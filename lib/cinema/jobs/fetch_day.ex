defmodule Cinema.Jobs.FetchDay do
  @moduledoc """
  Fetches one theater's programme for one date.

  One job per fetch, deliberately: a job per city would burst all its requests
  inside a single execution, which is what tripped AlloCiné's rate limit. At
  this granularity the queue's concurrency *is* the pace, and a rate-limited
  fetch snoozes without holding anything else up.

  Results are cached per theater and date, so the schedule is assembled from
  whatever has landed rather than waiting on the whole city.
  """

  use Oban.Worker,
    queue: :allocine,
    max_attempts: 5,
    # One job per theater and date; a repeat enqueue while one is pending is a
    # duplicate, not a refresh.
    unique: [
      period: 300,
      fields: [:worker, :args],
      states: Oban.Job.states() -- [:completed, :discarded, :cancelled]
    ]

  alias Cinema.{City, Store}

  @namespace :fetched_days

  # How long a fetched day stays usable. Matches the schedule cache: this is the
  # same data, just stored per theater instead of per city.
  @ttl :timer.hours(3)

  # Spacing between fetches. The queue limit caps concurrency, not rate: at one
  # job at a time each request still finishes in ~150ms, which is ~7/s and
  # enough to trip AlloCiné on a cold Paris. Sleeping here makes the rate
  # explicit and keeps a big city under their limit.
  @pace_ms 2_000

  # Long enough for a rate limit to lapse, short enough that a day still lands
  # while it is useful.
  @snooze_seconds 60

  @doc "Queues one job per theater and date for a city. Returns how many were queued."
  @spec enqueue(City.t(), keyword()) :: {:ok, non_neg_integer()}
  def enqueue(%City{} = city, opts \\ []) do
    days = Keyword.get(opts, :days, 7)
    today = Keyword.get(opts, :today, Cinema.today())
    source = source()

    jobs =
      for theater <- source.theaters(city),
          offset <- 0..(days - 1),
          date = Date.add(today, offset) do
        new(%{
          city_slug: city.slug,
          theater_id: theater.external_id,
          date: Date.to_iso8601(date)
        })
      end

    queued = jobs |> Enum.map(&Oban.insert/1) |> Enum.count(&match?({:ok, _job}, &1))

    {:ok, queued}
  end

  @doc "Screenings already fetched for a theater on a date, if still fresh."
  @spec fetched(City.t(), String.t(), Date.t()) :: {:ok, list()} | :miss
  def fetched(%City{} = city, theater_id, %Date{} = date) do
    Store.fetch(@namespace, key(city.slug, theater_id, date), @ttl)
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"city_slug" => slug, "theater_id" => id, "date" => date}}) do
    with {:ok, date} <- Date.from_iso8601(date),
         %City{} = city <- Cinema.find_city(slug),
         %{} = theater <- find_theater(city, id) do
      fetch_and_store(city, theater, date)
    else
      _unresolvable ->
        # The city's theater list changed since this job was queued — AlloCiné
        # dropped the cinema, or the directory refreshed mid-queue. Cancelling
        # says so in the job record instead of reporting a silent success.
        {:cancel, "no theater #{id} in #{slug}"}
    end
  end

  defp fetch_and_store(city, theater, date) do
    Process.sleep(pace_ms())

    case source().fetch_day(theater, date) do
      {:ok, screenings} ->
        Store.put(@namespace, key(city.slug, theater.external_id, date), screenings)
        :ok

      {:error, {:http_status, 429}} ->
        # Retrying a rate limit deepens it; wait for the window to pass instead.
        {:snooze, @snooze_seconds}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp find_theater(city, id) do
    source().theaters(city) |> Enum.find(&(&1.external_id == id))
  end

  defp key(slug, theater_id, date), do: "#{slug}/#{theater_id}/#{Date.to_iso8601(date)}"

  defp source, do: Application.get_env(:cinema, Cinema.Showtimes, [])[:source] || Cinema.Allocine

  defp pace_ms, do: Application.get_env(:cinema, __MODULE__, [])[:pace_ms] || @pace_ms
end

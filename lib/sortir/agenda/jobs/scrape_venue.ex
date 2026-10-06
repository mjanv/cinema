defmodule Sortir.Agenda.Jobs.ScrapeVenue do
  @moduledoc """
  Scrapes one venue and saves what it finds.

  One job per source, not per month: a source follows its own site's
  pagination, so how far ahead it reads is its own concern.

  Runs on the `:agenda` queue, separate from showtimes, so a slow or broken
  scraper cannot stall the cinema board. A 429 snoozes for `@snooze_seconds`
  rather than failing, since retrying a rate limit deepens it. A source module
  that no longer exists cancels the job instead of crash-looping.
  """

  use Oban.Worker,
    queue: :agenda,
    max_attempts: 5,
    unique: [
      period: 3600,
      fields: [:worker, :args],
      states: Oban.Job.states() -- [:completed, :discarded, :cancelled]
    ]

  alias Sortir.Agenda

  require Logger

  # Long enough for a rate limit to lapse; a month's programme is not urgent.
  @snooze_seconds 300

  @doc """
  Queues one job for a venue.

  One job, not one per month: a source follows its own site's pagination, so
  the job does not need to guess how the venue divides its programme.
  """
  @spec enqueue(module(), keyword()) :: {:ok, non_neg_integer()}
  def enqueue(source, _opts \\ []) do
    queued =
      %{source: to_string(source)}
      |> new()
      |> Oban.insert()
      |> case do
        {:ok, _job} -> 1
        {:error, _reason} -> 0
      end

    {:ok, queued}
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"source" => source}}) do
    case resolve(source) do
      {:ok, module} -> scrape(module)
      {:error, :unknown_source} -> {:cancel, "no such source: #{source}"}
    end
  end

  # No source named: this is the nightly cron entry. Fan out rather than list
  # the sources in the crontab, so `Sortir.Agenda.sources/0` stays the one
  # place a venue is registered.
  def perform(%Oban.Job{}) do
    {:ok, _queued} = Agenda.refresh()

    :ok
  end

  defp scrape(module) do
    with {:ok, venue} <- Agenda.upsert_venue(module.venue()),
         {:ok, scraped} <- module.fetch() do
      saved = Enum.count(scraped, &match?({:ok, _event}, Agenda.save(&1, venue)))

      Logger.info("Scraped #{saved}/#{length(scraped)} events: #{venue.name}")

      :ok
    else
      # Retrying a rate limit deepens it; wait for the window instead.
      {:error, {:http_status, 429}} -> {:snooze, @snooze_seconds}
      {:error, reason} -> {:error, reason}
    end
  end

  # A source is named in job args, so it may no longer exist by the time the
  # job runs; cancelling records why rather than crash-looping.
  defp resolve(name) do
    module = String.to_existing_atom(name)

    if Code.ensure_loaded?(module) and function_exported?(module, :fetch, 0) do
      {:ok, module}
    else
      {:error, :unknown_source}
    end
  rescue
    ArgumentError -> {:error, :unknown_source}
  end
end

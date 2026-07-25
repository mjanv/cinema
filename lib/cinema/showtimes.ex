defmodule Cinema.Showtimes do
  @moduledoc """
  Aggregates every configured `Cinema.Source` into a day → theater → movie tree,
  behind a lazy TTL cache.

  Screenings are returned exactly as the source reports them; showings that have
  already started are deliberately kept, so the page reflects the full day.
  """

  alias Cinema.{City, Screening, Theater}
  alias Cinema.Jobs.FetchDay

  @cache __MODULE__.Cache
  @ttl :timer.minutes(30)

  # While a source is down, retry on this shorter cadence instead of on every
  # request, so an outage does not turn into a request storm.
  @stale_retry_ms :timer.minutes(2)

  # Paris is 75 theaters x 7 days = 525 requests for one page load. Fanning
  # those out aggressively trips AlloCiné's rate limit, and the resulting 429s
  # hit every other city too. Keep the pipe narrow: a cold city takes a few
  # seconds longer, which the cache then amortises over hours.
  @max_concurrency 3

  # Beyond this many theaters a full-horizon fetch is too big a burst, so the
  # horizon is trimmed instead. Better a correct board covering fewer days than
  # a rate-limited one covering none.
  @large_city_theaters 20
  @large_city_days 3

  @type movie :: %{
          title: String.t(),
          original_title: String.t() | nil,
          runtime_min: pos_integer() | nil,
          genres: [String.t()],
          poster_url: String.t() | nil,
          versions: [Screening.version()],
          screenings: [Screening.t()]
        }

  @type theater :: %{id: String.t(), name: String.t(), movies: [movie()]}
  @type day :: %{date: Date.t(), theaters: [theater()]}

  @doc """
  The aggregated schedule, served from cache when a fresh entry exists.

  Options: `:days` (default from config), `:today`, `:refresh` to bypass the cache.
  """
  @spec list_days(City.t(), keyword()) :: [day()]
  def list_days(%City{} = city, opts \\ []) do
    days = Keyword.get(opts, :days, config(:days, 7))
    today = Keyword.get(opts, :today, today())
    refresh? = Keyword.get(opts, :refresh, false)

    with false <- refresh?,
         {:ok, entry} <- read_cache(city, :fresh) do
      entry.days
    else
      _reload -> reload(city, today, days)
    end
  end

  @doc """
  What the schedule currently holds, including whether it is stale.

  `stale?` is true when the last fetch failed and the previous schedule is being
  served instead, so the UI can say so rather than silently showing old times.
  """
  @spec status(City.t()) :: %{days: [day()], fetched_at: DateTime.t() | nil, stale?: boolean()}
  def status(%City{} = city) do
    case read_cache(city, :any) do
      {:ok, entry} ->
        %{days: entry.days, fetched_at: entry.fetched_at, stale?: entry.stale?}

      :miss ->
        %{days: [], fetched_at: nil, stale?: false}
    end
  end

  @doc """
  Today's date in Grenoble.

  The board must roll over at local midnight; UTC would advance it two hours
  early in summer and hide the late showings.
  """
  @spec today(DateTime.t()) :: Date.t()
  def today(now \\ DateTime.utc_now()), do: now |> local() |> DateTime.to_date()

  @doc "The current time in Grenoble, for reading the board against."
  @spec now(DateTime.t()) :: DateTime.t()
  def now(at \\ DateTime.utc_now()), do: local(at)

  # How long a started screening stays worth showing: you may still be in it,
  # and a film that began 10 minutes ago is not a reason to skip the whole day.
  @grace_minutes 30

  @doc """
  Which day the board should open on.

  Today, until its last screening started more than #{@grace_minutes} minutes
  ago — then tomorrow, because a day whose programme is spent is not a useful
  landing page. Falls back to today when there is no later day to move to.
  """
  @spec opening_date([day()], NaiveDateTime.t()) :: Date.t() | nil
  def opening_date([], _now), do: nil

  def opening_date(days, now) do
    Enum.find_value(days, hd(days).date, fn day ->
      if worth_showing?(day, now), do: day.date
    end)
  end

  defp worth_showing?(day, now) do
    case last_start(day) do
      nil -> false
      last -> NaiveDateTime.diff(now, last, :minute) <= @grace_minutes
    end
  end

  defp last_start(day) do
    for theater <- day.theaters, movie <- theater.movies, screening <- movie.screenings do
      screening.starts_at
    end
    |> case do
      [] -> nil
      starts -> Enum.max(starts, NaiveDateTime)
    end
  end

  defp local(at) do
    case DateTime.shift_zone(at, timezone()) do
      {:ok, local} -> local
      {:error, _no_tzdata} -> at
    end
  end

  # A source outage must not evict a good schedule: an empty fetch keeps the
  # previous days and only marks them stale.
  defp reload(city, today, days) do
    fetched = load(city, today, days)

    if empty?(fetched) do
      case read_cache(city, :any) do
        {:ok, %{days: [_ | _] = previous}} -> put_cache(city, previous, stale?: true).days
        _no_previous -> put_cache(city, fetched, stale?: false).days
      end
    else
      put_cache(city, fetched, stale?: false).days
    end
  end

  defp empty?(days), do: Enum.all?(days, &(&1.theaters == []))

  # Fetching goes through Oban: one job per theater and date, paced by the
  # queue. `load` assembles whatever those jobs have already cached and queues
  # the rest, so a cold city returns partial data immediately and fills in
  # rather than blocking on hundreds of requests.
  defp load(city, today, days) do
    source = config(:source, Cinema.Allocine)
    theaters = source.theaters(city)

    FetchDay.enqueue(city, days: days, today: today)

    build(theaters, &fetch_cached(city, &1, &2), today, days)
  end

  defp fetch_cached(city, theater, date) do
    case FetchDay.fetched(city, theater.external_id, date) do
      {:ok, screenings} -> {:ok, screenings}
      :miss -> {:ok, []}
    end
  end

  # A big city multiplied by a long horizon is what trips the rate limit.
  @doc false
  def horizon(theater_count, days) when theater_count > @large_city_theaters,
    do: min(days, @large_city_days)

  def horizon(_theater_count, days), do: days

  @doc """
  Pure aggregation: fans out `fetch` over theaters × dates and shapes the tree.

  `fetch` receives a `Cinema.Theater` and a `Date` and returns
  `{:ok, screenings}` or `{:error, reason}`; a failing theater is simply absent.
  """
  @spec build(
          [Theater.t()],
          (Theater.t(), Date.t() -> {:ok, [Screening.t()]} | {:error, term()}),
          Date.t(),
          pos_integer()
        ) :: [day()]
  def build(theaters, fetch, today, days) do
    dates = Enum.map(0..(days - 1), &Date.add(today, &1))

    screenings =
      for date <- dates, theater <- theaters, do: {theater, date}

    screenings
    |> Task.async_stream(
      fn {theater, date} ->
        case fetch.(theater, date) do
          {:ok, screenings} -> {theater, date, screenings}
          {:error, _reason} -> {theater, date, []}
        end
      end,
      max_concurrency: config(:max_concurrency, @max_concurrency),
      timeout: 30_000,
      on_timeout: :kill_task,
      ordered: true
    )
    |> Enum.flat_map(fn
      {:ok, {theater, date, screenings}} -> [{theater, date, screenings}]
      {:exit, _reason} -> []
    end)
    |> group_by_day(theaters, dates)
  end

  defp group_by_day(entries, theaters, dates) do
    order = theaters |> Enum.map(& &1.external_id) |> Enum.with_index() |> Map.new()

    by_date = Enum.group_by(entries, fn {_theater, date, _screenings} -> date end)

    Enum.map(dates, fn date ->
      theaters =
        by_date
        |> Map.get(date, [])
        |> Enum.reject(fn {_theater, _date, screenings} -> screenings == [] end)
        |> Enum.sort_by(fn {theater, _date, _screenings} ->
          Map.get(order, theater.external_id, 999)
        end)
        |> Enum.map(fn {theater, _date, screenings} ->
          %{id: theater.external_id, name: theater.name, movies: group_movies(screenings)}
        end)

      %{date: date, theaters: theaters}
    end)
  end

  @doc """
  Inverts a day's tree from theater → movie into movie → theater.

  Answers "where can I see this film?" rather than "what's on at this cinema?".
  Movies are ordered by their earliest screening, so the day still reads
  chronologically; within a movie, cinemas are ordered the same way.
  """
  @spec by_movie(day()) :: [
          %{
            title: String.t(),
            original_title: String.t() | nil,
            runtime_min: pos_integer() | nil,
            genres: [String.t()],
            poster_url: String.t() | nil,
            versions: [Screening.version()],
            theaters: [%{id: String.t(), name: String.t(), screenings: [Screening.t()]}]
          }
        ]
  def by_movie(%{theaters: theaters}) do
    theaters
    |> Enum.flat_map(fn theater ->
      Enum.map(theater.movies, &{theater, &1})
    end)
    |> Enum.group_by(fn {_theater, movie} -> movie.title end)
    |> Enum.map(fn {title, pairs} ->
      screenings = Enum.flat_map(pairs, fn {_theater, movie} -> movie.screenings end)

      venues =
        pairs
        |> Enum.map(fn {theater, movie} ->
          %{id: theater.id, name: theater.name, screenings: movie.screenings}
        end)
        |> Enum.sort_by(&earliest/1, NaiveDateTime)

      %{
        title: title,
        original_title: first_present(pairs, & &1.original_title),
        runtime_min: first_present(pairs, & &1.runtime_min),
        genres: first_present(pairs, fn movie -> presence(movie.genres) end) || [],
        poster_url: first_present(pairs, & &1.poster_url),
        versions: screenings |> Enum.map(& &1.version) |> Enum.uniq() |> Enum.sort(),
        theaters: venues
      }
    end)
    |> Enum.sort_by(&earliest/1, NaiveDateTime)
  end

  def by_movie(nil), do: []

  defp earliest(%{screenings: screenings}),
    do: screenings |> Enum.map(& &1.starts_at) |> Enum.min(NaiveDateTime)

  defp earliest(%{theaters: theaters}),
    do: theaters |> Enum.map(&earliest/1) |> Enum.min(NaiveDateTime)

  defp first_present(pairs, fun) do
    Enum.find_value(pairs, fn {_theater, movie} -> fun.(movie) end)
  end

  defp presence([]), do: nil
  defp presence(list), do: list

  @doc """
  One film's whole run: every day it plays, and where, across the schedule.

  Answers "when can I catch this at all?" rather than "what is on today". Days
  with no showing are dropped, so the result is only the dates that matter.
  Returns nil when the film is not in the schedule.
  """
  @spec film([day()], String.t()) :: map() | nil
  def film(days, title) do
    matching =
      days
      |> Enum.map(fn day -> {day.date, Enum.find(by_movie(day), &(&1.title == title))} end)
      |> Enum.reject(fn {_date, movie} -> is_nil(movie) end)

    case matching do
      [] ->
        nil

      [{_date, first} | _rest] ->
        %{
          title: first.title,
          original_title: first.original_title,
          runtime_min: first.runtime_min,
          genres: first.genres,
          poster_url: first.poster_url,
          days:
            Enum.map(matching, fn {date, movie} ->
              %{date: date, theaters: movie.theaters}
            end)
        }
    end
  end

  defp group_movies(screenings) do
    screenings
    |> Enum.group_by(& &1.title)
    |> Enum.map(fn {title, group} ->
      sorted = Enum.sort_by(group, & &1.starts_at, NaiveDateTime)
      first = hd(sorted)

      %{
        title: title,
        original_title: first.original_title,
        runtime_min: first.runtime_min,
        genres: first.genres,
        poster_url: first.poster_url,
        versions: sorted |> Enum.map(& &1.version) |> Enum.uniq() |> Enum.sort(),
        screenings: sorted
      }
    end)
    |> Enum.sort_by(fn movie -> hd(movie.screenings).starts_at end, NaiveDateTime)
  end

  # --- cache -------------------------------------------------------------

  @doc false
  def init_cache, do: Cinema.Store.open(@cache)

  @doc false
  def reset_cache do
    init_cache()
    Cinema.Store.clear(@cache)
  end

  # `:fresh` respects the TTL; `:any` returns the last schedule whatever its age,
  # which is what lets an outage fall back instead of blanking the page.
  defp read_cache(city, mode) do
    key = cache_key(city)

    # A stale entry is retried sooner: an outage should recover quickly without
    # turning every page load into a request storm.
    ttl =
      case Cinema.Store.fetch(key_table(), key, :infinity) do
        {:ok, %{stale?: true}} -> @stale_retry_ms
        _otherwise -> config(:cache_ttl_ms, @ttl)
      end

    ttl = if mode == :any, do: :infinity, else: ttl

    Cinema.Store.fetch(key_table(), key, ttl)
  end

  defp key_table, do: @cache

  defp put_cache(city, days, opts) do
    stale? = Keyword.fetch!(opts, :stale?)

    entry = %{
      days: days,
      stale?: stale?,
      fetched_at: if(stale?, do: last_fetched_at(city), else: DateTime.utc_now())
    }

    Cinema.Store.put(@cache, cache_key(city), entry)
    entry
  end

  defp last_fetched_at(city) do
    case read_cache(city, :any) do
      {:ok, %{fetched_at: at}} -> at
      :miss -> DateTime.utc_now()
    end
  end

  # Keyed per city: without this, switching city would serve the previous
  # city's schedule from cache.
  defp cache_key(%City{slug: slug}), do: {:days, slug}

  defp timezone, do: config(:timezone, "Europe/Paris")

  defp config(key, default), do: Application.get_env(:cinema, __MODULE__, [])[key] || default
end

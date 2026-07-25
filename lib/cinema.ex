defmodule Cinema do
  @moduledoc """
  The public interface of the showtimes domain.

  `CinemaWeb` talks to this module and nothing else: the aggregation, caching
  and source modules behind it are private. That keeps the web layer unaware of
  where showtimes come from, so swapping or adding a `Cinema.Source` never
  reaches into a template.

  Structs (`Cinema.Screening`, `Cinema.Theater`) are shared data and may be
  referenced directly; the modules that *operate* on them may not.
  """

  alias Cinema.{City, Showtimes}

  @typedoc "A day's programme, grouped by cinema."
  @type day :: Showtimes.day()

  @typedoc "The schedule plus how current it is."
  @type schedule :: %{days: [day()], fetched_at: DateTime.t() | nil, stale?: boolean()}

  @doc """
  The coming days' showtimes, with the freshness of the underlying data.

  Served from cache when it is current. `stale?` means the last fetch failed and
  the previous schedule is standing in for it, so the UI can say so.

  Options: `:days` to override the horizon, `:today` to pin the first day.
  """
  @spec schedule(City.t(), keyword()) :: schedule()
  def schedule(%City{} = city, opts \\ []) do
    days = Showtimes.list_days(city, opts)
    %{Showtimes.status(city) | days: days}
  end

  @doc """
  Re-fetches from every source, bypassing the cache, and returns the schedule.

  A failing fetch keeps the previous schedule and marks it stale rather than
  emptying the board.
  """
  @spec refresh(City.t(), keyword()) :: schedule()
  def refresh(%City{} = city, opts \\ []), do: schedule(city, Keyword.put(opts, :refresh, true))

  @doc "Every city the board can show, in display order."
  @spec cities() :: [City.t()]
  def cities, do: source().cities()

  @doc """
  The city matching `slug`, or the configured default when it is unknown.

  Returns nil only when no city can be resolved at all (AlloCiné unreachable on
  a cold cache), which the UI renders as an explicit error rather than an
  empty board.
  """
  @spec find_city(String.t() | nil) :: City.t() | nil
  def find_city(slug) do
    cities = cities()

    Enum.find(cities, fn city -> city.slug == slug end) ||
      Enum.find(cities, fn city -> city.slug == default_city_slug() end) ||
      List.first(cities)
  end

  defp default_city_slug,
    do: Application.get_env(:cinema, Showtimes, [])[:default_city] || "grenoble"

  defp source, do: Application.get_env(:cinema, Showtimes, [])[:source] || Cinema.Allocine

  @doc """
  Regroups one day around films, listing every cinema showing each.

  Answers "where can I see this?" rather than "what's on here?".
  """
  @spec by_movie(day() | nil) :: [map()]
  defdelegate by_movie(day), to: Showtimes

  @doc "Today's date in Grenoble, which is what the board rolls over on."
  @spec today() :: Date.t()
  defdelegate today(), to: Showtimes

  @doc "The current time in Grenoble, for reading the board against."
  @spec now() :: DateTime.t()
  defdelegate now(), to: Showtimes

  @doc """
  Which day the board should open on: today, unless its programme is spent.

  Once the last screening of the day started over half an hour ago, tomorrow is
  the more useful landing page.
  """
  @spec opening_date([day()], NaiveDateTime.t()) :: Date.t() | nil
  defdelegate opening_date(days, now), to: Showtimes

  @doc false
  defdelegate init_cache(), to: Showtimes

  @doc false
  defdelegate reset_cache(), to: Showtimes
end

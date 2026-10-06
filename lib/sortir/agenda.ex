defmodule Sortir.Agenda do
  @moduledoc """
  The public interface of the events domain.

  Aggregates cultural events — concerts, performances, exhibitions, tours —
  scraped from venue websites. `SortirWeb` calls this module and nothing else;
  the schemas, scrapers and queries behind it are internal.

  ## Storage

  Events accumulate rather than mirror. `save/2` upserts on `(source,
  external_id)`, so a venue may be re-scraped as often as needed without
  duplicating events or dropping past ones.

  An event is a production; an `Occurrence` places it at a date, time and
  venue. A show on three nights is one event with three occurrences. An
  exhibition has none, and is placed instead by its `runs_from`/`runs_to`
  range.

  ## Reading

  `on/1` returns entries for a single date. `days/2` covers a fixed range and
  omits empty days. `upcoming/2` returns the next `n` days that have something
  on, skipping quiet spells such as a venue's summer closure.

  ## Scraping

  `sources/0` lists the scraper modules; `refresh/0` queues one job per source.
  """

  import Ecto.Query

  alias Sortir.Agenda.{Event, Occurrence, Venue}
  alias Sortir.Agenda.Jobs.ScrapeVenue
  alias Sortir.Core.{Clock, Repo}

  @typedoc """
  One thing happening on a day.

  `occurrence` is the earliest showing, `occurrences` every showing of it that
  day — a tour run six times is one entry with six of them. An exhibition has
  neither: it is placed by its run instead.
  """
  @type entry :: %{
          event: Event.t(),
          occurrence: Occurrence.t() | nil,
          occurrences: [Occurrence.t()],
          venue: Venue.t() | nil
        }

  # Every venue we scrape. Adding one is this line plus the module: the job,
  # the persistence and the board are all indifferent to which source they
  # are handling.
  @sources [
    Sortir.Agenda.Sources.BelleElectrique,
    Sortir.Agenda.Sources.Tmg,
    Sortir.Agenda.Sources.Musee,
    Sortir.Agenda.Sources.Mc2
  ]

  @doc "The scrapers this agenda is built from."
  # No @spec: the list is a compile-time constant, so Dialyzer infers the three
  # literal modules and rejects the `[module()]` contract as too broad.
  def sources, do: @sources

  @doc """
  Queues a scrape of every source.

  One job per venue, on a queue with a limit of one, so the venues are read
  in sequence rather than hammered in parallel.

  Returns how many jobs were actually queued: uniqueness means a source
  already waiting is not queued twice.
  """
  @spec refresh() :: {:ok, non_neg_integer()}
  def refresh do
    queued =
      @sources
      |> Enum.map(&ScrapeVenue.enqueue/1)
      |> Enum.sum_by(fn {:ok, count} -> count end)

    {:ok, queued}
  end

  @typedoc "A venue with what it currently has programmed."
  @type listed_venue :: %{
          venue: Venue.t(),
          events: non_neg_integer(),
          occurrences: non_neg_integer(),
          next: Date.t() | nil,
          last: Date.t() | nil
        }

  @doc """
  Every venue, with a count of what it has programmed.

  A venue with nothing on is still listed: a scraper that ran and found
  nothing must be distinguishable from one that was never added. Ordered by
  what is coming up soonest, with the empty ones last.
  """
  @spec venues() :: [listed_venue()]
  def venues do
    counts =
      from(o in Occurrence,
        group_by: o.venue_id,
        select: %{
          venue_id: o.venue_id,
          occurrences: count(o.id),
          events: count(o.event_id, :distinct),
          last: max(o.starts_at)
        }
      )
      |> Repo.all()
      |> Map.new(&{&1.venue_id, &1})

    next = next_dates()

    Venue
    |> order_by([v], asc: v.name)
    |> Repo.all()
    |> Enum.map(fn venue ->
      counted = Map.get(counts, venue.id, %{occurrences: 0, events: 0, last: nil})

      %{
        venue: venue,
        events: counted.events,
        occurrences: counted.occurrences,
        next: next[venue.id],
        last: counted.last && counted.last |> Clock.to_local() |> DateTime.to_date()
      }
    end)
    |> Enum.sort_by(& &1.next, fn
      nil, nil -> true
      nil, _date -> false
      _date, nil -> true
      a, b -> Date.compare(a, b) != :gt
    end)
  end

  # The soonest occurrence still to come, per venue. A venue whose programme
  # has entirely passed sorts with the empty ones.
  defp next_dates do
    {start_at, _end} = day_bounds(Clock.today())

    from(o in Occurrence,
      where: o.starts_at >= ^start_at,
      group_by: o.venue_id,
      select: {o.venue_id, min(o.starts_at)}
    )
    |> Repo.all()
    |> Map.new(fn {venue_id, at} ->
      {venue_id, at |> Clock.to_local() |> DateTime.to_date()}
    end)
  end

  @doc """
  When an event was last written, or `nil` if the agenda is empty.

  Reports on the data rather than on the jobs: a scrape that ran but saved
  nothing has not refreshed the agenda.
  """
  @spec scraped_at() :: DateTime.t() | nil
  def scraped_at, do: Repo.one(from(e in Event, select: max(e.updated_at)))

  @doc "Creates a venue or updates the one with this slug."
  @spec upsert_venue(map()) :: {:ok, Venue.t()} | {:error, Ecto.Changeset.t()}
  def upsert_venue(attrs) do
    case Repo.get_by(Venue, slug: attrs.slug) do
      nil -> %Venue{}
      existing -> existing
    end
    |> Venue.changeset(attrs)
    |> Repo.insert_or_update()
  end

  @doc """
  Stores one scraped event and its occurrence, if it has one.

  Identity is `(source, external_id)` for the event and
  `(event, venue, starts_at)` for the occurrence, so re-scraping updates in
  place rather than accumulating duplicates.
  """
  @spec save(map(), Venue.t()) :: {:ok, Event.t()} | {:error, Ecto.Changeset.t()}
  def save(%{event: event_attrs} = scraped, %Venue{} = venue) do
    with {:ok, event} <- upsert_event(event_attrs),
         :ok <- upsert_occurrence(scraped[:occurrence], event, venue) do
      {:ok, event}
    end
  end

  defp upsert_event(attrs) do
    attrs
    |> find_event()
    |> Event.changeset(attrs)
    |> Repo.insert_or_update()
  end

  # A scraper that could not identify an event returns nil here; look nothing
  # up and let the changeset report it, rather than crashing the whole fetch.
  defp find_event(%{source: source, external_id: id}) when is_binary(id) do
    Repo.get_by(Event, source: to_string(source), external_id: id) || %Event{}
  end

  defp find_event(_unidentified), do: %Event{}

  defp upsert_occurrence(nil, _event, _venue), do: :ok

  defp upsert_occurrence(attrs, event, venue) do
    starts_at = Clock.to_utc(attrs[:starts_at])

    existing =
      Repo.get_by(Occurrence, event_id: event.id, venue_id: venue.id, starts_at: starts_at)

    attrs =
      attrs
      |> Map.put(:event_id, event.id)
      |> Map.put(:venue_id, venue.id)
      |> Map.put(:starts_at, starts_at)
      |> Map.update(:ends_at, nil, &Clock.to_utc/1)

    case (existing || %Occurrence{}) |> Occurrence.changeset(attrs) |> Repo.insert_or_update() do
      {:ok, _occurrence} -> :ok
      {:error, changeset} -> {:error, changeset}
    end
  end

  @doc """
  What is on for a date.

  Occurrences starting that day, plus events whose run spans it — an exhibition
  has no occurrence and would otherwise never appear.
  """
  @spec on(Date.t()) :: [entry()]
  def on(%Date{} = date) do
    (scheduled(date) ++ running(date)) |> sort_entries()
  end

  @typedoc "A day's programme."
  @type day :: %{date: Date.t(), entries: [entry()]}

  @doc """
  Days with something on, from `from` for `count` days.

  Empty days are omitted: an agenda that renders a heading for a day with
  nothing on wastes the reader's attention. One query for the range rather than
  one per day.
  """
  @spec days(Date.t(), pos_integer()) :: [day()]
  def days(%Date{} = from, count) when count > 0 do
    to = Date.add(from, count - 1)

    scheduled_between(from, to)
    |> Enum.concat(running_between(from, to))
    |> Enum.group_by(& &1.date, & &1.entry)
    |> Enum.map(fn {date, entries} -> %{date: date, entries: sort_entries(entries)} end)
    |> Enum.sort_by(& &1.date, Date)
  end

  @doc """
  The next `count` days that have something on, from `from` onwards.

  Unlike `days/2`, this does not stop at a fixed horizon. A venue closes for
  the summer; looking a fortnight ahead then shows an empty page during exactly
  the spell when you want to know what is coming back.
  """
  @spec upcoming(Date.t(), pos_integer()) :: [day()]
  def upcoming(%Date{} = from, count) when count > 0 do
    case last_programmed_date() do
      nil ->
        []

      last ->
        # Everything already happened: nothing is upcoming.
        case Date.diff(last, from) + 1 do
          span when span > 0 -> from |> days(span) |> Enum.take(count)
          _all_past -> []
        end
    end
  end

  defp last_programmed_date do
    latest_occurrence = Repo.one(from(o in Occurrence, select: max(o.starts_at)))
    latest_run = Repo.one(from(e in Event, select: max(e.runs_to)))

    [latest_occurrence && latest_occurrence |> Clock.to_local() |> DateTime.to_date(), latest_run]
    |> Enum.reject(&is_nil/1)
    |> case do
      [] -> nil
      dates -> Enum.max(dates, Date)
    end
  end

  defp scheduled_between(from, to) do
    {start_at, _end} = day_bounds(from)
    {_start, end_at} = day_bounds(to)

    from(o in Occurrence,
      join: e in assoc(o, :event),
      join: v in assoc(o, :venue),
      where: o.starts_at >= ^start_at and o.starts_at < ^end_at,
      order_by: [asc: o.starts_at],
      preload: [event: e, venue: v]
    )
    |> Repo.all()
    |> Enum.map(fn occurrence ->
      %{
        date: occurrence.starts_at |> Clock.to_local() |> DateTime.to_date(),
        entry: %{
          event: occurrence.event,
          occurrence: occurrence,
          occurrences: [occurrence],
          venue: occurrence.venue
        }
      }
    end)
  end

  # An exhibition appears on every day of its run inside the window.
  defp running_between(from, to) do
    from(e in Event,
      where: not is_nil(e.runs_from) and e.runs_from <= ^to,
      where: is_nil(e.runs_to) or e.runs_to >= ^from,
      order_by: [asc: e.title]
    )
    |> Repo.all()
    |> Enum.flat_map(fn event ->
      first = Enum.max([event.runs_from, from], Date)
      last = Enum.min([event.runs_to || to, to], Date)

      Date.range(first, last)
      |> Enum.map(
        &%{date: &1, entry: %{event: event, occurrence: nil, occurrences: [], venue: nil}}
      )
    end)
  end

  # Timed entries first, in order; a run has no time and sorts after.
  defp sort_entries(entries) do
    entries
    |> group_repeats()
    |> Enum.sort_by(fn
      %{occurrence: nil} -> {1, nil}
      %{occurrence: occurrence} -> {0, DateTime.to_unix(occurrence.starts_at)}
    end)
  end

  # A museum runs the same tour six times in an afternoon, a cinema screens a
  # film twice. Six near-identical rows differing only by a time is noise: it
  # is one thing to go to, with several start times.
  #
  # Keyed on the room as well as the event, because the same production in two
  # rooms is two different offerings.
  defp group_repeats(entries) do
    entries
    |> Enum.group_by(&repeat_key/1)
    |> Enum.map(fn {_key, [first | _rest] = group} ->
      occurrences =
        group
        |> Enum.map(& &1.occurrence)
        |> Enum.reject(&is_nil/1)
        |> Enum.sort_by(&DateTime.to_unix(&1.starts_at))

      # `occurrence` stays the earliest, so ordering and every existing reader
      # keep working; `occurrences` is the addition.
      %{first | occurrence: List.first(occurrences), occurrences: occurrences}
    end)
  end

  # An exhibition has no occurrence and no room; keep each one distinct.
  defp repeat_key(%{occurrence: nil, event: event}), do: {:run, event.id}

  defp repeat_key(%{event: event, venue: venue, occurrence: occurrence}) do
    {:timed, event.id, venue && venue.id, occurrence.room}
  end

  defp scheduled(date) do
    {from, to} = day_bounds(date)

    from(o in Occurrence,
      join: e in assoc(o, :event),
      join: v in assoc(o, :venue),
      where: o.starts_at >= ^from and o.starts_at < ^to,
      order_by: [asc: o.starts_at],
      preload: [event: e, venue: v]
    )
    |> Repo.all()
    |> Enum.map(&%{event: &1.event, occurrence: &1, occurrences: [&1], venue: &1.venue})
  end

  defp running(date) do
    from(e in Event,
      where: not is_nil(e.runs_from) and e.runs_from <= ^date,
      where: is_nil(e.runs_to) or e.runs_to >= ^date,
      order_by: [asc: e.title]
    )
    |> Repo.all()
    |> Enum.map(&%{event: &1, occurrence: nil, occurrences: [], venue: nil})
  end

  defp day_bounds(date) do
    {:ok, start_of_day} = NaiveDateTime.new(date, ~T[00:00:00])

    {Clock.to_utc(start_of_day), Clock.to_utc(NaiveDateTime.add(start_of_day, 1, :day))}
  end
end

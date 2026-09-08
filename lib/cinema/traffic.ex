defmodule Cinema.Traffic do
  @moduledoc """
  A hit counter: one row per hour, per page, per city, on the SQLite the app
  already has.

  Aggregating on write is what keeps this small. A view is an upsert that adds
  1 to an existing row, so a year of traffic is a few thousand rows rather than
  one per visit, a timeseries is a `GROUP BY` over them, and there is nothing
  to prune and no second service to run.

  Only *connected* views are counted, and the LiveViews count themselves rather
  than a plug counting requests. That is deliberate on both halves. A plug sees
  the dead render, which every crawler also gets and which does not yet know
  which city it is about to show; the LiveView sees a real browser that stayed,
  and knows the city it actually put on screen. The same call catches the
  in-page city switches that never reach the router at all — most of the city
  signal, since the picker patches rather than reloads. The cost is that a
  visitor whose socket never connects goes uncounted; the gain is that
  "usage" means people, not robots.

  Nothing about the visitor is recorded — no address, no session, no user
  agent. The table cannot say who came, only how often a board was looked at,
  which is all "is anyone using this?" needs.

  Writes degrade to a no-op, like `Cinema.Store`: a locked or unwritable
  database must cost a statistic, never a page.
  """

  import Ecto.Query

  require Logger

  alias Cinema.Repo
  alias Cinema.Traffic.Hit

  @typedoc "A point in a series, or a row in a breakdown: a label and its views."
  @type point :: {String.t(), non_neg_integer()}

  # A day is the first 10 characters of a bucket ("2026-09-08"), an hour all 13.
  @day "substr(?, 1, 10)"

  @doc """
  Counts one view of `path` showing `city`.

  `city` is a slug, or `""` for a page that is not about a city.
  """
  @spec hit(String.t(), String.t()) :: :ok
  def hit(path, city \\ "") when is_binary(path) and is_binary(city) do
    Repo.insert_all(
      Hit,
      [%{bucket: bucket(DateTime.utc_now()), path: path, city: city, count: 1}],
      on_conflict: [inc: [count: 1]],
      conflict_target: [:bucket, :path, :city]
    )

    :ok
  rescue
    error ->
      Logger.warning("Traffic write failed for #{path}: #{inspect(error)}")
      :ok
  catch
    :exit, _reason -> :ok
  end

  @doc """
  Views per hour over the last `hours` hours, oldest first, ending on the
  current hour.

  Quiet hours come back as zeroes rather than as missing points: a chart has to
  draw them either way, and a gap the caller has to notice is a gap the caller
  will forget to notice.
  """
  @spec hourly(pos_integer()) :: [point()]
  def hourly(hours \\ 48) do
    totals =
      -hours
      |> window(:hour)
      |> group_by([h], h.bucket)
      |> select([h], {h.bucket, sum(h.count)})
      |> all()
      |> Map.new()

    now = DateTime.utc_now()

    (hours - 1)..0//-1
    |> Enum.map(&bucket(DateTime.add(now, -&1, :hour)))
    |> fill(totals)
  end

  @doc "Views per day over the last `days` days, oldest first, ending today."
  @spec daily(pos_integer()) :: [point()]
  def daily(days \\ 30) do
    totals =
      -days
      |> window(:day)
      |> group_by([h], fragment(@day, h.bucket))
      |> select([h], {fragment(@day, h.bucket), sum(h.count)})
      |> all()
      |> Map.new()

    today = Date.utc_today()

    (days - 1)..0//-1
    |> Enum.map(&Date.to_iso8601(Date.add(today, -&1)))
    |> fill(totals)
  end

  @doc """
  Views per city over the last `days` days, busiest first.

  Pages that show no city are left out — they are not a city, and listing them
  would put the dashboard's own traffic at the top of the ranking.
  """
  @spec cities(pos_integer()) :: [point()]
  def cities(days \\ 30) do
    -days
    |> window(:day)
    |> where([h], h.city != "")
    |> group_by([h], h.city)
    |> order_by([h], desc: sum(h.count), asc: h.city)
    |> select([h], {h.city, sum(h.count)})
    |> all()
  end

  @doc "Views per page over the last `days` days, busiest first."
  @spec paths(pos_integer()) :: [point()]
  def paths(days \\ 30) do
    -days
    |> window(:day)
    |> group_by([h], h.path)
    |> order_by([h], desc: sum(h.count), asc: h.path)
    |> select([h], {h.path, sum(h.count)})
    |> all()
  end

  @doc "Every view over the last `days` days."
  @spec total(pos_integer()) :: non_neg_integer()
  def total(days \\ 30) do
    -days
    |> window(:day)
    |> select([h], sum(h.count))
    |> one()
  end

  # Buckets sort as strings, so a window is a plain `>=` on the earliest one.
  defp window(amount, unit) do
    floor = bucket(DateTime.add(DateTime.utc_now(), amount, unit))

    from(h in Hit, where: h.bucket >= ^floor)
  end

  defp fill(buckets, totals), do: Enum.map(buckets, &{&1, Map.get(totals, &1, 0)})

  defp bucket(%DateTime{} = at) do
    at
    |> DateTime.to_iso8601()
    |> binary_part(0, 13)
  end

  defp all(query) do
    Repo.all(query)
  rescue
    error ->
      Logger.warning("Traffic read failed: #{inspect(error)}")
      []
  end

  defp one(query) do
    Repo.one(query) || 0
  rescue
    error ->
      Logger.warning("Traffic read failed: #{inspect(error)}")
      0
  end
end

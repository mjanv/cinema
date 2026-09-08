defmodule Cinema.Traffic do
  @moduledoc """
  A hit counter: one row per hour per path, on the SQLite the app already has.

  Aggregating on write is what keeps this small. A pageview is an upsert that
  adds 1 to an existing row, so a year of traffic is a few thousand rows rather
  than one per visit, and a timeseries is a `GROUP BY` over them. Nothing needs
  pruning and there is no second service to run.

  Nothing about the visitor is recorded — no address, no session, no user
  agent. The table cannot say who came, only how often a path was served, which
  is all "is anyone using this?" needs.

  Writes degrade to a no-op, like `Cinema.Store`: a locked or unwritable
  database must cost a statistic, never a page.
  """

  import Ecto.Query

  require Logger

  alias Cinema.Repo
  alias Cinema.Traffic.Hit

  @typedoc "A point in a series: the bucket it covers and its pageviews."
  @type point :: {String.t(), non_neg_integer()}

  # A day is 10 characters of the bucket ("2026-09-08"), an hour is all 13.
  @day "substr(?, 1, 10)"

  @doc "Counts one pageview of `path` in the current hour."
  @spec hit(String.t()) :: :ok
  def hit(path) when is_binary(path) do
    Repo.insert_all(
      Hit,
      [%{bucket: bucket(DateTime.utc_now()), path: path, count: 1}],
      on_conflict: [inc: [count: 1]],
      conflict_target: [:bucket, :path]
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
  Pageviews per day over the last `days` days, oldest first.

  Days with no traffic have no row: a chart that needs a flat line through them
  should fill the gaps itself rather than have the query invent zeroes.
  """
  @spec daily(pos_integer()) :: [point()]
  def daily(days \\ 30) do
    from(h in since(-days, :day),
      group_by: fragment(@day, h.bucket),
      order_by: fragment(@day, h.bucket),
      select: {fragment(@day, h.bucket), sum(h.count)}
    )
    |> all()
  end

  @doc "Pageviews per hour over the last `hours` hours, oldest first."
  @spec hourly(pos_integer()) :: [point()]
  def hourly(hours \\ 48) do
    from(h in since(-hours, :hour),
      group_by: h.bucket,
      order_by: h.bucket,
      select: {h.bucket, sum(h.count)}
    )
    |> all()
  end

  @doc "Pageviews per path over the last `days` days, busiest first."
  @spec paths(pos_integer()) :: [point()]
  def paths(days \\ 30) do
    from(h in since(-days, :day),
      group_by: h.path,
      order_by: [desc: sum(h.count)],
      select: {h.path, sum(h.count)}
    )
    |> all()
  end

  # Buckets sort as strings, so a window is a plain `>=` on the earliest one.
  defp since(amount, unit) do
    floor = bucket(DateTime.add(DateTime.utc_now(), amount, unit))

    from(h in Hit, where: h.bucket >= ^floor)
  end

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
end

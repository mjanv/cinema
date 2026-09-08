defmodule Cinema.TrafficTest do
  use Cinema.DataCase, async: false

  alias Cinema.Repo
  alias Cinema.Traffic
  alias Cinema.Traffic.Hit

  setup do
    Repo.delete_all(Hit)
    :ok
  end

  test "counts a pageview" do
    Traffic.hit("/")

    assert [{_day, 1}] = Traffic.daily()
  end

  test "adds repeat views to the same row rather than inserting a new one" do
    for _ <- 1..3, do: Traffic.hit("/")

    assert [{_day, 3}] = Traffic.daily()
    assert Repo.aggregate(Hit, :count) == 1
  end

  test "keeps paths apart" do
    Traffic.hit("/")
    Traffic.hit("/")
    Traffic.hit("/health")

    assert Traffic.paths() == [{"/", 2}, {"/health", 1}]
  end

  test "sums the paths of an hour into one point" do
    Traffic.hit("/")
    Traffic.hit("/health")

    assert [{_hour, 2}] = Traffic.hourly()
  end

  test "a series is oldest first and leaves empty buckets out" do
    seed("2026-09-01T09", "/", 5)
    seed("2026-09-03T22", "/", 2)
    seed("2026-09-03T23", "/", 1)

    assert Traffic.daily(9_999) == [{"2026-09-01", 5}, {"2026-09-03", 3}]
  end

  test "a series stops at the window it is asked for" do
    # Yesterday is inside a two-day window; last month never is.
    seed(bucket(-1, :day), "/", 4)
    seed(bucket(-40, :day), "/", 99)

    assert Traffic.daily(2) == [{Date.to_iso8601(Date.utc_today() |> Date.add(-1)), 4}]
  end

  test "an empty table is an empty series, not a crash" do
    assert Traffic.daily() == []
    assert Traffic.hourly() == []
    assert Traffic.paths() == []
  end

  defp seed(bucket, path, count) do
    Repo.insert_all(Hit, [%{bucket: bucket, path: path, count: count}])
  end

  defp bucket(amount, unit) do
    DateTime.utc_now()
    |> DateTime.add(amount, unit)
    |> DateTime.to_iso8601()
    |> binary_part(0, 13)
  end
end

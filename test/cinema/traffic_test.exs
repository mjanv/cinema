defmodule Cinema.TrafficTest do
  use Cinema.DataCase, async: false

  alias Cinema.Repo
  alias Cinema.Traffic
  alias Cinema.Traffic.Hit

  setup do
    Repo.delete_all(Hit)
    :ok
  end

  test "counts a view" do
    Traffic.hit("/", "grenoble")

    assert Traffic.total() == 1
    assert List.last(Traffic.daily()) == {today(), 1}
  end

  test "adds repeat views to the same row rather than inserting a new one" do
    for _ <- 1..3, do: Traffic.hit("/", "grenoble")

    assert Repo.aggregate(Hit, :count) == 1
    assert Traffic.total() == 3
  end

  test "keeps cities apart" do
    Traffic.hit("/", "grenoble")
    Traffic.hit("/", "grenoble")
    Traffic.hit("/", "lyon")

    assert Traffic.cities() == [{"grenoble", 2}, {"lyon", 1}]
  end

  test "keeps pages apart" do
    Traffic.hit("/", "grenoble")
    Traffic.hit("/traffic")
    Traffic.hit("/traffic")

    assert Traffic.paths() == [{"/traffic", 2}, {"/", 1}]
  end

  test "counts a page that shows no city without ranking it as one" do
    Traffic.hit("/traffic")

    assert Traffic.cities() == []
    assert Traffic.paths() == [{"/traffic", 1}]
    assert Traffic.total() == 1
  end

  test "an hourly series is dense, oldest first, and ends on the current hour" do
    seed(hour(-2), "/", "grenoble", 5)

    assert Traffic.hourly(3) == [{hour(-2), 5}, {hour(-1), 0}, {hour(0), 0}]
  end

  test "a daily series covers every day of the window, quiet ones included" do
    Traffic.hit("/", "grenoble")

    series = Traffic.daily(7)

    assert length(series) == 7
    assert List.last(series) == {today(), 1}
    assert Enum.all?(Enum.take(series, 6), &(elem(&1, 1) == 0))
  end

  test "a series stops at the window it is asked for" do
    seed(day(-40) <> "T09", "/", "grenoble", 99)

    assert Traffic.total(2) == 0
    assert Enum.all?(Traffic.daily(2), &(elem(&1, 1) == 0))
  end

  test "an empty table reads as zeroes, not as a crash" do
    assert Traffic.cities() == []
    assert Traffic.paths() == []
    assert Traffic.total() == 0
    assert Traffic.hourly(3) |> Enum.map(&elem(&1, 1)) == [0, 0, 0]
  end

  defp seed(bucket, path, city, count) do
    Repo.insert_all(Hit, [%{bucket: bucket, path: path, city: city, count: count}])
  end

  defp today, do: Date.to_iso8601(Date.utc_today())

  defp day(offset), do: Date.to_iso8601(Date.add(Date.utc_today(), offset))

  defp hour(offset) do
    DateTime.utc_now()
    |> DateTime.add(offset, :hour)
    |> DateTime.to_iso8601()
    |> binary_part(0, 13)
  end
end

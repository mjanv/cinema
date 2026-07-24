defmodule CinemaTest do
  # Shares the ETS cache with Cinema.ShowtimesTest.
  use ExUnit.Case, async: false

  setup do
    Cinema.reset_cache()
    :ok
  end

  test "schedule/1 returns the days together with their freshness" do
    schedule = Cinema.schedule()

    assert %{days: days, fetched_at: %DateTime{}, stale?: false} = schedule
    assert length(days) == 3, "the test source is configured for 3 days"
    assert Enum.all?(days, &match?(%{date: %Date{}, theaters: _}, &1))
  end

  test "schedule/1 honours the requested horizon" do
    assert %{days: days} = Cinema.schedule(days: 1)
    assert length(days) == 1
  end

  test "by_movie/1 regroups a day around films" do
    %{days: [day | _]} = Cinema.schedule(days: 1)

    assert [movie | _] = Cinema.by_movie(day)
    assert %{title: title, theaters: [_ | _]} = movie
    assert is_binary(title)
  end

  test "today/0 is the local Grenoble date, not the UTC one" do
    local = DateTime.now!("Europe/Paris") |> DateTime.to_date()

    assert Cinema.today() == local
  end

  test "now/0 is the current Grenoble time" do
    now = Cinema.now()
    local = DateTime.now!("Europe/Paris")

    assert %DateTime{} = now
    assert now.time_zone == "Europe/Paris"
    assert DateTime.to_date(now) == DateTime.to_date(local)
    assert abs(DateTime.diff(now, local)) <= 2
  end

  test "now/0 and today/0 agree on the local day" do
    assert Cinema.now() |> DateTime.to_date() == Cinema.today()
  end

  test "exposes the whole surface the web layer needs" do
    exported = Cinema.__info__(:functions) |> Keyword.keys() |> MapSet.new()

    for name <- [:schedule, :refresh, :by_movie, :today, :now] do
      assert name in exported, "Cinema must expose #{name}/_"
    end
  end
end

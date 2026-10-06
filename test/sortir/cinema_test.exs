defmodule Sortir.CinemaTest do
  # Shares the ETS cache with Sortir.Cinema.ShowtimesTest.
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox

  setup do
    pid = Sandbox.start_owner!(Sortir.Core.Repo, shared: true)
    on_exit(fn -> Sandbox.stop_owner(pid) end)
    Sortir.Cinema.reset_cache()
    {:ok, city: Sortir.Cinema.find_city(nil)}
  end

  test "schedule/2 returns the days together with their freshness", %{city: city} do
    schedule = Sortir.Cinema.schedule(city)

    assert %{days: days, fetched_at: %DateTime{}, stale?: false} = schedule
    assert length(days) == 3, "the test source is configured for 3 days"
    assert Enum.all?(days, &match?(%{date: %Date{}, theaters: _}, &1))
  end

  test "schedule/2 honours the requested horizon", %{city: city} do
    assert %{days: days} = Sortir.Cinema.schedule(city, days: 1)
    assert length(days) == 1
  end

  test "by_movie/1 regroups a day around films", %{city: city} do
    # Fetching is queued now, so drain it before asserting on content.
    Sortir.Cinema.schedule(city, days: 1)
    Oban.drain_queue(queue: :allocine)

    %{days: [day | _]} = Sortir.Cinema.schedule(city, days: 1, refresh: true)

    assert [movie | _] = Sortir.Cinema.by_movie(day)
    assert %{title: title, theaters: [_ | _]} = movie
    assert is_binary(title)
  end

  test "today/0 is the local Grenoble date, not the UTC one" do
    local = DateTime.now!("Europe/Paris") |> DateTime.to_date()

    assert Sortir.Cinema.today() == local
  end

  test "now/0 is the current Grenoble time" do
    now = Sortir.Cinema.now()
    local = DateTime.now!("Europe/Paris")

    assert %DateTime{} = now
    assert now.time_zone == "Europe/Paris"
    assert DateTime.to_date(now) == DateTime.to_date(local)
    assert abs(DateTime.diff(now, local)) <= 2
  end

  test "now/0 and today/0 agree on the local day" do
    assert Sortir.Cinema.now() |> DateTime.to_date() == Sortir.Cinema.today()
  end

  test "cities/0 lists the cities the board can show" do
    cities = Sortir.Cinema.cities()

    assert [_ | _] = cities
    assert Enum.all?(cities, &match?(%Sortir.Cinema.City{}, &1))
    assert "Grenoble" in Enum.map(cities, & &1.name)
  end

  test "find_city/1 resolves a public slug, ignoring the source's own id" do
    assert Sortir.Cinema.find_city("lyon").name == "Lyon"

    # AlloCiné's key is internal; it must not address a city from the outside.
    assert Sortir.Cinema.find_city("ville-113315").name == "Grenoble"
  end

  test "find_city/1 falls back to the default for an unknown slug" do
    assert Sortir.Cinema.find_city("nowhere-at-all").name == "Grenoble"
    assert Sortir.Cinema.find_city(nil).name == "Grenoble"
  end
end

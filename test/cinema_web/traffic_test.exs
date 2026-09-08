defmodule CinemaWeb.TrafficTest do
  use CinemaWeb.ConnCase, async: false

  alias Cinema.Repo
  alias Cinema.Traffic
  alias Cinema.Traffic.Hit

  setup do
    Repo.delete_all(Hit)
    :ok
  end

  test "counts a page load", %{conn: conn} do
    get(conn, ~p"/")

    assert Traffic.paths() == [{"/", 1}]
  end

  test "leaves the health probe out", %{conn: conn} do
    # Uptime checks run every few seconds and would swamp the real numbers.
    get(conn, ~p"/health")

    assert Traffic.paths() == []
  end
end

defmodule CinemaWeb.TrafficTest do
  use CinemaWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Cinema.Repo
  alias Cinema.Traffic
  alias Cinema.Traffic.Hit

  @moduletag :schedule

  setup do
    Repo.delete_all(Hit)
    :ok
  end

  describe "counting board views" do
    test "counts a connected view against the city it showed", %{conn: conn} do
      {:ok, _live, _html} = live(conn, ~p"/?city=lyon")

      assert Traffic.cities() == [{"lyon", 1}]
      assert Traffic.paths() == [{"/", 1}]
    end

    test "counts the city the app resolved when the url names none", %{conn: conn} do
      {:ok, _live, _html} = live(conn, ~p"/")

      assert Traffic.cities() == [{"grenoble", 1}]
    end

    test "leaves the dead render out", %{conn: conn} do
      # What crawlers get, and what a visitor who never stays gets.
      assert get(conn, ~p"/").status == 200
      assert Traffic.total() == 0
    end

    test "counts a switch to another city", %{conn: conn} do
      {:ok, live, _html} = live(conn, ~p"/?city=grenoble")

      render_change(live, "select-city", %{"city" => "lyon"})

      assert Traffic.cities() == [{"grenoble", 1}, {"lyon", 1}]
    end

    test "does not count a patch that stays on the same city", %{conn: conn} do
      {:ok, live, _html} = live(conn, ~p"/?city=grenoble")

      # Picking a day or opening a film re-runs handle_params on the board that
      # is already showing; neither is a new view.
      tomorrow = Date.utc_today() |> Date.add(1) |> Date.to_iso8601()
      render_click(live, "select-day", %{"date" => tomorrow})
      render_click(live, "select-city", %{"city" => "grenoble"})

      assert Traffic.cities() == [{"grenoble", 1}]
    end

    test "leaves the health probe out", %{conn: conn} do
      # Uptime checks run every few seconds and would swamp the real numbers.
      assert get(conn, ~p"/health").status == 200
      assert Traffic.total() == 0
    end
  end

  describe "the dashboard" do
    test "asks for a password", %{conn: conn} do
      assert get(conn, ~p"/traffic").status == 401
    end

    test "does not exist when no password is configured", %{conn: conn} do
      unconfigured(nil)

      assert get(conn, ~p"/traffic").status == 404
    end

    test "does not exist when the password is empty" do
      # An unset deploy secret reaches the release as "", which must not become
      # a dashboard anyone can open by submitting a blank password.
      unconfigured(username: "cinema", password: "")

      assert get(build_conn(), ~p"/traffic").status == 404
    end

    test "charts the traffic it has", %{conn: conn} do
      Traffic.hit("/", "grenoble")
      Traffic.hit("/", "grenoble")
      Traffic.hit("/", "lyon")

      {:ok, live, _html} = live(as_operator(conn), ~p"/traffic")
      html = render(live)

      # Cities are named, not slugged, and the busiest one leads.
      assert html =~ "Grenoble"
      assert html =~ "Lyon"
      assert [{_, _, ["Grenoble"]}, {_, _, ["Lyon"]}] = rows(live, "#cities .row-label")

      # 3 board views plus this dashboard's own.
      assert html =~ "<strong>4</strong>"
    end

    test "switches granularity with the range", %{conn: conn} do
      {:ok, live, _html} = live(as_operator(conn), ~p"/traffic")

      assert render(live) =~ "Par heure"
      assert has_element?(live, ".period.is-on", "48 h")

      html = render_click(live, "select-range", %{"range" => "30 j"})

      assert html =~ "Par jour"
      # One bar per day of the window, quiet days included.
      assert length(rows(live, ".slot")) == 30
    end

    test "renders with nothing recorded at all", %{conn: conn} do
      {:ok, _live, html} = live(as_operator(conn), ~p"/traffic")

      assert html =~ "Aucune ville consultée."
      assert html =~ "Trafic"
    end
  end

  defp unconfigured(operator) do
    configured = Application.get_env(:cinema, :operator)
    on_exit(fn -> Application.put_env(:cinema, :operator, configured) end)
    Application.put_env(:cinema, :operator, operator)
  end

  defp as_operator(conn) do
    put_req_header(conn, "authorization", Plug.BasicAuth.encode_basic_auth("cinema", "cinema"))
  end

  defp rows(live, selector) do
    live |> render() |> LazyHTML.from_fragment() |> LazyHTML.query(selector) |> LazyHTML.to_tree()
  end
end

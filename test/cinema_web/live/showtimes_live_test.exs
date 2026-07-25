defmodule CinemaWeb.ShowtimesLiveTest do
  use CinemaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "opens grouped by film", %{conn: conn} do
    {:ok, _live, html} = live(conn, ~p"/")

    assert html =~ "Séances à Grenoble"
    assert html =~ "Toy Story 5"
    assert html =~ "00:01"
    # Films lead, cinemas appear beneath them.
    assert html =~ "venue-name"
  end

  test "shows the current Grenoble date and time to read the board against", %{conn: conn} do
    {:ok, live, html} = live(conn, ~p"/")

    now = Cinema.now()
    html_after_connect = render(live)

    assert html =~ ~s(class="clock")
    assert html_after_connect =~ Calendar.strftime(now, "%H:%M")

    # French short date inside the clock itself, e.g. "ven. 24 juil." — the day
    # strip also renders abbreviations, so assert against the clock element.
    clock_date = live |> element(".clock .clock-date") |> render()

    assert clock_date =~ "#{DateTime.to_date(now).day}"
    assert Regex.match?(~r/(lun|mar|mer|jeu|ven|sam|dim)\./, clock_date)
    assert Regex.match?(~r/(janv|févr|mars|avr|mai|juin|juil|août|sept|oct|nov|déc)/, clock_date)
  end

  test "dims today's started screenings but leaves upcoming ones bookable", %{conn: conn} do
    {:ok, live, _html} = live(conn, ~p"/")

    # The stub programmes 00:01 (past by any sane run time) and 23:59 (upcoming).
    past_chip = live |> element(".chip.is-past") |> render()
    assert past_chip =~ "00:01"
    refute past_chip =~ "<a", "a started screening must not stay bookable"

    assert has_element?(live, "a.chip", "23:59"), "upcoming screenings keep their booking link"
    refute has_element?(live, "a.chip.is-past")
  end

  test "opens on today while the day still has something to catch", %{conn: conn} do
    {:ok, live, _html} = live(conn, ~p"/")

    # The stub programmes 23:59 today, so today is never spent during a test run.
    today = Cinema.today() |> Date.to_iso8601()

    assert has_element?(live, "button.day.is-current[phx-value-date='#{today}']")
  end

  test "an explicit date in the URL still wins", %{conn: conn} do
    tomorrow = Cinema.today() |> Date.add(1) |> Date.to_iso8601()

    {:ok, live, _html} = live(conn, ~p"/?date=#{tomorrow}")

    assert has_element?(live, "button.day.is-current[phx-value-date='#{tomorrow}']")
  end

  test "offers every city and marks the current one", %{conn: conn} do
    {:ok, live, _html} = live(conn, ~p"/")

    assert has_element?(live, "select#city option[value=grenoble][selected]")
    assert has_element?(live, "select#city option[value=lyon]")
  end

  test "switching city loads that city's schedule", %{conn: conn} do
    {:ok, live, html} = live(conn, ~p"/")
    assert html =~ "Toy Story 5"

    html = live |> form("form.city-picker", city: "lyon") |> render_change()

    assert html =~ "Film Lyonnais", "the Lyon board must replace Grenoble's"
    refute html =~ "Toy Story 5"
    assert html =~ "Cinéma Lyonnais"
  end

  test "a city in the URL is what gets rendered", %{conn: conn} do
    {:ok, _live, html} = live(conn, ~p"/?city=lyon")

    assert html =~ "Film Lyonnais"
    refute html =~ "Toy Story 5"
  end

  test "an unknown city falls back to the default rather than erroring", %{conn: conn} do
    {:ok, _live, html} = live(conn, ~p"/?city=nowhere-at-all")

    assert html =~ "Toy Story 5"
  end

  test "renders an explicit message instead of crashing when no city resolves", %{conn: conn} do
    # Reproduces the 429 case: the source returns nothing, so there is no city
    # to render. This used to raise BadMapError on @city.name and KeyError on
    # @days rather than telling the user anything.
    defmodule NoCitiesSource do
      @behaviour Cinema.Source
      @impl true
      def cities, do: []
      @impl true
      def theaters(_city), do: []
      @impl true
      def fetch_day(_theater, _date), do: {:ok, []}
    end

    previous = Application.get_env(:cinema, Cinema.Showtimes, [])
    Application.put_env(:cinema, Cinema.Showtimes, Keyword.put(previous, :source, NoCitiesSource))
    on_exit(fn -> Application.put_env(:cinema, Cinema.Showtimes, previous) end)

    {:ok, live, html} = live(conn, ~p"/")

    assert html =~ "AlloCiné est injoignable"
    refute has_element?(live, "select#city")

    # Interacting with a city-less board must not crash either.
    assert render_click(live, "refresh") =~ "AlloCiné est injoignable"
  end

  test "marks each screening with its version so the colours can differ", %{conn: conn} do
    {:ok, live, _html} = live(conn, ~p"/")

    # The stub programmes one VF (00:01) and one VOST (23:59) today.
    assert has_element?(live, ".chip.is-vf", "00:01")
    assert has_element?(live, ".chip.is-vost", "23:59")
    refute has_element?(live, ".chip.is-vf.is-vost")
  end

  test "shows a film's genres as labels in both groupings", %{conn: conn} do
    {:ok, live, html} = live(conn, ~p"/")

    assert html =~ ~s(class="genres")
    assert has_element?(live, ".genre", "Animation")

    html = live |> element("button", "Par cinéma") |> render_click()
    assert html =~ ~s(class="genres")
  end

  test "regroups by cinema on demand", %{conn: conn} do
    {:ok, live, _html} = live(conn, ~p"/")

    html = live |> element("button", "Par cinéma") |> render_click()

    assert html =~ "theater-name"
    assert html =~ "Cinéma Test"
    assert html =~ "Toy Story 5"
    refute html =~ "venue-name"
  end

  test "filters the board down to subtitled screenings", %{conn: conn} do
    {:ok, live, _html} = live(conn, ~p"/")

    html = live |> element("button", "VOST") |> render_click()

    assert html =~ "Kill Bill"
    refute html =~ "Toy Story 5"
  end

  test "returning to the film grouping lists every cinema playing a film", %{conn: conn} do
    {:ok, live, _html} = live(conn, ~p"/")

    live |> element("button", "Par cinéma") |> render_click()
    html = live |> element("button", "Par film") |> render_click()

    assert html =~ "Toy Story 5"
    assert html =~ "Kill Bill"
    assert html =~ "venue-name"
  end

  test "combines the film grouping with the version filter", %{conn: conn} do
    {:ok, live, _html} = live(conn, ~p"/")

    html = live |> element("button", "VOST") |> render_click()

    assert html =~ "Kill Bill"
    refute html =~ "Toy Story 5"
  end

  test "switching day keeps the schedule addressable by URL", %{conn: conn} do
    tomorrow = Date.utc_today() |> Date.add(1) |> Date.to_iso8601()

    {:ok, live, _html} = live(conn, ~p"/")

    live
    |> element("button[phx-value-date='#{tomorrow}']")
    |> render_click()

    assert_patched(live, "/?city=grenoble&date=#{tomorrow}")
  end
end

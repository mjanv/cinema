defmodule CinemaWeb.ShowtimesLiveTest do
  use CinemaWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  @moduletag :schedule

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

  test "groups the picker into cities and departments", %{conn: conn} do
    {:ok, live, _html} = live(conn, ~p"/")

    assert has_element?(live, ~s(select#city optgroup[label="Villes"] option[value=grenoble]))
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

  test "shows the running build in the footer", %{conn: conn} do
    {:ok, _live, html} = live(conn, ~p"/")

    assert html =~ ~s(class="build")
    assert html =~ Cinema.commit()
  end

  test "clicking a film title shows its run across every day", %{conn: conn} do
    {:ok, live, _html} = live(conn, ~p"/")

    html = live |> element("a.movie-link", "Toy Story 5") |> render_click()

    assert html =~ ~s(class="film")
    assert html =~ "Toy Story 5"
    # The stub programmes it on all three days, each listed with its cinema.
    assert html =~ "film-day-name"
    refute html =~ "Kill Bill", "the film view shows one film, not the board"
  end

  test "hides the day strip and filters in the film view", %{conn: conn} do
    {:ok, live, _html} = live(conn, ~p"/?city=grenoble&film=Toy+Story+5")

    # Neither acts on this view: it spans every day and shows one film.
    refute has_element?(live, "nav.days")
    refute has_element?(live, ".controls")
    # The title, clock and refresh remain useful and stay.
    assert has_element?(live, ".clock")
    assert has_element?(live, "button.refresh")

    html = live |> element("button.back") |> render_click()
    assert html =~ ~s(class="days")
    assert html =~ ~s(class="controls")
  end

  test "the film view is addressable and reversible", %{conn: conn} do
    {:ok, _live, html} = live(conn, ~p"/?city=grenoble&film=Toy+Story+5")
    assert html =~ ~s(class="film")

    {:ok, live, _html} = live(conn, ~p"/?city=grenoble&film=Toy+Story+5")
    html = live |> element("button.back") |> render_click()

    refute html =~ ~s(class="film-head")
    assert html =~ "Kill Bill", "back returns to the full board"
  end

  test "an unknown film falls back to the board rather than erroring", %{conn: conn} do
    {:ok, _live, html} = live(conn, ~p"/?city=grenoble&film=Film+Inexistant")

    refute html =~ ~s(class="film-head")
    assert html =~ "Toy Story 5"
  end

  @tag schedule: false
  test "says it is loading rather than showing an empty board", %{conn: conn} do
    # A cold city: jobs are queued but none have landed. The board must say so
    # rather than claiming there are no screenings.
    Cinema.reset_cache()

    {:ok, _live, html} = live(conn, ~p"/")

    assert html =~ "Chargement des séances"
    refute html =~ "Aucune séance"
  end

  test "refreshes itself when the city's fetch jobs land", %{conn: conn} do
    # A cold city renders empty and fills in; without this the board would sit
    # blank until the user reloaded.
    {:ok, live, _html} = live(conn, ~p"/")

    send(live.pid, {:schedule_updated, "grenoble"})

    assert render(live) =~ "Toy Story 5"
  end

  test "keeps the day you are looking at when jobs land", %{conn: conn} do
    # Background updates must not yank you back to today: you could be reading
    # Saturday's board when a fetch completes.
    tomorrow = Cinema.today() |> Date.add(1) |> Date.to_iso8601()

    {:ok, live, _html} = live(conn, ~p"/?date=#{tomorrow}")
    assert has_element?(live, "button.day.is-current[phx-value-date='#{tomorrow}']")

    send(live.pid, {:schedule_updated, "grenoble"})

    assert has_element?(live, "button.day.is-current[phx-value-date='#{tomorrow}']"),
           "the selected day must survive a background refresh"
  end

  test "switching city still lands on a sensible day", %{conn: conn} do
    tomorrow = Cinema.today() |> Date.add(1) |> Date.to_iso8601()

    {:ok, live, _html} = live(conn, ~p"/?date=#{tomorrow}")
    live |> form("form.city-picker", city: "lyon") |> render_change()

    # A different city may not even have that date, so it re-picks.
    assert has_element?(live, "button.day.is-current")
  end

  test "the refresh button keeps the day you are on", %{conn: conn} do
    tomorrow = Cinema.today() |> Date.add(1) |> Date.to_iso8601()

    {:ok, live, _html} = live(conn, ~p"/?date=#{tomorrow}")
    render_click(live, "refresh")

    assert has_element?(live, "button.day.is-current[phx-value-date='#{tomorrow}']")
  end

  test "ignores updates for a city it is not showing", %{conn: conn} do
    {:ok, live, _html} = live(conn, ~p"/")

    send(live.pid, {:schedule_updated, "lyon"})

    # Still Grenoble's board, not Lyon's.
    assert render(live) =~ "Toy Story 5"
    refute render(live) =~ "Film Lyonnais"
  end

  test "does not repeat the city name on every cinema", %{conn: conn} do
    # The stub's theaters are in Grenoble and the board is Grenoble: printing
    # the town on each would be noise, not information.
    {:ok, live, _html} = live(conn, ~p"/")

    refute has_element?(live, ".town")
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

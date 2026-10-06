defmodule SortirWeb.AgendaLiveTest do
  use SortirWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Sortir.Agenda
  alias Sortir.Agenda.{Event, Occurrence}
  alias Sortir.Core.{Clock, Repo}

  setup do
    {:ok, venue} =
      Agenda.upsert_venue(%{
        slug: "la-belle-electrique",
        name: "La Belle Électrique",
        city: "Grenoble",
        kind: :music_hall
      })

    # The board's clock, not UTC: between local midnight and 22:00Z the two
    # differ, and an event seeded on the UTC date is already in the past.
    today = Clock.today()

    {:ok, _event} =
      Agenda.save(
        %{
          event: %{
            source: "belle_electrique",
            external_id: "ce-soir",
            title: "Un concert ce soir",
            category: :concert,
            labels: ["Funk", "Soul"]
          },
          occurrence: %{
            starts_at: NaiveDateTime.new!(today, ~T[20:00:00]),
            ends_at: nil,
            status: :unknown,
            room: "Grande salle",
            prices: [1300, 1900]
          }
        },
        venue
      )

    {:ok, venue: venue, today: today}
  end

  test "lists what is on, by day", %{conn: conn} do
    {:ok, _live, html} = live(conn, ~p"/agenda")

    assert html =~ "Un concert ce soir"
    assert html =~ "20:00"
    assert html =~ "La Belle Électrique"
  end

  test "shows the venue's own labels", %{conn: conn} do
    {:ok, live, _html} = live(conn, ~p"/agenda")

    assert has_element?(live, ".label", "Funk")
    assert has_element?(live, ".label", "Soul")
  end

  test "shows the cheapest price rather than a bare list", %{conn: conn} do
    {:ok, _live, html} = live(conn, ~p"/agenda")

    assert html =~ "13"
  end

  test "marks a sold-out occurrence", %{conn: conn, venue: venue, today: today} do
    {:ok, _event} =
      Agenda.save(
        %{
          event: %{
            source: "belle_electrique",
            external_id: "complet",
            title: "Déjà complet",
            category: :concert
          },
          occurrence: %{
            starts_at: NaiveDateTime.new!(today, ~T[21:00:00]),
            status: :sold_out
          }
        },
        venue
      )

    {:ok, live, _html} = live(conn, ~p"/agenda")

    assert has_element?(live, ".is-sold-out")
  end

  test "shows one row with every start time when a showing repeats", %{
    conn: conn,
    venue: venue,
    today: today
  } do
    # A tour run three times in a day is one thing to go to, not three rows.
    for at <- [~T[10:30:00], ~T[11:00:00], ~T[15:00:00]] do
      {:ok, _event} =
        Agenda.save(
          %{
            event: %{
              source: "belle_electrique",
              external_id: "flash",
              title: "Visite flash"
            },
            occurrence: %{starts_at: NaiveDateTime.new!(today, at)}
          },
          venue
        )
    end

    {:ok, live, html} = live(conn, ~p"/agenda")

    titles = html |> String.split("Visite flash") |> length()
    assert titles == 2, "the title must appear once, not once per showing"

    assert has_element?(live, ".chip", "10:30")
    assert has_element?(live, ".chip", "11:00")
    assert has_element?(live, ".chip", "15:00")
  end

  test "says so when nothing is programmed", %{conn: conn} do
    Repo.delete_all(Occurrence)
    Repo.delete_all(Event)

    {:ok, _live, html} = live(conn, ~p"/agenda")

    assert html =~ "Rien de programmé"
  end

  test "links back to the showtimes board", %{conn: conn} do
    {:ok, live, _html} = live(conn, ~p"/agenda")

    assert has_element?(live, ~s(a[href="/"]))
  end
end

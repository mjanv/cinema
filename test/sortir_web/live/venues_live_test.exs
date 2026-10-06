defmodule SortirWeb.VenuesLiveTest do
  use SortirWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Sortir.Agenda
  alias Sortir.Agenda.{Event, Occurrence, Venue}
  alias Sortir.Core.{Clock, Repo}

  setup do
    {:ok, venue} =
      Agenda.upsert_venue(%{
        slug: "la-belle-electrique",
        name: "La Belle Électrique",
        city: "Grenoble",
        kind: :music_hall,
        url: "https://www.la-belle-electrique.com"
      })

    today = Clock.today()

    {:ok, _event} =
      Agenda.save(
        %{
          event: %{
            source: "belle_electrique",
            external_id: "ce-soir",
            title: "Un concert ce soir",
            category: :concert
          },
          occurrence: %{starts_at: NaiveDateTime.new!(today, ~T[20:00:00])}
        },
        venue
      )

    {:ok, venue: venue, today: today}
  end

  test "lists the venues the agenda is built from", %{conn: conn} do
    {:ok, _live, html} = live(conn, ~p"/agenda/venues")

    assert html =~ "La Belle Électrique"
    assert html =~ "Grenoble"
  end

  test "shows how much each venue has programmed", %{conn: conn} do
    {:ok, _live, html} = live(conn, ~p"/agenda/venues")

    assert html =~ "1"
  end

  test "links to the venue's own site", %{conn: conn} do
    {:ok, live, _html} = live(conn, ~p"/agenda/venues")

    assert has_element?(live, ~s(a[href="https://www.la-belle-electrique.com"]))
  end

  test "shows a venue that has nothing programmed", %{conn: conn} do
    # A scraper that ran and found nothing must still appear, or a broken
    # source is indistinguishable from one that was never added.
    {:ok, _empty} =
      Agenda.upsert_venue(%{slug: "vide", name: "Salle Vide", city: "Grenoble", kind: :other})

    {:ok, _live, html} = live(conn, ~p"/agenda/venues")

    assert html =~ "Salle Vide"
  end

  test "links back to the agenda", %{conn: conn} do
    {:ok, live, _html} = live(conn, ~p"/agenda/venues")

    assert has_element?(live, ~s(a[href="/agenda"]))
  end

  test "says so when no venue has been scraped yet", %{conn: conn} do
    Repo.delete_all(Occurrence)
    Repo.delete_all(Event)
    Repo.delete_all(Venue)

    {:ok, _live, html} = live(conn, ~p"/agenda/venues")

    assert html =~ "Aucune salle"
  end
end

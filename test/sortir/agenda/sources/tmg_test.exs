defmodule Sortir.Agenda.Sources.TmgTest do
  use ExUnit.Case, async: true

  alias Sortir.Agenda.Fixtures
  alias Sortir.Agenda.Sources.Tmg

  defp listing, do: Fixtures.html!("tmg_spectacles")

  describe "parse_listing/1" do
    test "extracts every show on the page" do
      shows = Tmg.parse_listing(listing())

      assert length(shows) > 30
      assert Enum.all?(shows, &match?(%{event: _, occurrences: _}, &1))
    end

    test "gives one show its several performances" do
      # The case La Belle Électrique never produces: one production, three
      # dates, which is why an event owns a list of occurrences.
      show = find(listing(), "Frisson")

      assert length(show.occurrences) == 3

      assert Enum.map(show.occurrences, & &1.starts_at) == [
               ~N[2026-10-01 14:30:00],
               ~N[2026-10-02 10:00:00],
               ~N[2026-10-02 14:30:00]
             ]
    end

    test "resolves the season's two calendar years" do
      # The page prints "01.10" with no year and covers "saison 2026/2027":
      # autumn is 2026, spring is 2027. Taking the current year would put every
      # spring show twelve months early.
      autumn = find(listing(), "Frisson")
      spring = find(listing(), "Les corps incorruptibles")

      assert hd(autumn.occurrences).starts_at.year == 2026
      assert hd(spring.occurrences).starts_at.year in [2026, 2027]
    end

    test "separates the room from the category" do
      # Tags mix the two: "Théâtre de Poche" is where, "Théâtre" is what.
      show = find(listing(), "Frisson")

      assert hd(show.occurrences).room == "Théâtre de Poche"
      assert show.event.labels == ["Théâtre"]
    end

    test "recognises a room it was never told about" do
      # The markup marks the category with o-tag--primary and leaves the room
      # plain, so rooms need not be enumerated — "Théâtre 145" is one, and a
      # hardcoded list had missed it.
      shows = Tmg.parse_listing(listing())

      rooms = shows |> Enum.flat_map(& &1.occurrences) |> Enum.map(& &1.room) |> Enum.uniq()
      labels = shows |> Enum.flat_map(& &1.event.labels) |> Enum.uniq()

      assert "Théâtre 145" in rooms
      refute "Théâtre 145" in labels
    end

    test "carries identity, url and image" do
      show = find(listing(), "Les corps incorruptibles")

      assert show.event.source == "tmg"
      assert show.event.external_id == "6558"
      assert show.event.url =~ "/agenda/6558/"
      assert show.event.image_url =~ "http"
    end

    test "skips entries that are not shows" do
      # "Ouverture de la billetterie" is an announcement: it sits in a card but
      # links to the listing itself rather than to an agenda page.
      shows = Tmg.parse_listing(listing())

      refute Enum.any?(shows, &(&1.event.title =~ "Ouverture de la billetterie"))
      assert Enum.all?(shows, &(&1.event.url =~ "/agenda/"))
    end

    test "returns an empty list rather than raising on unexpected html" do
      assert Tmg.parse_listing("<html><body>nope</body></html>") == []
    end
  end

  describe "fetch/1" do
    test "returns one entry per performance, sharing the event" do
      get = fn _url -> {:ok, listing()} end

      assert {:ok, scraped} = Tmg.fetch(get: get)

      frissons = Enum.filter(scraped, &(&1.event.title =~ "Frisson"))

      assert length(frissons) == 3
      # One event, three occurrences: the id is shared, the times are not.
      assert frissons |> Enum.map(& &1.event.external_id) |> Enum.uniq() |> length() == 1
      assert frissons |> Enum.map(& &1.occurrence.starts_at) |> Enum.uniq() |> length() == 3
    end

    test "reports a failure rather than returning nothing quietly" do
      get = fn _url -> {:error, {:http_status, 500}} end

      assert {:error, {:http_status, 500}} = Tmg.fetch(get: get)
    end
  end

  defp find(html, fragment) do
    html
    |> Tmg.parse_listing()
    |> Enum.find(&String.contains?(&1.event.title, fragment))
    |> case do
      nil -> flunk("no show matching #{inspect(fragment)}")
      found -> found
    end
  end
end

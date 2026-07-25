defmodule Cinema.Allocine.CitiesTest do
  use ExUnit.Case, async: true

  alias Cinema.Allocine.Cities
  alias Cinema.{City, Theater}

  describe "parse_index/1" do
    test "extracts the cities AlloCiné lists, sorted by name" do
      cities = Cities.parse_index(Cinema.Fixtures.html!("salle_index"))

      assert Enum.all?(cities, &match?(%City{}, &1))

      names = Enum.map(cities, & &1.name)
      assert "Grenoble" in names
      assert "Paris" in names
      assert "Lyon" in names
      assert names == Enum.sort(names), "cities must come out in display order"

      grenoble = Enum.find(cities, &(&1.name == "Grenoble"))
      assert grenoble.slug == "grenoble", "the public slug must not be AlloCiné's id"
      assert grenoble.external_id == "ville-98857"
    end

    test "returns an empty list rather than raising on unexpected HTML" do
      assert Cities.parse_index("<html><body>nope</body></html>") == []
    end
  end

  describe "parse_theaters/2" do
    test "extracts a city's theaters with their ids and names" do
      theaters =
        Cinema.Fixtures.html!("ville_lyon_page1")
        |> Cities.parse_theaters("Lyon")

      assert Enum.all?(theaters, &match?(%Theater{}, &1))
      assert Enum.all?(theaters, &(&1.city == "Lyon"))
      assert length(theaters) > 5

      assert "P0005" in Enum.map(theaters, & &1.external_id)
      assert "UGC Astoria" in Enum.map(theaters, & &1.name)
    end

    test "keeps every theater id format AlloCiné issues" do
      # Ids are not all P\d+: Véo Cartoucherie in Toulouse is G0699, and some
      # carry hex digits (G06DB). Anchoring on too narrow a pattern silently
      # drops real cinemas from a city.
      html =
        Enum.map_join(
          [
            {"W7461", "Megarama Annecy"},
            {"G0699", "Véo Cartoucherie"},
            {"G06DB", "Véo Le Sénéchal"},
            {"P0071", "ABC"}
          ],
          fn {id, name} -> ~s(<a href="/seance/salle_gen_csalle=#{id}.html">#{name}</a>) end
        )

      ids = html |> Cities.parse_theaters("Toulouse") |> Enum.map(& &1.external_id)

      assert Enum.sort(ids) == ["G0699", "G06DB", "P0071", "W7461"]
    end

    test "deduplicates a theater linked more than once on the page" do
      html = """
      <a href="/seance/salle_gen_csalle=P0005.html">UGC Astoria</a>
      <a href="/seance/salle_gen_csalle=P0005.html">UGC Astoria</a>
      """

      assert [_only_one] = Cities.parse_theaters(html, "Lyon")
    end
  end

  describe "list/1 when AlloCiné is unavailable" do
    setup do
      Cities.reset_cache()
      :ok
    end

    test "falls back to a built-in list rather than emptying the app" do
      # A 429 or an outage must not leave the board with no cities to show:
      # without this the UI has nothing to render and crashes.
      cities = Cities.list(fetch: fn _url -> {:error, {:http_status, 429}} end)

      assert [_ | _] = cities
      assert "Grenoble" in Enum.map(cities, & &1.name)
      assert Enum.all?(cities, &match?(%City{external_id: "ville-" <> _}, &1))
    end

    test "prefers the live list once it is available" do
      live = Cities.list(fetch: fn _url -> {:ok, Cinema.Fixtures.html!("salle_index")} end)

      assert length(live) >= length(Cities.fallback())
    end
  end

  describe "max_page/1" do
    test "reads how many pages of theaters a city has" do
      assert Cities.max_page(Cinema.Fixtures.html!("ville_lyon_page1")) == 2
    end

    test "defaults to a single page when there is no pagination" do
      assert Cities.max_page("<html></html>") == 1
    end
  end
end

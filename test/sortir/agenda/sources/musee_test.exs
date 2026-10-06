defmodule Sortir.Agenda.Sources.MuseeTest do
  use ExUnit.Case, async: true

  alias Sortir.Agenda.Sources.Musee

  defp listing, do: File.read!("test/support/fixtures/agenda/musee_agenda.html")
  defp last_page, do: File.read!("test/support/fixtures/agenda/musee_agenda_last.html")

  describe "venue/0" do
    test "identifies the museum" do
      venue = Musee.venue()

      assert venue.slug == "musee-de-grenoble"
      assert venue.city == "Grenoble"
      assert venue.kind == :museum
    end
  end

  describe "parse_listing/1" do
    test "reads every entry on the page" do
      assert length(Musee.parse_listing(listing())) == 10
    end

    test "builds a full date from the day, month and year parts" do
      # The date is split across three elements and the month is a French
      # word; none of it parses without being reassembled.
      [%{occurrence: occurrence} | _rest] = Musee.parse_listing(listing())

      assert occurrence.starts_at == ~N[2026-08-01 10:30:00]
    end

    test "keeps the museum's own title and labels" do
      entries = Musee.parse_listing(listing())

      entry =
        Enum.find(
          entries,
          &String.starts_with?(&1.event.title, "Visites guidées de l'exposition")
        )

      assert entry.event.title =~ "Léon Tutundjian"
      assert "Visites guidées" in entry.event.labels
      assert "Tout public" in entry.event.labels
    end

    test "decodes entities in the title" do
      # Titles arrive as `l&#039;exposition`; storing that verbatim would
      # render the escape to the reader.
      titles = Enum.map(Musee.parse_listing(listing()), & &1.event.title)

      refute Enum.any?(titles, &String.contains?(&1, "&#039;"))
      assert Enum.any?(titles, &String.contains?(&1, "'"))
    end

    test "gives repeated dates of one visit the same identity" do
      # The same guided tour runs on several days. Each is its own
      # occurrence, but they must share one event or the agenda lists the
      # same title as unrelated entries.
      entries = Musee.parse_listing(listing())

      ids =
        entries
        |> Enum.filter(&String.starts_with?(&1.event.title, "Visites guidées de l'exposition"))
        |> Enum.map(& &1.event.external_id)

      assert length(ids) > 1
      assert length(Enum.uniq(ids)) == 1
    end

    test "separates two different visits" do
      entries = Musee.parse_listing(listing())
      ids = entries |> Enum.map(& &1.event.external_id) |> Enum.uniq()

      assert length(ids) > 1
    end

    test "classifies a guided tour of an exhibition" do
      [%{event: event} | _rest] = Musee.parse_listing(listing())

      assert event.category == :guided_tour
    end

    test "only emits categories the schema can store" do
      # A category outside the enum is rejected at insert, so a scraper that
      # invents one loses every event silently.
      storable = Ecto.Enum.values(Sortir.Agenda.Event, :category)

      for %{event: event} <- Musee.parse_listing(listing()) do
        assert event.category in storable
      end
    end

    test "links back to the entry's own page" do
      [%{event: event} | _rest] = Musee.parse_listing(listing())

      assert event.url =~ "museedegrenoble.fr"
      assert event.url =~ "/agenda/"
    end

    test "never invents an end time" do
      # The museum publishes a start only.
      for %{occurrence: occurrence} <- Musee.parse_listing(listing()) do
        assert occurrence.ends_at == nil
      end
    end

    test "ignores markup that is not an entry" do
      assert Musee.parse_listing("<html><body>rien du tout</body></html>") == []
    end

    test "survives a truncated entry" do
      assert Musee.parse_listing(~s(<li class="calendar__item"><a href="/agenda/1/x.htm">)) == []
    end
  end

  describe "fetch/1" do
    test "follows pages until one has no successor" do
      # 313 entries over 32 pages: stopping at the first page would silently
      # drop everything after mid-August.
      {:ok, counter} = Agent.start_link(fn -> 0 end)

      get = fn _url ->
        page = Agent.get_and_update(counter, &{&1, &1 + 1})
        {:ok, if(page == 0, do: listing(), else: last_page())}
      end

      assert {:ok, scraped} = Musee.fetch(get: get, pace_ms: 0)

      assert Agent.get(counter, & &1) == 2, "should stop once a page offers no next link"
      assert length(scraped) == 13
    end

    test "stops at the page cap rather than looping forever" do
      # A site that always advertises a next page must not spin.
      {:ok, counter} = Agent.start_link(fn -> 0 end)

      get = fn _url ->
        Agent.update(counter, &(&1 + 1))
        {:ok, listing()}
      end

      assert {:ok, _scraped} = Musee.fetch(get: get, pace_ms: 0)
      assert Agent.get(counter, & &1) <= 40
    end

    test "keeps what it already read when a later page fails" do
      # A partial agenda beats none; the next scrape fills the gap.
      {:ok, counter} = Agent.start_link(fn -> 0 end)

      get = fn _url ->
        case Agent.get_and_update(counter, &{&1, &1 + 1}) do
          0 -> {:ok, listing()}
          _later -> {:error, {:http_status, 500}}
        end
      end

      assert {:ok, scraped} = Musee.fetch(get: get, pace_ms: 0)
      assert length(scraped) == 10
    end

    test "reports a failure on the very first page" do
      get = fn _url -> {:error, {:http_status, 500}} end

      assert {:error, {:http_status, 500}} = Musee.fetch(get: get, pace_ms: 0)
    end
  end
end

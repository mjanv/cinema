defmodule Sortir.Agenda.Sources.Mc2Test do
  use ExUnit.Case, async: true

  alias Sortir.Agenda.Fixtures
  alias Sortir.Agenda.Sources.Mc2

  defp page, do: Fixtures.json!("mc2_events")
  defp last_page, do: Fixtures.json!("mc2_events_last")

  describe "venue/0" do
    test "identifies the MC2" do
      venue = Mc2.venue()

      assert venue.slug == "mc2-grenoble"
      assert venue.city == "Grenoble"
      assert venue.kind == :theatre
    end
  end

  describe "parse_page/1" do
    test "reads every programmed performance in the response" do
      # 50 entries, 5 of which are a site announcement rather than a show.
      assert length(Mc2.parse_page(page())) == 45
    end

    test "skips announcements posted alongside the programme" do
      # The MC2 files news posts under /spectacle/ with no category, no price
      # and a start time that is really the moment it was published. Listing
      # "Durant l'été restez connectés !" as a show on five dates is wrong.
      titles = page() |> Mc2.parse_page() |> Enum.map(& &1.event.title)

      refute Enum.any?(titles, &String.contains?(&1, "restez connectés"))
    end

    test "keeps a show even when it carries only one category" do
      # The filter must key on *having* a billing, not on having several.
      entries = Mc2.parse_page(page())

      assert entries != []
      assert Enum.all?(entries, &(&1.event.labels != []))
    end

    test "reads the local start time, not the UTC one" do
      # The API gives both; `start_date` is what the venue prints on a ticket.
      [%{occurrence: occurrence} | _rest] = Mc2.parse_page(page())

      assert occurrence.starts_at == ~N[2026-10-02 20:00:00]
    end

    test "never trusts the end date" do
      # The API sets end_date equal to start_date on every event, so it says
      # nothing about when a show finishes. Storing it would claim every
      # performance lasts zero minutes.
      for %{occurrence: occurrence} <- Mc2.parse_page(page()) do
        assert occurrence.ends_at == nil
      end
    end

    test "gives every date of one production the same identity" do
      # The API returns one entry per date with a *different* numeric id, so
      # the id cannot be the identity: "I love you two" runs eight times and
      # must be one event, not eight.
      entries = Mc2.parse_page(page())

      ids =
        entries
        |> Enum.filter(&(&1.event.title == "I love you two"))
        |> Enum.map(& &1.event.external_id)

      assert length(ids) == 8
      assert length(Enum.uniq(ids)) == 1
    end

    test "keeps different productions apart" do
      ids = page() |> Mc2.parse_page() |> Enum.map(& &1.event.external_id) |> Enum.uniq()

      assert length(ids) > 5
    end

    test "reads the price as cents" do
      entry = Enum.find(Mc2.parse_page(page()), &(&1.event.title == "I love you two"))

      assert entry.occurrence.prices == [3000]
    end

    test "leaves prices empty when the event is free or unpriced" do
      # Not every entry has a cost; an empty list means "not published",
      # never zero.
      for %{occurrence: occurrence} <- Mc2.parse_page(page()) do
        assert is_list(occurrence.prices)
        refute 0 in occurrence.prices
      end
    end

    test "keeps the venue's own categories as labels" do
      entry = Enum.find(Mc2.parse_page(page()), &(&1.event.title == "I love you two"))

      assert "Cirque" in entry.event.labels
    end

    test "survives an event with no room" do
      # `venue` comes back as an empty list rather than a map when unset;
      # treating it as a map crashes the whole page.
      entries = Mc2.parse_page(page())

      assert Enum.any?(entries, &is_nil(&1.occurrence.room))
      assert Enum.any?(entries, &(&1.occurrence.room != nil))
    end

    test "records the room when there is one" do
      entry =
        Enum.find(Mc2.parse_page(page()), &String.starts_with?(&1.event.title, "Préambule"))

      assert entry.occurrence.room == "Salle multimédia"
    end

    test "decodes numeric entities in a title" do
      # WordPress emits typographic punctuation as numeric entities, which no
      # hand-written table can enumerate. `&#8211;` is an en dash.
      entry =
        Enum.find(Mc2.parse_page(page()), &String.starts_with?(&1.event.title, "Les Indes"))

      assert entry.event.title =~ "–"
      refute entry.event.title =~ "&#"
    end

    test "leaves no undecoded entity in any title" do
      for %{event: event} <- Mc2.parse_page(page()) do
        refute event.title =~ ~r/&(#\d+|[a-z]+);/,
               "undecoded entity in #{inspect(event.title)}"
      end
    end

    test "links to the event's own page" do
      [%{event: event} | _rest] = Mc2.parse_page(page())

      assert event.url =~ "mc2grenoble.fr"
    end

    test "only emits categories the schema can store" do
      storable = Ecto.Enum.values(Sortir.Agenda.Event, :category)

      for %{event: event} <- Mc2.parse_page(page()) do
        assert event.category in storable
      end
    end

    test "ignores a response that is not an event list" do
      assert Mc2.parse_page(%{}) == []
      assert Mc2.parse_page(%{"events" => "nonsense"}) == []
    end

    test "drops an event it cannot place in time" do
      assert Mc2.parse_page(%{"events" => [%{"title" => "Sans date"}]}) == []
    end
  end

  describe "fetch/1" do
    test "follows next_rest_url until the response omits it" do
      # The API states its own continuation; page arithmetic would guess.
      {:ok, counter} = Agent.start_link(fn -> 0 end)

      get = fn _url ->
        page = Agent.get_and_update(counter, &{&1, &1 + 1})
        {:ok, if(page == 0, do: page(), else: last_page())}
      end

      assert {:ok, scraped} = Mc2.fetch(get: get, pace_ms: 0)

      assert Agent.get(counter, & &1) == 2, "must stop when there is no next page"
      assert length(scraped) == 69, "45 shows on the first page, 24 on the last"
    end

    test "stops at the page cap rather than looping forever" do
      {:ok, counter} = Agent.start_link(fn -> 0 end)

      get = fn _url ->
        Agent.update(counter, &(&1 + 1))
        {:ok, page()}
      end

      assert {:ok, _scraped} = Mc2.fetch(get: get, pace_ms: 0)
      assert Agent.get(counter, & &1) <= 40
    end

    test "keeps what it read when a later page fails" do
      {:ok, counter} = Agent.start_link(fn -> 0 end)

      get = fn _url ->
        case Agent.get_and_update(counter, &{&1, &1 + 1}) do
          0 -> {:ok, page()}
          _later -> {:error, {:http_status, 500}}
        end
      end

      assert {:ok, scraped} = Mc2.fetch(get: get, pace_ms: 0)
      assert length(scraped) == 45
    end

    test "reports a failure on the first page" do
      get = fn _url -> {:error, {:http_status, 429}} end

      assert {:error, {:http_status, 429}} = Mc2.fetch(get: get, pace_ms: 0)
    end
  end
end

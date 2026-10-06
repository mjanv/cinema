defmodule Sortir.Agenda.Sources.BelleElectriqueTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias Sortir.Agenda.Fixtures
  alias Sortir.Agenda.Sources.BelleElectrique

  defp listing, do: Fixtures.html!("belle_electrique_programmation")

  describe "parse_listing/1" do
    test "extracts every event card on the page" do
      events = BelleElectrique.parse_listing(listing())

      assert length(events) == 7
      assert Enum.all?(events, &match?(%{event: _, occurrence: _}, &1))
    end

    test "reads a single evening's start and end" do
      %{event: event, occurrence: occurrence} = find(listing(), "Miami Vice")

      assert event.title == "Miami Vice"
      assert occurrence.starts_at == ~N[2026-09-04 18:00:00]
      assert occurrence.ends_at == ~N[2026-09-05 01:00:00]
    end

    test "keeps a night that crosses midnight as one interval" do
      # 23h55 to 05h30 the next morning is one outing, not two days.
      %{occurrence: occurrence} = find(listing(), "ACTRESS M")

      assert occurrence.starts_at == ~N[2026-09-12 23:55:00]
      assert occurrence.ends_at == ~N[2026-09-13 05:30:00]
    end

    test "rolls an end time past midnight onto the next day" do
      # "Du 05.09.26 / 16h au 05.09.26 / 1h" prints the same date twice, but 1h
      # is the following morning — taken literally the event ends before it
      # starts and is rejected on save.
      %{occurrence: occurrence} =
        listing()
        |> BelleElectrique.parse_listing()
        |> Enum.find(&(&1.event.external_id == "miami-vice-2-26"))

      assert occurrence.starts_at == ~N[2026-09-05 16:00:00]
      assert occurrence.ends_at == ~N[2026-09-06 01:00:00]
    end

    test "reads an event given only a single time" do
      %{occurrence: occurrence} = find(listing(), "Stand-up")

      assert occurrence.starts_at == ~N[2026-09-09 19:00:00]
      assert occurrence.ends_at == nil, "no end time must not be invented"
    end

    test "takes sold-out status off the title rather than leaving it there" do
      %{event: event, occurrence: occurrence} = find(listing(), "Meryl")

      assert event.title == "Meryl", "the COMPLET prefix is status, not part of the name"
      assert occurrence.status == :sold_out
    end

    test "defaults to unknown availability when the venue says nothing" do
      %{occurrence: occurrence} = find(listing(), "Miami Vice")

      assert occurrence.status == :unknown
    end

    test "keeps the venue's own genre words" do
      %{event: event} = find(listing(), "ACTRESS M")

      assert event.labels == ["Italo-Disco", "Trance"]
    end

    test "records the room separately from the genres" do
      %{occurrence: occurrence} = find(listing(), "ACTRESS M")

      assert occurrence.room == "Grande salle · Nuits"
    end

    test "carries the detail url and image" do
      %{event: event} = find(listing(), "Miami Vice")

      assert event.url =~ "/fr/agenda/miami-vice-1-26"
      assert event.image_url =~ "MINISITE-miami-vice"
      assert event.external_id == "miami-vice-1-26"
    end

    test "returns an empty list rather than raising on unexpected html" do
      assert BelleElectrique.parse_listing("<html><body>nope</body></html>") == []
    end
  end

  describe "parse_detail/1" do
    test "reads the price tiers as ascending cents" do
      detail = Fixtures.html!("belle_electrique_event")

      assert %{prices: prices} = BelleElectrique.parse_detail(detail)
      assert prices == [1300, 1400, 1700, 1900]
    end

    test "reads the ticketing link" do
      detail = Fixtures.html!("belle_electrique_event")

      assert %{ticket_url: url} = BelleElectrique.parse_detail(detail)
      assert url =~ "billetterie.la-belle-electrique.com"
    end

    test "reads the description" do
      detail = Fixtures.html!("belle_electrique_event")

      assert %{description: description} = BelleElectrique.parse_detail(detail)
      assert description =~ "Kendal"
    end

    test "degrades to empty extras rather than raising" do
      assert %{prices: [], ticket_url: nil} = BelleElectrique.parse_detail("<html></html>")
    end
  end

  describe "next_page/1" do
    test "reads the link to the following page" do
      # The venue paginates by page, not by month: one page carries a couple of
      # months and links to the next.
      assert BelleElectrique.next_page(listing()) == ~D[2026-10-01]
    end

    test "returns nil on the last page" do
      assert BelleElectrique.next_page("<html>no more</html>") == nil
    end
  end

  describe "fetch/1" do
    test "follows the venue's pagination to the end of the programme" do
      # One page carries a couple of months and links onward; stopping at the
      # first would silently truncate the programme.
      {:ok, counter} = Agent.start_link(fn -> 0 end)

      get = fn
        url ->
          if String.contains?(url, "/programmation") do
            page = Agent.get_and_update(counter, &{&1, &1 + 1})
            # Two pages, then no more links.
            if page == 0 do
              {:ok, Fixtures.html!("belle_electrique_programmation")}
            else
              {:ok, "<html>no more</html>"}
            end
          else
            {:ok, Fixtures.html!("belle_electrique_event")}
          end
      end

      assert {:ok, scraped} = BelleElectrique.fetch(get: get)

      assert length(scraped) == 7
      assert Agent.get(counter, & &1) == 2, "the next-page link must be followed"
    end

    test "keeps what it read when a later page fails" do
      {:ok, counter} = Agent.start_link(fn -> 0 end)

      get = fn url ->
        if String.contains?(url, "/programmation") do
          case Agent.get_and_update(counter, &{&1, &1 + 1}) do
            0 -> {:ok, Fixtures.html!("belle_electrique_programmation")}
            _later -> {:error, {:http_status, 429}}
          end
        else
          {:ok, Fixtures.html!("belle_electrique_event")}
        end
      end

      log =
        capture_log(fn ->
          assert {:ok, scraped} = BelleElectrique.fetch(get: get)
          assert length(scraped) == 7, "a late failure must not lose earlier pages"
        end)

      assert log =~ "stopped at page", "a truncated scrape must say so"
    end

    test "combines the listing with each event's detail page" do
      get = fn url ->
        cond do
          String.contains?(url, "from=") ->
            {:ok, "<html>no more</html>"}

          String.contains?(url, "/programmation") ->
            {:ok, Fixtures.html!("belle_electrique_programmation")}

          true ->
            {:ok, Fixtures.html!("belle_electrique_event")}
        end
      end

      assert {:ok, scraped} = BelleElectrique.fetch(get: get)

      assert length(scraped) == 7
      first = hd(scraped)
      assert first.occurrence.prices == [1300, 1400, 1700, 1900]
      assert first.occurrence.ticket_url =~ "billetterie"
      assert first.event.description =~ "Kendal"
    end

    test "keeps an event whose detail page fails" do
      # A failed detail fetch costs that event its extras, never the month.
      get = fn url ->
        cond do
          String.contains?(url, "from=") ->
            {:ok, "<html>no more</html>"}

          String.contains?(url, "/programmation") ->
            {:ok, Fixtures.html!("belle_electrique_programmation")}

          true ->
            {:error, :timeout}
        end
      end

      log =
        capture_log(fn ->
          assert {:ok, scraped} = BelleElectrique.fetch(get: get)

          assert length(scraped) == 7
          assert hd(scraped).event.title == "Miami Vice"
        end)

      assert log =~ "no detail for", "a missing detail page must be logged, not silent"
    end

    test "reports a failure to fetch the listing at all" do
      get = fn _url -> {:error, {:http_status, 429}} end

      assert {:error, {:http_status, 429}} = BelleElectrique.fetch(get: get)
    end
  end

  defp find(html, fragment) do
    html
    |> BelleElectrique.parse_listing()
    |> Enum.find(&String.contains?(&1.event.title, fragment))
    |> case do
      nil -> flunk("no event matching #{inspect(fragment)}")
      found -> found
    end
  end
end

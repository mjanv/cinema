defmodule Sortir.AgendaTest do
  use Sortir.Cinema.DataCase, async: false

  alias Sortir.Agenda
  alias Sortir.Agenda.{Event, Occurrence, Venue}
  alias Sortir.Core.{Clock, Repo}

  defp venue_attrs do
    %{
      slug: "la-belle-electrique",
      name: "La Belle Électrique",
      city: "Grenoble",
      kind: :music_hall
    }
  end

  # The agenda only counts dates still to come, so fixtures are relative to today.
  defp days_ahead(days, time \\ ~T[20:00:00]) do
    NaiveDateTime.new!(Date.add(Clock.today(), days), time)
  end

  defp scraped(overrides \\ %{}) do
    base = %{
      event: %{
        source: "belle_electrique",
        external_id: "miami-vice-1-26",
        title: "Miami Vice",
        category: :concert,
        labels: ["Funk"]
      },
      occurrence: %{
        room: "Bar",
        starts_at: ~N[2026-09-04 18:00:00],
        ends_at: ~N[2026-09-05 01:00:00],
        status: :unknown
      }
    }

    %{
      event: Map.merge(base.event, Map.get(overrides, :event, %{})),
      occurrence: Map.merge(base.occurrence, Map.get(overrides, :occurrence, %{}))
    }
  end

  describe "venues/0" do
    test "is empty before anything is scraped" do
      assert Agenda.venues() == []
    end

    test "reports what each venue has programmed" do
      {:ok, venue} = Agenda.upsert_venue(venue_attrs())
      {:ok, _first} =
        Agenda.save(
          scraped(%{occurrence: %{starts_at: days_ahead(1, ~T[18:00:00]), ends_at: nil}}),
          venue
        )

      {:ok, _second} =
        Agenda.save(
          scraped(%{
            event: %{external_id: "autre", title: "Autre"},
            occurrence: %{starts_at: days_ahead(3), ends_at: nil}
          }),
          venue
        )

      assert [listed] = Agenda.venues()

      assert listed.venue.slug == "la-belle-electrique"
      assert listed.events == 2
      assert listed.occurrences == 2
      assert listed.next == Date.add(Clock.today(), 1), "the soonest date still to come"
      assert listed.last == Date.add(Clock.today(), 3)
    end

    test "counts an event once however many times it is performed" do
      # A production on three nights is one event, three occurrences. Showing
      # 3 events would misreport how much a venue actually programmes.
      {:ok, venue} = Agenda.upsert_venue(venue_attrs())

      for at <- [~N[2026-09-04 20:00:00], ~N[2026-09-05 20:00:00], ~N[2026-09-06 20:00:00]] do
        {:ok, _event} = Agenda.save(scraped(%{occurrence: %{starts_at: at, ends_at: nil}}), venue)
      end

      assert [listed] = Agenda.venues()
      assert listed.events == 1
      assert listed.occurrences == 3
    end

    test "lists a venue that has nothing programmed" do
      # A scraper that has run but found nothing must still be visible, or a
      # broken source looks identical to one that was never added.
      {:ok, _venue} = Agenda.upsert_venue(venue_attrs())

      assert [listed] = Agenda.venues()
      assert listed.events == 0
      assert listed.occurrences == 0
      assert listed.next == nil
      assert listed.last == nil
    end

    test "orders by what each venue has coming up" do
      {:ok, quiet} = Agenda.upsert_venue(venue_attrs())

      {:ok, busy} =
        Agenda.upsert_venue(%{venue_attrs() | slug: "tmg", name: "TMG"})

      {:ok, _late} =
        Agenda.save(
          scraped(%{
            event: %{external_id: "tard"},
            occurrence: %{starts_at: days_ahead(30), ends_at: nil}
          }),
          quiet
        )

      {:ok, _soon} =
        Agenda.save(
          scraped(%{
            event: %{external_id: "bientot"},
            occurrence: %{starts_at: days_ahead(1), ends_at: nil}
          }),
          busy
        )

      assert [first, second] = Agenda.venues()
      assert first.venue.slug == "tmg"
      assert second.venue.slug == "la-belle-electrique"
    end
  end

  describe "scraped_at/0" do
    test "is nil on an empty agenda" do
      assert Agenda.scraped_at() == nil
    end

    test "reports when an event was last written" do
      {:ok, venue} = Agenda.upsert_venue(venue_attrs())
      {:ok, _event} = Agenda.save(scraped(), venue)

      assert %DateTime{} = at = Agenda.scraped_at()
      assert DateTime.diff(DateTime.utc_now(), at, :second) < 60
    end
  end

  describe "upsert_venue/1" do
    test "creates a venue, then returns the same one" do
      assert {:ok, first} = Agenda.upsert_venue(venue_attrs())
      assert {:ok, second} = Agenda.upsert_venue(venue_attrs())

      assert first.id == second.id
      assert Repo.aggregate(Venue, :count) == 1
    end

    test "updates details that changed" do
      {:ok, _first} = Agenda.upsert_venue(venue_attrs())
      {:ok, updated} = Agenda.upsert_venue(%{venue_attrs() | name: "La Belle Élec"})

      assert updated.name == "La Belle Élec"
    end
  end

  describe "save/3" do
    setup do
      {:ok, venue} = Agenda.upsert_venue(venue_attrs())
      {:ok, venue: venue}
    end

    test "stores an event with its occurrence", %{venue: venue} do
      assert {:ok, event} = Agenda.save(scraped(), venue)

      assert event.title == "Miami Vice"
      assert event.slug == "miami-vice"
      assert Repo.aggregate(Ecto.assoc(event, :occurrences), :count) == 1
    end

    test "re-scraping updates rather than duplicating", %{venue: venue} do
      # A source is scraped repeatedly; the same event must not accumulate.
      {:ok, _first} = Agenda.save(scraped(), venue)
      {:ok, _again} = Agenda.save(scraped(), venue)

      assert Repo.aggregate(Event, :count) == 1
      assert Repo.aggregate(Occurrence, :count) == 1
    end

    test "picks up details that changed between scrapes", %{venue: venue} do
      {:ok, _first} = Agenda.save(scraped(), venue)

      sold_out = scraped(%{occurrence: %{status: :sold_out}})
      {:ok, event} = Agenda.save(sold_out, venue)

      assert [occurrence] = Repo.all(Ecto.assoc(event, :occurrences))
      assert occurrence.status == :sold_out
    end

    test "keeps two occurrences of one event apart", %{venue: venue} do
      # A show on two nights is one event with two occurrences.
      {:ok, _first} = Agenda.save(scraped(), venue)

      second_night =
        scraped(%{occurrence: %{starts_at: ~N[2026-09-05 18:00:00], ends_at: nil}})

      {:ok, event} = Agenda.save(second_night, venue)

      assert Repo.aggregate(Ecto.assoc(event, :occurrences), :count) == 2
      assert Repo.aggregate(Event, :count) == 1
    end

    test "rejects an event a source could not identify", %{venue: venue} do
      broken = scraped(%{event: %{external_id: nil}})

      assert {:error, _changeset} = Agenda.save(broken, venue)
    end
  end

  describe "on/2" do
    setup do
      {:ok, venue} = Agenda.upsert_venue(venue_attrs())
      {:ok, venue: venue}
    end

    test "lists what is happening on a date", %{venue: venue} do
      {:ok, _event} = Agenda.save(scraped(), venue)

      assert [entry] = Agenda.on(~D[2026-09-04])
      assert entry.event.title == "Miami Vice"
      assert entry.occurrence.room == "Bar"
    end

    test "ignores other days", %{venue: venue} do
      {:ok, _event} = Agenda.save(scraped(), venue)

      assert Agenda.on(~D[2026-09-06]) == []
    end

    test "includes an exhibition whose run spans the date", %{venue: venue} do
      # An exhibition has no occurrence: it is placed by its run instead, and
      # must still appear on every day it is open.
      exhibition =
        scraped(%{
          event: %{
            external_id: "perriand",
            title: "Charlotte Perriand",
            category: :exhibition,
            runs_from: ~D[2026-03-14],
            runs_to: ~D[2026-07-20]
          }
        })
        |> Map.delete(:occurrence)

      {:ok, _event} = Agenda.save(exhibition, venue)

      assert [entry] = Agenda.on(~D[2026-05-01])
      assert entry.event.title == "Charlotte Perriand"
      assert entry.occurrence == nil, "an exhibition has no occurrence"

      assert Agenda.on(~D[2026-08-01]) == [], "outside the run it is not on"
    end

    test "groups a range of days, keeping empty ones out", %{venue: venue} do
      # The board shows a week; a day with nothing on should not render an
      # empty heading.
      for {id, at} <- [{"a", ~N[2026-09-04 18:00:00]}, {"b", ~N[2026-09-06 20:00:00]}] do
        {:ok, _event} =
          Agenda.save(
            scraped(%{
              event: %{external_id: id, title: id},
              occurrence: %{starts_at: at, ends_at: nil}
            }),
            venue
          )
      end

      days = Agenda.days(~D[2026-09-04], 4)

      assert Enum.map(days, & &1.date) == [~D[2026-09-04], ~D[2026-09-06]]
      assert [%{entries: [entry]} | _rest] = days
      assert entry.event.title == "a"
    end

    test "upcoming/2 skips a quiet spell to reach the next events", %{venue: venue} do
      # A venue closes for the summer. Looking a fixed window ahead shows an
      # empty page during exactly the period you want to know what is coming.
      {:ok, _event} =
        Agenda.save(
          scraped(%{
            event: %{external_id: "rentree", title: "La rentrée"},
            occurrence: %{starts_at: ~N[2026-09-04 20:00:00], ends_at: nil}
          }),
          venue
        )

      days = Agenda.upcoming(~D[2026-07-27], 5)

      assert [%{date: ~D[2026-09-04]} | _rest] = days
    end

    test "upcoming/2 ignores what has already happened", %{venue: venue} do
      {:ok, _past} =
        Agenda.save(
          scraped(%{
            event: %{external_id: "hier", title: "Hier"},
            occurrence: %{starts_at: ~N[2026-07-01 20:00:00], ends_at: nil}
          }),
          venue
        )

      assert Agenda.upcoming(~D[2026-07-27], 5) == []
    end

    test "groups repeated showings of one event on the same day", %{venue: venue} do
      # A museum runs the same 20-minute tour six times in a day. Six identical
      # rows differing only by time is noise; it is one thing to go to, with
      # six start times.
      for at <- [~T[10:30:00], ~T[11:00:00], ~T[15:00:00]] do
        {:ok, _event} =
          Agenda.save(
            scraped(%{
              event: %{external_id: "flash", title: "Visite flash"},
              occurrence: %{starts_at: NaiveDateTime.new!(~D[2026-09-04], at), ends_at: nil}
            }),
            venue
          )
      end

      assert [entry] = Agenda.on(~D[2026-09-04])
      assert entry.event.title == "Visite flash"
      assert length(entry.occurrences) == 3

      assert Enum.map(entry.occurrences, &DateTime.to_time(Clock.to_local(&1.starts_at))) ==
               [~T[10:30:00], ~T[11:00:00], ~T[15:00:00]]
    end

    test "keeps the earliest showing as the entry's own occurrence", %{venue: venue} do
      # `occurrence` stays the first one so ordering and existing readers are
      # unaffected by grouping.
      for at <- [~T[15:00:00], ~T[10:30:00]] do
        {:ok, _event} =
          Agenda.save(
            scraped(%{
              event: %{external_id: "flash"},
              occurrence: %{starts_at: NaiveDateTime.new!(~D[2026-09-04], at), ends_at: nil}
            }),
            venue
          )
      end

      assert [entry] = Agenda.on(~D[2026-09-04])
      assert DateTime.to_time(Clock.to_local(entry.occurrence.starts_at)) == ~T[10:30:00]
    end

    test "keeps showings in different rooms apart", %{venue: venue} do
      # Two rooms is two different offerings, even for the same production on
      # the same day: which room you go to changes what you book.
      for {room, at} <- [{"Grande salle", ~T[18:00:00]}, {"Petite salle", ~T[20:00:00]}] do
        {:ok, _event} =
          Agenda.save(
            scraped(%{
              event: %{external_id: "double"},
              occurrence: %{
                starts_at: NaiveDateTime.new!(~D[2026-09-04], at),
                ends_at: nil,
                room: room
              }
            }),
            venue
          )
      end

      assert [first, second] = Agenda.on(~D[2026-09-04])
      assert first.occurrence.room == "Grande salle"
      assert second.occurrence.room == "Petite salle"
      assert length(first.occurrences) == 1
    end

    test "keeps different events apart", %{venue: venue} do
      for id <- ["a", "b"] do
        {:ok, _event} =
          Agenda.save(
            scraped(%{
              event: %{external_id: id, title: id},
              occurrence: %{starts_at: ~N[2026-09-04 20:00:00], ends_at: nil}
            }),
            venue
          )
      end

      assert length(Agenda.on(~D[2026-09-04])) == 2
    end

    test "an exhibition still has an empty occurrence list", %{venue: venue} do
      exhibition =
        scraped(%{
          event: %{
            external_id: "expo",
            title: "Expo",
            category: :exhibition,
            runs_from: ~D[2026-09-01],
            runs_to: ~D[2026-09-30]
          }
        })
        |> Map.delete(:occurrence)

      {:ok, _event} = Agenda.save(exhibition, venue)

      assert [entry] = Agenda.on(~D[2026-09-04])
      assert entry.occurrence == nil
      assert entry.occurrences == []
    end

    test "orders a day chronologically", %{venue: venue} do
      for {id, at} <- [{"late", ~N[2026-09-04 21:00:00]}, {"early", ~N[2026-09-04 18:00:00]}] do
        {:ok, _event} =
          Agenda.save(
            scraped(%{
              event: %{external_id: id, title: id},
              occurrence: %{starts_at: at, ends_at: nil}
            }),
            venue
          )
      end

      assert ["early", "late"] = Agenda.on(~D[2026-09-04]) |> Enum.map(& &1.event.title)
    end
  end
end

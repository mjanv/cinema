defmodule Sortir.Agenda.OccurrenceTest do
  use Sortir.Cinema.DataCase, async: false

  alias Sortir.Agenda.{Event, Occurrence, Venue}
  alias Sortir.Core.Repo

  defp venue(slug \\ "la-belle-electrique") do
    {:ok, venue} =
      %Venue{}
      |> Venue.changeset(%{
        slug: slug,
        name: "La Belle Électrique",
        city: "Grenoble",
        kind: :music_hall
      })
      |> Repo.insert()

    venue
  end

  defp event(attrs \\ %{}) do
    {:ok, event} =
      %Event{}
      |> Event.changeset(
        Map.merge(
          %{
            source: "belle_electrique",
            external_id: "e-#{System.unique_integer([:positive])}",
            title: "Un concert"
          },
          attrs
        )
      )
      |> Repo.insert()

    event
  end

  test "stores a night that crosses midnight as an interval" do
    # A club night running 23h55 to 05h30 belongs to the evening you go out,
    # not to two calendar days.
    attrs = %{
      event_id: event().id,
      venue_id: venue().id,
      starts_at: ~U[2026-09-12 21:55:00Z],
      ends_at: ~U[2026-09-13 03:30:00Z]
    }

    assert {:ok, occurrence} = %Occurrence{} |> Occurrence.changeset(attrs) |> Repo.insert()
    assert DateTime.compare(occurrence.ends_at, occurrence.starts_at) == :gt
  end

  test "accepts an occurrence with no end time" do
    # Many venues publish only "19h30"; inferring a duration would invent data.
    attrs = %{event_id: event().id, venue_id: venue().id, starts_at: ~U[2026-09-19 08:00:00Z]}

    assert {:ok, %{ends_at: nil}} = %Occurrence{} |> Occurrence.changeset(attrs) |> Repo.insert()
  end

  test "rejects an end before the start" do
    attrs = %{
      event_id: event().id,
      venue_id: venue().id,
      starts_at: ~U[2026-09-19 20:00:00Z],
      ends_at: ~U[2026-09-19 18:00:00Z]
    }

    refute Occurrence.changeset(%Occurrence{}, attrs).valid?
  end

  test "keeps price tiers as ascending cents" do
    attrs = %{
      event_id: event().id,
      venue_id: venue().id,
      starts_at: ~U[2026-09-12 21:55:00Z],
      prices: [1300, 1400, 1700, 1900]
    }

    assert {:ok, occurrence} = %Occurrence{} |> Occurrence.changeset(attrs) |> Repo.insert()
    assert occurrence.prices == [1300, 1400, 1700, 1900]
  end

  test "defaults to unknown availability rather than claiming seats are free" do
    attrs = %{event_id: event().id, venue_id: venue().id, starts_at: ~U[2026-09-12 21:55:00Z]}

    assert {:ok, %{status: :unknown}} =
             %Occurrence{} |> Occurrence.changeset(attrs) |> Repo.insert()
  end

  test "one event may play several venues" do
    # A touring production: same work, different places, which is why the venue
    # lives on the occurrence.
    show = event(%{title: "Faune"})
    tmg = venue("tmg")
    ilyade = venue("l-ilyade")

    for {v, at} <- [{tmg, ~U[2026-09-19 08:00:00Z]}, {ilyade, ~U[2027-03-03 18:30:00Z]}] do
      assert {:ok, _occurrence} =
               %Occurrence{}
               |> Occurrence.changeset(%{event_id: show.id, venue_id: v.id, starts_at: at})
               |> Repo.insert()
    end

    assert Repo.aggregate(Ecto.assoc(show, :occurrences), :count) == 2
  end

  test "the same performance cannot be recorded twice" do
    show = event()
    place = venue()
    attrs = %{event_id: show.id, venue_id: place.id, starts_at: ~U[2026-09-19 08:00:00Z]}

    {:ok, _first} = %Occurrence{} |> Occurrence.changeset(attrs) |> Repo.insert()

    assert {:error, changeset} = %Occurrence{} |> Occurrence.changeset(attrs) |> Repo.insert()
    assert errors_on(changeset) != %{}
  end

  test "an exhibition is an event with a run and no occurrences" do
    show =
      event(%{
        category: :exhibition,
        title: "Charlotte Perriand",
        runs_from: ~D[2026-03-14],
        runs_to: ~D[2026-07-20]
      })

    assert Repo.aggregate(Ecto.assoc(show, :occurrences), :count) == 0
    assert show.runs_from == ~D[2026-03-14]
  end
end

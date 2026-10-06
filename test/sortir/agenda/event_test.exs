defmodule Sortir.Agenda.EventTest do
  use Sortir.Cinema.DataCase, async: false

  alias Sortir.Agenda.Event
  alias Sortir.Core.Repo

  @valid %{
    source: "belle_electrique",
    external_id: "miami-vice-1-26",
    title: "Miami Vice",
    category: :concert
  }

  test "derives the public slug from the title" do
    # The source's key stays internal; the slug is what appears in URLs, so a
    # change of source cannot break a bookmark.
    assert %{valid?: true} = changeset = Event.changeset(%Event{}, @valid)
    assert Ecto.Changeset.get_field(changeset, :slug) == "miami-vice"
  end

  test "requires the identity a source must supply" do
    changeset = Event.changeset(%Event{}, %{})

    assert errors_on(changeset).source
    assert errors_on(changeset).external_id
    assert errors_on(changeset).title
  end

  test "keeps the source's own labels rather than normalising them" do
    changeset = Event.changeset(%Event{}, Map.put(@valid, :labels, ["Italo-Disco", "Trance"]))

    assert Ecto.Changeset.get_field(changeset, :labels) == ["Italo-Disco", "Trance"]
  end

  test "accepts an exhibition, which has a run but no occurrences" do
    attrs =
      @valid
      |> Map.merge(%{
        category: :exhibition,
        runs_from: ~D[2026-03-14],
        runs_to: ~D[2026-07-20]
      })

    assert %{valid?: true} = Event.changeset(%Event{}, attrs)
  end

  test "rejects a run that ends before it starts" do
    attrs = Map.merge(@valid, %{runs_from: ~D[2026-07-20], runs_to: ~D[2026-03-14]})

    refute Event.changeset(%Event{}, attrs).valid?
  end

  test "two sources may share an external id without colliding" do
    {:ok, _first} = %Event{} |> Event.changeset(@valid) |> Repo.insert()

    other_source = Map.put(@valid, :source, "tmg")
    assert {:ok, _second} = %Event{} |> Event.changeset(other_source) |> Repo.insert()
  end

  test "the same event from one source is upserted, not duplicated" do
    {:ok, _first} = %Event{} |> Event.changeset(@valid) |> Repo.insert()

    assert {:error, changeset} = %Event{} |> Event.changeset(@valid) |> Repo.insert()
    # Ecto attributes a composite unique constraint to its first field.
    assert errors_on(changeset).source == ["has already been taken"]
  end
end

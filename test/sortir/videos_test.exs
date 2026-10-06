defmodule Sortir.VideosTest do
  use Sortir.Cinema.DataCase, async: false

  alias Sortir.Videos

  defp video(id, title, attrs \\ %{}) do
    Map.merge(
      %{youtube_id: id, title: title, published_at: ~U[2026-10-05 12:00:00Z], views: 10},
      attrs
    )
  end

  describe "save/1" do
    test "stores a video" do
      assert {:ok, _} = Videos.save(video("a", "Tour de Lombardie"))

      assert [%{youtube_id: "a", views: 10}] = Videos.list()
    end

    test "re-saving updates the views instead of duplicating" do
      {:ok, _} = Videos.save(video("a", "Tour de Lombardie", %{views: 10}))
      {:ok, _} = Videos.save(video("a", "Tour de Lombardie", %{views: 5000}))

      assert [%{views: 5000}] = Videos.list()
    end

    test "rejects a video without a title or id" do
      assert {:error, changeset} = Videos.save(%{views: 1})

      assert %{youtube_id: _, title: _, published_at: _} = errors_on(changeset)
    end
  end

  describe "list/1" do
    test "returns the newest first" do
      {:ok, _} = Videos.save(video("old", "Old", %{published_at: ~U[2026-09-01 00:00:00Z]}))
      {:ok, _} = Videos.save(video("new", "New", %{published_at: ~U[2026-10-01 00:00:00Z]}))

      assert ["new", "old"] = Enum.map(Videos.list(), & &1.youtube_id)
    end

    test "matches a substring of the title" do
      {:ok, _} = Videos.save(video("a", "Grand Prix de Bahreïn"))
      {:ok, _} = Videos.save(video("b", "Tour de Lombardie"))

      assert ["b"] = "lombar" |> Videos.list() |> Enum.map(& &1.youtube_id)
    end

    test "ignores case and accents, both ways" do
      {:ok, _} = Videos.save(video("a", "Grand Prix de Bahreïn"))
      {:ok, _} = Videos.save(video("b", "Étape 3 du Tour"))

      assert ["a"] = "BAHREIN" |> Videos.list() |> Enum.map(& &1.youtube_id)
      assert ["b"] = "etape" |> Videos.list() |> Enum.map(& &1.youtube_id)
      assert ["a"] = "bahreïn" |> Videos.list() |> Enum.map(& &1.youtube_id)
    end

    test "treats a blank query as no filter" do
      {:ok, _} = Videos.save(video("a", "A"))

      assert [_] = Videos.list("   ")
      assert [_] = Videos.list(nil)
    end

    test "returns nothing when nothing matches" do
      {:ok, _} = Videos.save(video("a", "Tour de Lombardie"))

      assert [] = Videos.list("roland garros")
    end

    test "treats the query as text, not as a pattern" do
      {:ok, _} = Videos.save(video("a", "Tour de Lombardie"))

      assert [] = Videos.list("%")
      assert [] = Videos.list(".*")
    end
  end

  describe "prune/1" do
    @now ~U[2026-10-31 12:00:00Z]

    test "deletes videos published more than a month ago" do
      {:ok, _} = Videos.save(video("old", "Old", %{published_at: ~U[2026-09-29 00:00:00Z]}))
      {:ok, _} = Videos.save(video("new", "New", %{published_at: ~U[2026-10-20 00:00:00Z]}))

      assert 1 = Videos.prune(@now)
      assert ["new"] = Enum.map(Videos.list(), & &1.youtube_id)
    end

    test "a month is a calendar month: 31 October keeps 30 September, drops 29 September" do
      {:ok, _} = Videos.save(video("kept", "Kept", %{published_at: ~U[2026-09-30 12:00:00Z]}))
      {:ok, _} = Videos.save(video("gone", "Gone", %{published_at: ~U[2026-09-30 11:59:59Z]}))

      assert 1 = Videos.prune(@now)
      assert ["kept"] = Enum.map(Videos.list(), & &1.youtube_id)
    end

    test "returns 0 and deletes nothing when everything is recent" do
      {:ok, _} = Videos.save(video("a", "A", %{published_at: ~U[2026-10-30 00:00:00Z]}))

      assert 0 = Videos.prune(@now)
      assert [_] = Videos.list()
    end

    test "works on an empty table" do
      assert 0 = Videos.prune(@now)
    end
  end

  describe "retained?/2" do
    test "is true for a video published within the month, false before it" do
      now = ~U[2026-10-31 12:00:00Z]

      assert Videos.retained?(%{published_at: ~U[2026-10-01 00:00:00Z]}, now)
      assert Videos.retained?(%{published_at: ~U[2026-09-30 12:00:00Z]}, now)
      refute Videos.retained?(%{published_at: ~U[2026-09-30 11:59:59Z]}, now)
    end
  end

  describe "a later batch" do
    test "adds the new videos, updates the ones seen again, and keeps the ones that dropped out" do
      # The feed only lists the 15 newest: by the next poll the oldest have
      # fallen off it, and they must stay.
      first = [
        video("old", "Old", %{published_at: ~U[2026-10-01 00:00:00Z], views: 10}),
        video("mid", "Mid", %{published_at: ~U[2026-10-02 00:00:00Z], views: 20})
      ]

      second = [
        video("new", "New", %{published_at: ~U[2026-10-03 00:00:00Z], views: 1}),
        video("mid", "Mid", %{published_at: ~U[2026-10-02 00:00:00Z], views: 999})
      ]

      for batch <- [first, second], attrs <- batch, do: {:ok, _} = Videos.save(attrs)

      assert [{"new", 1}, {"mid", 999}, {"old", 10}] =
               Enum.map(Videos.list(), &{&1.youtube_id, &1.views})
    end

    test "picks up a title the channel edited" do
      {:ok, _} = Videos.save(video("a", "Titre provisoire"))
      {:ok, _} = Videos.save(video("a", "COPPA BERNOCCHI 2026"))

      assert [_] = Videos.list("bernocchi")
      assert [] = Videos.list("provisoire")
    end
  end

  describe "get/1" do
    test "finds a stored video by its YouTube id" do
      {:ok, _} = Videos.save(video("abc", "Tour"))

      assert %{youtube_id: "abc"} = Videos.get("abc")
    end

    test "is nil for an id we never stored, so only known videos can be played" do
      assert Videos.get("nope") == nil
      assert Videos.get(nil) == nil
    end
  end

  describe "list/1 with several words" do
    setup do
      {:ok, _} =
        Videos.save(
          video("a", "VICTOIRE ! Noa Isidore remporte la Coppa Bernocchi #cycling", %{
            published_at: ~U[2026-10-06 11:00:00Z]
          })
        )

      :ok
    end

    test "matches when every word is in the title, in any order" do
      assert [_] = Videos.list("coppa bernocchi")
      assert [_] = Videos.list("bernocchi coppa")
      assert [_] = Videos.list("COPPA   BERNOCCHI")
    end

    test "does not match when one word is missing" do
      assert [] = Videos.list("coppa lombardie")
    end

    test "a year matches the publication year, since titles rarely carry it" do
      assert [_] = Videos.list("COPPA BERNOCCHI 2026")
      assert [_] = Videos.list("2026")
    end

    test "a different year does not match" do
      assert [] = Videos.list("coppa bernocchi 2025")
    end

    test "the match is the phrase when the words are together" do
      assert [%{match: "Coppa Bernocchi"}] = Videos.list("coppa bernocchi 2026")
    end

    test "the match is the separate words when they are apart" do
      assert [%{match: "Noa … Bernocchi"}] = Videos.list("bernocchi noa")
    end

    test "a year alone matches without revealing any of the title" do
      assert [%{match: nil}] = Videos.list("2026")
    end
  end

  describe "list/1 segments" do
    # The title, in order, as bars and shown text: the hidden parts only as a
    # length, never as text.
    test "put the match at its place in the title, the rest as lengths" do
      {:ok, _} = Videos.save(video("a", "Tour de Lombardie : Pogacar s'impose"))

      assert [%{segments: [{:hidden, 8}, {:shown, "Lombardie"}, {:hidden, 19}]}] =
               Videos.list("lombardie")
    end

    test "have no leading bar when the match starts the title" do
      {:ok, _} = Videos.save(video("a", "Tour de Lombardie"))

      assert [%{segments: [{:shown, "Tour"}, {:hidden, 13}]}] = Videos.list("tour")
    end

    test "have no trailing bar when the match ends the title" do
      {:ok, _} = Videos.save(video("a", "Tour de Lombardie"))

      assert [%{segments: [{:hidden, 8}, {:shown, "Lombardie"}]}] = Videos.list("lombardie")
    end

    test "show every matched word at its own place" do
      {:ok, _} = Videos.save(video("a", "Noa Isidore remporte la Coppa Bernocchi"))

      assert [%{segments: segments}] = Videos.list("bernocchi noa")

      assert segments == [
               {:shown, "Noa"},
               {:hidden, 27},
               {:shown, "Bernocchi"}
             ]
    end

    test "merge matches that touch or overlap into one" do
      {:ok, _} = Videos.save(video("a", "Grand Prix de Bahreïn"))

      assert [%{segments: [{:shown, "Grand Prix"}, {:hidden, 11}]}] =
               Videos.list("grand prix")

      assert [%{segments: [{:shown, "Grand Prix"}, {:hidden, 11}]}] =
               Videos.list("prix grand")
    end

    test "cover the whole title: lengths and shown text add up to it" do
      title = "Grand Prix de Bahreïn : Verstappen vainqueur"
      {:ok, _} = Videos.save(video("a", title))

      assert [%{segments: segments}] = Videos.list("bahrein")

      total =
        Enum.sum_by(segments, fn
          {:hidden, length} -> length
          {:shown, text} -> String.length(text)
        end)

      assert total == String.length(title)
    end

    test "never carry hidden text" do
      {:ok, _} = Videos.save(video("a", "Tour de Lombardie : Pogacar s'impose"))

      assert [%{segments: segments}] = Videos.list("lombardie")

      assert Enum.all?(segments, fn
               {:hidden, length} -> is_integer(length)
               {:shown, text} -> text == "Lombardie"
             end)
    end

    test "are nil without a query, and when only a year matched" do
      {:ok, _} =
        Videos.save(video("a", "Tour de Lombardie", %{published_at: ~U[2026-10-05 12:00:00Z]}))

      assert [%{segments: nil}] = Videos.list()
      assert [%{segments: nil}] = Videos.list("2026")
    end
  end

  describe "list/1 match" do
    test "is the part of the title that matched, as the title spells it" do
      {:ok, _} = Videos.save(video("a", "Grand Prix de Bahreïn : Verstappen vainqueur"))

      assert [%{match: "Bahreïn"}] = Videos.list("BAHREIN")
    end

    test "is only the matched part, never the whole title" do
      {:ok, _} = Videos.save(video("a", "Tour de Lombardie : Pogacar s'impose"))

      assert [%{match: "Lombardie"}] = Videos.list("lombardie")
      assert [%{match: "Tour de Lom"}] = Videos.list("tour de lom")
    end

    test "is the first occurrence when the title repeats it" do
      {:ok, _} = Videos.save(video("a", "Tour de France, Tour de Pologne"))

      assert [%{match: "Tour"}] = Videos.list("tour")
    end

    test "keeps accents the query did not type, across a decomposed title" do
      {:ok, _} = Videos.save(video("a", "E\u0301tape 3"))

      assert [%{match: "E\u0301tape"}] = Videos.list("etape")
    end

    test "is nil when there is no query" do
      {:ok, _} = Videos.save(video("a", "Tour de Lombardie"))

      assert [%{match: nil}] = Videos.list()
      assert [%{match: nil}] = Videos.list("  ")
    end
  end

  describe "fetched_at/0" do
    test "is nil before the first fetch" do
      assert Videos.fetched_at() == nil
    end

    test "is the last time a video was saved" do
      {:ok, _} = Videos.save(video("a", "A"))

      assert %DateTime{} = Videos.fetched_at()
    end
  end
end

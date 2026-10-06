defmodule Sortir.Videos.FeedTest do
  use ExUnit.Case, async: true

  alias Sortir.Videos.Feed

  @xml File.read!("test/support/fixtures/videos/feed.xml")

  describe "parse/1" do
    test "reads one video per entry, in feed order" do
      assert [
               %{youtube_id: "AAAAAAAAAA1"},
               %{youtube_id: "BBBBBBBBBB2"},
               %{youtube_id: "CCCCCCCCCC3"}
             ] =
               Feed.parse(@xml)
    end

    test "reads the publication date as UTC" do
      [first | _] = Feed.parse(@xml)

      assert first.published_at == ~U[2026-10-05 14:10:31Z]
    end

    test "reads the view count as an integer" do
      assert [4417, 120, 98_765] = @xml |> Feed.parse() |> Enum.map(& &1.views)
    end

    test "decodes XML entities in titles" do
      [_, second, _] = Feed.parse(@xml)

      assert second.title == ~s("C'était éblouissant" : Tom & Jerry au Grand Prix de Bahreïn)
    end

    test "takes the entry's own title, not the channel's" do
      assert Enum.all?(Feed.parse(@xml), &(&1.title != "Eurosport France"))
    end

    test "defaults views to 0 when the entry has no statistics" do
      xml = String.replace(@xml, ~r{<media:statistics views="120"/>}, "")

      assert [_, %{views: 0}, _] = Feed.parse(xml)
    end

    test "skips an entry without a video id or date instead of raising" do
      xml = String.replace(@xml, "<yt:videoId>BBBBBBBBBB2</yt:videoId>", "")

      assert ["AAAAAAAAAA1", "CCCCCCCCCC3"] = xml |> Feed.parse() |> Enum.map(& &1.youtube_id)
    end

    test "returns no videos for something that is not a feed" do
      assert [] = Feed.parse("<html>nope</html>")
      assert [] = Feed.parse(nil)
    end
  end

  describe "fetch/1" do
    test "parses what the HTTP function returns" do
      assert {:ok, [_, _, _]} = Feed.fetch(get: fn _url -> {:ok, @xml} end)
    end

    test "requests the channel's long-form videos, not its Shorts or lives" do
      test = self()
      Feed.fetch(get: fn url -> send(test, {:url, url}) && {:ok, @xml} end)

      # UULF + the channel id without its "UC": the "Vidéos" tab. UUSH is the
      # Shorts, UULV the lives, and the plain channel feed mixes all three.
      assert_received {:url,
                       "https://www.youtube.com/feeds/videos.xml?playlist_id=UULFozt5iXNqmhU1I7tcjJ0UFQ"}
    end

    test "passes an HTTP error through" do
      assert {:error, {:http_status, 500}} =
               Feed.fetch(get: fn _ -> {:error, {:http_status, 500}} end)
    end
  end
end

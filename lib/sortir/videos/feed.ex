defmodule Sortir.Videos.Feed do
  @moduledoc """
  Reads the Eurosport France channel's public RSS feed.

  Reads the channel's "Vidéos" tab, not the plain channel feed: that one mixes
  in the Shorts, which are most of what the channel posts and would crowd the
  long videos out of the 15 slots. The tab is the playlist `UULF` + the channel
  id without its `UC` prefix (`UUSH` is the Shorts, `UULV` the live streams).

  The feed needs no API key but only ever lists the 15 newest, so it must be
  polled often; `Sortir.Videos.Jobs.Fetch` does that and the database
  accumulates what passes through.

  Parsed with regexes rather than an XML library, as the scrapers are: the
  feed's shape is fixed and an entry that does not fit is dropped.
  """

  # Channel UCozt5iXNqmhU1I7tcjJ0UFQ — https://www.youtube.com/@EurosportFrance
  @url "https://www.youtube.com/feeds/videos.xml?playlist_id=UULFozt5iXNqmhU1I7tcjJ0UFQ"

  @type video :: %{
          youtube_id: String.t(),
          title: String.t(),
          published_at: DateTime.t(),
          views: non_neg_integer()
        }

  @doc "The newest videos of the channel."
  @spec fetch(keyword()) :: {:ok, [video()]} | {:error, term()}
  def fetch(opts \\ []) do
    get = Keyword.get(opts, :get, &get_xml/1)

    with {:ok, xml} <- get.(@url), do: {:ok, parse(xml)}
  end

  @doc "Videos in a feed, newest first as the feed lists them."
  @spec parse(String.t() | nil) :: [video()]
  def parse(xml) when is_binary(xml) do
    ~r{<entry>(.*?)</entry>}s
    |> Regex.scan(xml, capture: :all_but_first)
    |> Enum.flat_map(fn [entry] -> parse_entry(entry) end)
  end

  def parse(_xml), do: []

  defp parse_entry(entry) do
    with id when is_binary(id) <- capture(~r{<yt:videoId>(.*?)</yt:videoId>}, entry),
         title when is_binary(title) <- capture(~r{<title>(.*?)</title>}s, entry),
         iso when is_binary(iso) <- capture(~r{<published>(.*?)</published>}, entry),
         {:ok, published_at, _offset} <- DateTime.from_iso8601(iso) do
      [
        %{
          youtube_id: id,
          title: decode(title),
          published_at: published_at,
          views: views(entry)
        }
      ]
    else
      _unparseable -> []
    end
  end

  defp views(entry) do
    case capture(~r{<media:statistics views="(\d+)"}, entry) do
      nil -> 0
      count -> String.to_integer(count)
    end
  end

  defp capture(regex, text) do
    case Regex.run(regex, text, capture: :all_but_first) do
      [match] -> match
      nil -> nil
    end
  end

  @entities %{"quot" => "\"", "amp" => "&", "lt" => "<", "gt" => ">", "apos" => "'"}

  defp decode(text) do
    Regex.replace(~r/&(#x[0-9a-fA-F]+|#\d+|\w+);/, text, fn whole, entity ->
      case entity do
        "#x" <> hex -> <<String.to_integer(hex, 16)::utf8>>
        "#" <> dec -> <<String.to_integer(dec)::utf8>>
        name -> Map.get(@entities, name, whole)
      end
    end)
  end

  defp get_xml(url) do
    case Req.get(url, decode_body: false, retry: :transient, max_retries: 2) do
      {:ok, %Req.Response{status: 200, body: body}} -> {:ok, body}
      {:ok, %Req.Response{status: status}} -> {:error, {:http_status, status}}
      {:error, reason} -> {:error, reason}
    end
  end
end

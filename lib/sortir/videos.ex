defmodule Sortir.Videos do
  @moduledoc """
  The public interface of the videos domain: Eurosport France's uploads, kept
  so a viewer can look for a race without being told who won it.

  `SortirWeb` calls this module and nothing else. Titles are stored and
  searchable, but callers decide whether to show them; the page built on this
  never does.

  Videos accumulate: the feed lists only the 15 newest, so `save/1` upserts on
  `youtube_id` and the history grows from the day the app starts polling. It
  does not grow forever: `prune/1` drops what is older than a month, and
  `retained?/2` is how the fetch avoids bringing it straight back.
  """

  import Ecto.Query

  alias Phoenix.PubSub
  alias Sortir.Core.Repo
  alias Sortir.Videos.Jobs.Fetch
  alias Sortir.Videos.Video

  @pubsub Sortir.Core.PubSub
  @topic "videos"

  # YouTube serves the feed with `cache-control: max-age=900`: a fetch sooner
  # than that after the last one returns the same thing.
  @refresh_window 900

  @doc "Queues a fetch of the feed. `{:ok, 0}` when one is already waiting."
  @spec refresh() :: {:ok, 0 | 1}
  def refresh, do: Fetch.enqueue()

  @doc """
  Queues a fetch because someone opened the page, unless one ran, or is
  waiting, in the last 15 minutes.

  Without that limit every page view would be a request to YouTube. A finished
  fetch counts here, unlike for the cron's `refresh/0`, which is never held
  back by an earlier one.
  """
  @spec request_refresh() :: {:ok, 0 | 1}
  def request_refresh do
    Fetch.enqueue(
      unique: [period: @refresh_window, states: Oban.Job.states() -- [:discarded, :cancelled]]
    )
  end

  @doc """
  Saves what a fetch brought back, and tells open pages if any of it was new.

  Skips videos past the retention period (see `retained?/2`). Only a new video
  is announced: view counts change on every fetch, and re-drawing every open
  page for that would be noise. Returns how many were fetched, saved and new.
  """
  @spec ingest([map()]) :: %{
          fetched: non_neg_integer(),
          saved: non_neg_integer(),
          new: non_neg_integer()
        }
  def ingest(fetched) do
    recent = Enum.filter(fetched, &retained?/1)
    ids = Enum.map(recent, & &1.youtube_id)

    known =
      from(v in Video, where: v.youtube_id in ^ids, select: v.youtube_id)
      |> Repo.all()
      |> MapSet.new()

    saved = Enum.filter(recent, &match?({:ok, _video}, save(&1)))
    new = Enum.count(saved, &(&1.youtube_id not in known))

    if new > 0, do: PubSub.broadcast(@pubsub, @topic, :videos_updated)

    %{fetched: length(fetched), saved: length(saved), new: new}
  end

  @doc "Subscribes the calling process to `:videos_updated`, sent when new videos arrive."
  @spec subscribe() :: :ok | {:error, {:already_registered, pid()}}
  def subscribe, do: PubSub.subscribe(@pubsub, @topic)

  @doc "Creates a video, or updates the one with this `youtube_id`."
  @spec save(map()) :: {:ok, Video.t()} | {:error, Ecto.Changeset.t()}
  def save(attrs) do
    attrs
    |> find()
    |> Video.changeset(attrs)
    |> Repo.insert_or_update()
  end

  defp find(%{youtube_id: id}) when is_binary(id),
    do: Repo.get_by(Video, youtube_id: id) || %Video{}

  defp find(_unidentified), do: %Video{}

  @doc """
  Deletes videos published more than a month before `now`, and returns how many.

  A calendar month, so on 31 October a video from 30 September noon is kept and
  one from before it goes. Run daily from cron by `Sortir.Videos.Jobs.Prune`.
  """
  @spec prune(DateTime.t()) :: non_neg_integer()
  def prune(now \\ DateTime.utc_now()) do
    {count, _} = Repo.delete_all(from(v in Video, where: v.published_at < ^cutoff(now)))

    count
  end

  @doc """
  Whether a video is recent enough to keep.

  The fetch checks this before saving: when the channel is quiet the feed's
  last entries are older than the retention period, and without the check the
  hourly fetch would re-add what the daily prune had just deleted.
  """
  @spec retained?(%{published_at: DateTime.t()}, DateTime.t()) :: boolean()
  def retained?(%{published_at: published_at}, now \\ DateTime.utc_now()) do
    DateTime.compare(published_at, cutoff(now)) != :lt
  end

  # Truncated: the column holds whole seconds and Ecto refuses microseconds.
  defp cutoff(now), do: now |> DateTime.shift(month: -1) |> DateTime.truncate(:second)

  @doc "The stored video with this YouTube id, or nil."
  @spec get(String.t() | nil) :: Video.t() | nil
  def get(youtube_id) when is_binary(youtube_id), do: Repo.get_by(Video, youtube_id: youtube_id)
  def get(_youtube_id), do: nil

  @doc """
  Videos, newest first, optionally only those matching `query`.

  `query` is plain text split into words. A video matches when every word is
  found in its title, in any order, ignoring case and accents. A word of four
  digits may instead match the year the video was published, since titles
  rarely carry one. Done here rather than in SQL because SQLite's `LIKE` folds
  only ASCII case.

  When searching, each video carries in `match` the parts of its title that
  matched, spelled as the title spells them: the whole query if it appears as
  a phrase, otherwise the matching words in title order, joined by ` … `. Enough
  to confirm why it was returned without giving the rest of the title away. It
  is nil when only a year matched.
  """
  @spec list(String.t() | nil) :: [Video.t()]
  def list(query \\ nil) do
    videos = Repo.all(from(v in Video, order_by: [desc: v.published_at, desc: v.id]))

    case words(query) do
      [] -> videos
      words -> Enum.flat_map(videos, &with_match(&1, words))
    end
  end

  defp words(nil), do: []
  defp words(query), do: query |> String.split() |> Enum.map(&fold/1) |> Enum.reject(&(&1 == []))

  defp with_match(video, words) do
    index = index(video.title)
    found = Enum.map(words, &{&1, find_range(index, &1)})

    if Enum.all?(found, fn {word, range} -> range != nil or year?(word, video) end) do
      ranges = ranges(index, found)

      [%{video | match: match_text(index, ranges), segments: segments(index, ranges)}]
    else
      []
    end
  end

  defp year?(word, video),
    do: word == String.to_charlist(Integer.to_string(video.published_at.year))

  # What to show of the title: the whole query as one phrase if it appears
  # that way ("coppa bernocchi 2026" shows "Coppa Bernocchi", the year having
  # matched elsewhere), otherwise each matched word, merged where they touch.
  defp ranges(index, found) do
    phrase =
      found
      |> Enum.filter(fn {_word, range} -> range != nil end)
      |> Enum.map(fn {word, _range} -> word end)
      |> Enum.intersperse(~c" ")
      |> List.flatten()

    case find_range(index, phrase) do
      nil -> found |> Enum.flat_map(fn {_word, range} -> List.wrap(range) end) |> merge(index)
      range -> [range]
    end
  end

  # Ranges that overlap, or are separated by blanks only, become one:
  # "prix grand" should show "Grand Prix", not two words and a one-character gap.
  defp merge(ranges, %{graphemes: graphemes}) do
    ranges
    |> Enum.sort()
    |> Enum.reduce([], fn
      {first, last}, [{prev_first, prev_last} | rest] = acc ->
        if first <= prev_last + 1 or blank?(graphemes, prev_last + 1, first - 1) do
          [{prev_first, max(last, prev_last)} | rest]
        else
          [{first, last} | acc]
        end

      range, acc ->
        [range | acc]
    end)
    |> Enum.reverse()
  end

  defp blank?(graphemes, from, to) do
    graphemes |> Enum.slice(from..to//1) |> Enum.all?(&(String.trim(&1) == ""))
  end

  defp match_text(_index, []), do: nil

  defp match_text(%{graphemes: graphemes}, ranges) do
    Enum.map_join(ranges, " … ", fn {first, last} ->
      graphemes |> Enum.slice(first..last//1) |> Enum.join()
    end)
  end

  defp segments(_index, []), do: nil

  defp segments(%{graphemes: graphemes}, ranges) do
    total = length(graphemes)

    {parts, position} =
      Enum.reduce(ranges, {[], 0}, fn {first, last}, {parts, position} ->
        parts = if first > position, do: [{:hidden, first - position} | parts], else: parts
        shown = graphemes |> Enum.slice(first..last//1) |> Enum.join()

        {[{:shown, shown} | parts], last + 1}
      end)

    parts = if position < total, do: [{:hidden, total - position} | parts], else: parts

    Enum.reverse(parts)
  end

  # The title is walked grapheme by grapheme so the folded text can be mapped
  # back to the original: folding changes lengths ("é" may be two codepoints),
  # and a match must be cut from the title as written, not from the folded
  # copy. Done once per title, then searched for each word.
  defp index(title) do
    graphemes = String.graphemes(title)

    {folded, owners} =
      graphemes
      |> Enum.with_index()
      |> Enum.flat_map(fn {grapheme, position} ->
        for codepoint <- fold(grapheme, trim: false), do: {codepoint, position}
      end)
      |> Enum.unzip()

    %{graphemes: graphemes, folded: folded, owners: owners}
  end

  # {first, last} grapheme positions of the first occurrence, or nil.
  defp find_range(_index, []), do: nil

  defp find_range(%{folded: folded, owners: owners}, needle) do
    find_prefix(folded, owners, needle, length(needle))
  end

  defp find_prefix([], _owners, _needle, _size), do: nil

  defp find_prefix([_ | rest] = folded, [first | owners_rest] = owners, needle, size) do
    if List.starts_with?(folded, needle) do
      {first, Enum.at(owners, size - 1)}
    else
      find_prefix(rest, owners_rest, needle, size)
    end
  end

  @doc "When a video was last stored, or nil if none ever was."
  @spec fetched_at() :: DateTime.t() | nil
  def fetched_at, do: Repo.one(from(v in Video, select: max(v.updated_at)))

  # Lowercase, accent-free codepoints, so "Bahreïn" and "BAHREIN" compare equal.
  defp fold(text, opts \\ [])
  defp fold(nil, _opts), do: []

  defp fold(text, opts) do
    folded =
      text
      |> :unicode.characters_to_nfd_binary()
      |> String.replace(~r/\p{Mn}/u, "")
      |> String.downcase()

    folded = if Keyword.get(opts, :trim, true), do: String.trim(folded), else: folded

    String.to_charlist(folded)
  end
end

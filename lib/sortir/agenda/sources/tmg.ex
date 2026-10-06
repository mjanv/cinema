defmodule Sortir.Agenda.Sources.Tmg do
  @moduledoc """
  Scraper for the Théâtre Municipal de Grenoble.

  Reads `/45-spectacles.htm`, a single unpaginated page holding the whole
  season: around thirty shows, each with one or more performance dates.

  Dates print as `01.10`, without a year, on a page spanning two calendar years
  ("saison 2026/2027"). Months from August take the first year, months to July
  the second — see `@season_break`. A show with no parseable date is skipped.

  Each show carries tags for both its room and its genre, distinguished by CSS
  class: `o-tag--primary` is the genre, a plain `o-tag` is the room.
  """

  @behaviour Sortir.Agenda.Source

  @base "https://www.theatre-grenoble.fr"
  @listing_path "/45-spectacles.htm"

  @user_agent "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36"

  # A season runs autumn to summer: months from August belong to the first
  # year, months to July to the second.
  @season_break 8

  @impl Sortir.Agenda.Source
  def venue do
    %{
      slug: "tmg-grenoble",
      name: "TMG — Théâtre Municipal de Grenoble",
      city: "Grenoble",
      kind: :theatre,
      url: @base
    }
  end

  @impl Sortir.Agenda.Source
  def fetch(opts \\ []) do
    get = Keyword.get(opts, :get, &get_html/1)

    case get.(@base <> @listing_path) do
      {:ok, html} ->
        # The contract is one entry per occurrence; a show with three dates
        # yields three entries sharing an event.
        scraped =
          html
          |> parse_listing()
          |> Enum.flat_map(fn %{event: event, occurrences: occurrences} ->
            Enum.map(occurrences, &%{event: event, occurrence: &1})
          end)

        {:ok, scraped}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "Shows on the season page, each with all of its performances."
  @spec parse_listing(String.t()) :: [%{event: map(), occurrences: [map()]}]
  def parse_listing(html) when is_binary(html) do
    years = season_years(html)

    ~r/<div class="c-card c-card--vertical">.*?(?=<div class="col-md-4|\z)/s
    |> Regex.scan(html)
    |> Enum.flat_map(fn [card] -> parse_card(card, years) end)
  end

  def parse_listing(_html), do: []

  defp parse_card(card, years) do
    with url when is_binary(url) <- capture(card, ~r|href="(/agenda/\d+/[^"]+)"|),
         raw_title when is_binary(raw_title) <-
           capture(card, ~r/class="c-card__title">\s*<a[^>]*>(.*?)<\/a>/s),
         [_ | _] = occurrences <- parse_dates(card, years) do
      {room, labels} = parse_tags(card)

      [
        %{
          event: %{
            source: "tmg",
            external_id: external_id(url),
            title: clean(raw_title),
            category: category(labels),
            labels: labels,
            image_url: image_url(card),
            url: @base <> url
          },
          occurrences: Enum.map(occurrences, &Map.put(&1, :room, room))
        }
      ]
    else
      _unparseable -> []
    end
  end

  # Each <li class="o-date"> is one performance: "04.11" plus an optional hour.
  defp parse_dates(card, years) do
    ~r/<li class="o-date">.*?(?=<li class="o-date">|<\/ul>)/s
    |> Regex.scan(card)
    |> Enum.flat_map(fn [entry] -> parse_date(entry, years) end)
  end

  defp parse_date(entry, years) do
    with day_month when is_binary(day_month) <-
           capture(entry, ~r|<span aria-hidden="true">(\d{2}\.\d{2})</span>|),
         [day, month] <- String.split(day_month, "."),
         {:ok, date} <- build_date(to_int(day), to_int(month), years),
         {:ok, time} <- parse_time(entry),
         {:ok, starts_at} <- NaiveDateTime.new(date, time) do
      # The venue never publishes an end time.
      [%{starts_at: starts_at, ends_at: nil, status: :unknown}]
    else
      _unparseable -> []
    end
  end

  # A time is optional: some entries are a booking opening, not a performance.
  defp parse_time(entry) do
    case Regex.run(~r|o-date__time.*?(\d{1,2})h(\d{2})|s, entry) do
      [_all, hour, minute] -> Time.new(to_int(hour), to_int(minute), 0)
      nil -> {:ok, ~T[00:00:00]}
    end
  end

  # "saison 2026/2027": months from August are the first year, the rest the
  # second. Without this every spring show lands a year early.
  defp season_years(html) do
    case Regex.run(~r|saison\s*(\d{4})\s*[/-]\s*(\d{2,4})|iu, html) do
      [_all, first, second] ->
        first = String.to_integer(first)
        second = String.to_integer(second)
        {first, if(second < 100, do: div(first, 100) * 100 + second, else: second)}

      nil ->
        year = Date.utc_today().year
        {year, year + 1}
    end
  end

  defp build_date(day, month, {autumn_year, spring_year}) do
    Date.new(if(month >= @season_break, do: autumn_year, else: spring_year), month, day)
  end

  # Tags carry both the room and the category; the CSS class says which is
  # which. `o-tag--primary` is the category, a plain `o-tag` is the room.
  # Reading the class rather than matching known room names keeps rooms the
  # venue adds later from being mistaken for genres.
  defp parse_tags(card) do
    tags =
      ~r|class="(o-tag[^"]*)">([^<]+)</p>|
      |> Regex.scan(card)
      |> Enum.map(fn [_all, class, text] -> {class, clean(text)} end)
      |> Enum.reject(fn {_class, text} -> text == "" end)

    room =
      Enum.find_value(tags, fn {class, text} ->
        if not String.contains?(class, "--primary"), do: text
      end)

    labels =
      for {class, text} <- tags, String.contains?(class, "--primary"), do: text

    {room, labels}
  end

  defp category(labels) do
    text = labels |> Enum.join(" ") |> String.downcase()

    cond do
      String.contains?(text, "projection") -> :screening
      String.contains?(text, "concert") or String.contains?(text, "musique") -> :concert
      String.contains?(text, "conférence") or String.contains?(text, "lecture") -> :talk
      labels != [] -> :performing_arts
      true -> :other
    end
  end

  defp image_url(card) do
    case capture(card, ~r|class="c-card__image[^"]*"\s+src="([^"]+)"|) do
      nil -> nil
      "http" <> _rest = url -> url
      path -> @base <> path
    end
  end

  defp external_id(url), do: capture(url, ~r|/agenda/(\d+)/|)

  defp get_html(url) do
    case Req.get(url,
           headers: [{"user-agent", @user_agent}],
           receive_timeout: 15_000,
           retry: fn _req, response ->
             case response do
               %Req.Response{status: 429} -> false
               %Req.Response{status: status} when status >= 500 -> true
               %Req.Response{} -> false
               _exception -> true
             end
           end,
           max_retries: 1,
           redirect: true
         ) do
      {:ok, %Req.Response{status: 200, body: body}} when is_binary(body) -> {:ok, body}
      {:ok, %Req.Response{status: status}} -> {:error, {:http_status, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp capture(html, regex) do
    case Regex.run(regex, html) do
      [_all, captured] -> captured
      _no_match -> nil
    end
  end

  defp to_int(value) do
    value |> String.trim_leading("0") |> then(&if &1 == "", do: 0, else: String.to_integer(&1))
  end

  defp clean(text) do
    text
    |> String.replace(~r|<[^>]+>|, " ")
    |> decode_entities()
    |> String.replace(~r|[\x{00A0}\s]+|u, " ")
    |> String.trim()
  end

  @entities %{
    "&amp;" => "&",
    "&quot;" => "\"",
    "&#039;" => "'",
    "&apos;" => "'",
    "&nbsp;" => " ",
    "&eacute;" => "é",
    "&egrave;" => "è",
    "&ecirc;" => "ê",
    "&agrave;" => "à",
    "&ccedil;" => "ç",
    "&ndash;" => "–"
  }

  defp decode_entities(text) do
    Enum.reduce(@entities, text, fn {entity, char}, acc ->
      String.replace(acc, entity, char)
    end)
  end
end

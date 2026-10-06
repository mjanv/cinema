defmodule Sortir.Agenda.Sources.Musee do
  @moduledoc """
  Scraper for the Musée de Grenoble's agenda.

  Reads `/1933-agenda.htm`, a paginated list of ~300 dated entries covering
  roughly ten months: guided tours, talks and concerts.

  The listing has one row per *date*, not per event, so a tour running every
  Saturday appears dozens of times. Rows are grouped into events by the numeric
  id in their `/agenda/<id>/` link; the `?periode=` query parameter varies per
  date and is excluded from the identity.

  Pages are `?indicePage=N`, zero-based, ten rows each. The last page omits the
  next-page link, which is the only end-of-list signal; `@max_pages` bounds the
  walk regardless. A page that fails mid-walk ends the scrape and keeps the
  rows already read.
  """

  @behaviour Sortir.Agenda.Source

  @base "https://www.museedegrenoble.fr"
  @listing_path "/1933-agenda.htm"

  @user_agent "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36"

  # The agenda runs to ~32 pages of 10. The cap is a runaway guard, not a
  # limit on the venue: it sits well above the real length so a site that
  # always advertises a next page cannot spin forever.
  @max_pages 40
  @pace_ms 400

  @months ~w(janvier février mars avril mai juin juillet août septembre octobre novembre décembre)

  @impl Sortir.Agenda.Source
  def venue do
    %{
      slug: "musee-de-grenoble",
      name: "Musée de Grenoble",
      city: "Grenoble",
      kind: :museum,
      url: @base
    }
  end

  @impl Sortir.Agenda.Source
  def fetch(opts \\ []) do
    get = Keyword.get(opts, :get, &get_html/1)
    pace_ms = Keyword.get(opts, :pace_ms, @pace_ms)

    case get.(page_url(0)) do
      {:ok, html} ->
        {:ok, follow_pages(html, get, pace_ms, 1, parse_listing(html))}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # A page that fails mid-list costs us its entries, not the whole scrape:
  # what we already read is still worth saving, and the next run fills in.
  defp follow_pages(html, get, pace_ms, page, acc) do
    with true <- page < @max_pages,
         true <- has_next_page?(html),
         _paced <- pace(pace_ms),
         {:ok, next} <- get.(page_url(page)) do
      follow_pages(next, get, pace_ms, page + 1, acc ++ parse_listing(next))
    else
      _done -> acc
    end
  end

  defp has_next_page?(html), do: Regex.match?(~r/indicePage=\d+/, html)

  defp page_url(0), do: @base <> @listing_path
  defp page_url(page), do: "#{@base}#{@listing_path}?indicePage=#{page}"

  defp pace(0), do: :ok
  defp pace(ms), do: Process.sleep(ms)

  @doc "The entries listed on one agenda page, one per date."
  @spec parse_listing(String.t()) :: [%{event: map(), occurrence: map()}]
  def parse_listing(html) when is_binary(html) do
    ~r/<li class="calendar__item">.*?(?=<li class="calendar__item">|<\/ul>)/s
    |> Regex.scan(html)
    |> Enum.flat_map(fn [row] -> parse_row(row) end)
  end

  def parse_listing(_html), do: []

  defp parse_row(row) do
    with url when is_binary(url) <- capture(row, ~r|href="(/agenda/\d+/[^"]+)"|),
         external_id when is_binary(external_id) <- external_id(url),
         raw_title when is_binary(raw_title) <-
           capture(row, ~r/class="calendar__heading">(.*?)<\/h3>/s),
         {:ok, starts_at} <- parse_datetime(row) do
      labels = labels(row)

      [
        %{
          event: %{
            source: "musee_grenoble",
            external_id: external_id,
            title: clean(raw_title),
            category: category(row, labels),
            labels: labels,
            image_url: image_url(row),
            url: @base <> url
          },
          # The museum publishes a start only, and no room: it is all one
          # building.
          occurrence: %{starts_at: starts_at, ends_at: nil, status: :unknown}
        }
      ]
    else
      _unparseable -> []
    end
  end

  # The same tour on ten dates shares one `/agenda/<id>/` path; the trailing
  # `?periode=` differs per date and must not enter the identity, or every
  # date becomes its own event.
  defp external_id(url), do: capture(url, ~r|/agenda/(\d+)/|)

  # "samedi | 01 | août 2026" plus "10h30", each in its own element.
  defp parse_datetime(row) do
    with [_all, day, month_name, year] <-
           Regex.run(
             ~r|dayNumber">(\d+)</div>\s*<div class="calendar__monthYear">\s*(\p{L}+)<br>\s*(\d{4})|us,
             row
           ),
         month when is_integer(month) <- month_number(month_name),
         {:ok, date} <- Date.new(to_int(year), month, to_int(day)),
         {:ok, time} <- parse_time(row) do
      NaiveDateTime.new(date, time)
    else
      _unparseable -> :error
    end
  end

  # Some entries are all-day and print no hour.
  defp parse_time(row) do
    case Regex.run(~r|calendar__hour">\s*(\d{1,2})h(\d{2})?|, row) do
      [_all, hour, ""] -> Time.new(to_int(hour), 0, 0)
      [_all, hour, minute] -> Time.new(to_int(hour), to_int(minute), 0)
      [_all, hour] -> Time.new(to_int(hour), 0, 0)
      nil -> {:ok, ~T[00:00:00]}
    end
  end

  defp month_number(name) do
    name = name |> String.downcase() |> String.trim()

    case Enum.find_index(@months, &(&1 == name)) do
      nil -> nil
      index -> index + 1
    end
  end

  # The museum's own words for the entry, kept verbatim.
  defp labels(row) do
    ~r/class="[^"]*calendarInfo__item[^"]*">([^<]+)</
    |> Regex.scan(row)
    |> Enum.map(fn [_all, text] -> clean(text) end)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  # Ordered: the first keyword found wins, so "visite" beats the "exposition"
  # it is a tour of.
  @keywords [
    {~w(visite), :guided_tour},
    {~w(exposition), :exhibition},
    {~w(concert musique), :concert},
    {~w(conférence lecture rencontre), :talk},
    {~w(projection cinéma), :screening}
  ]

  # The `-thematique` cell says what kind of thing this is.
  defp category(row, labels) do
    text =
      [capture(row, ~r/class="[^"]*-thematique">([^<]*)</) || "" | labels]
      |> Enum.join(" ")
      |> String.downcase()

    Enum.find_value(@keywords, :other, fn {keywords, category} ->
      if Enum.any?(keywords, &String.contains?(text, &1)), do: category
    end)
  end

  defp image_url(row) do
    case capture(row, ~r|<img[^>]+src="([^"]+)"|) do
      nil -> nil
      "http" <> _rest = url -> url
      path -> @base <> path
    end
  end

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

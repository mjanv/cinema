defmodule Sortir.Agenda.Sources.Mc2 do
  @moduledoc """
  Scraper for the MC2, Grenoble's national stage.

  Reads The Events Calendar's REST API rather than the rendered page:

      /wp-json/tribe/events/v1/events?per_page=50&start_date=YYYY-MM-DD

  The response is one entry per *performance*, each with its own numeric `id`,
  so the id cannot identify a production — an eight-night run would become
  eight events. Identity comes from the slug in the event URL
  (`/spectacle/<slug>/<date>/`), which is stable across dates.

  `end_date` is always equal to `start_date` in this feed and says nothing
  about when a show finishes, so it is discarded rather than stored.

  The MC2 also files site announcements under `/spectacle/`, with a start time
  that is really their publication timestamp. They carry no category, while
  every programmed show is billed under at least one, so an entry without a
  category is skipped.

  Pagination follows `next_rest_url`, which the API includes only while more
  pages remain; `@max_pages` bounds the walk regardless. A page that fails
  mid-walk ends the scrape and keeps what was already read.
  """

  @behaviour Sortir.Agenda.Source

  @base "https://www.mc2grenoble.fr"
  @api "#{@base}/wp-json/tribe/events/v1/events"

  @user_agent "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36"

  @per_page 50
  @max_pages 40
  @pace_ms 400

  @impl Sortir.Agenda.Source
  def venue do
    %{
      slug: "mc2-grenoble",
      name: "MC2 — Maison de la Culture de Grenoble",
      city: "Grenoble",
      kind: :theatre,
      url: @base
    }
  end

  @impl Sortir.Agenda.Source
  def fetch(opts \\ []) do
    get = Keyword.get(opts, :get, &get_json/1)
    pace_ms = Keyword.get(opts, :pace_ms, @pace_ms)
    from = Keyword.get(opts, :from, Date.utc_today())

    case get.(first_url(from)) do
      {:ok, body} -> {:ok, follow_pages(body, get, pace_ms, 1, parse_page(body))}
      {:error, reason} -> {:error, reason}
    end
  end

  defp follow_pages(body, get, pace_ms, page, acc) do
    with true <- page < @max_pages,
         next when is_binary(next) <- next_url(body),
         _paced <- pace(pace_ms),
         {:ok, body} <- get.(next) do
      follow_pages(body, get, pace_ms, page + 1, acc ++ parse_page(body))
    else
      _done -> acc
    end
  end

  # The API states its own continuation; absent means this was the last page.
  defp next_url(%{"next_rest_url" => url}) when is_binary(url), do: url
  defp next_url(_last_page), do: nil

  defp first_url(from), do: "#{@api}?per_page=#{@per_page}&start_date=#{Date.to_iso8601(from)}"

  defp pace(0), do: :ok
  defp pace(ms), do: Process.sleep(ms)

  @doc "The performances listed in one API response."
  @spec parse_page(map()) :: [%{event: map(), occurrence: map()}]
  def parse_page(%{"events" => events}) when is_list(events) do
    Enum.flat_map(events, &parse_event/1)
  end

  def parse_page(_unexpected), do: []

  defp parse_event(%{} = event) do
    with url when is_binary(url) <- event["url"],
         slug when is_binary(slug) <- slug(url),
         title when is_binary(title) <- event["title"],
         [_ | _] = categories <- names(event["categories"]),
         {:ok, starts_at} <- parse_naive(event["start_date"]) do
      labels = categories ++ names(event["tags"])

      [
        %{
          event: %{
            source: "mc2",
            external_id: slug,
            title: clean(title),
            category: category(categories),
            labels: labels,
            image_url: image_url(event["image"]),
            url: url
          },
          occurrence: %{
            starts_at: starts_at,
            # `end_date` mirrors `start_date` in this feed; it is not an end.
            ends_at: nil,
            status: :unknown,
            room: room(event["venue"]),
            prices: prices(event["cost_details"])
          }
        }
      ]
    else
      _unparseable -> []
    end
  end

  defp parse_event(_not_a_map), do: []

  # `/spectacle/i-love-you-two/2026-10-02/` — the slug, not the trailing date.
  defp slug(url) do
    case Regex.run(~r{/spectacle/([^/]+)/}, url) do
      [_all, slug] -> slug
      _no_match -> nil
    end
  end

  defp parse_naive(value) when is_binary(value) do
    case NaiveDateTime.from_iso8601(value) do
      {:ok, at} -> {:ok, at}
      {:error, _invalid} -> :error
    end
  end

  defp parse_naive(_missing), do: :error

  # `venue` is a map when set and an empty list when not.
  defp room(%{"venue" => name}) when is_binary(name), do: clean(name)
  defp room(_unset), do: nil

  # Integer cents, ascending, as everywhere else. An unpriced event gets an
  # empty list — never a zero, which would read as "free".
  defp prices(%{"values" => values}) when is_list(values) do
    values
    |> Enum.map(&to_cents/1)
    |> Enum.reject(&(&1 in [nil, 0]))
    |> Enum.sort()
  end

  defp prices(_absent), do: []

  defp to_cents(value) when is_binary(value) do
    case Float.parse(String.replace(value, ",", ".")) do
      {amount, _rest} -> round(amount * 100)
      :error -> nil
    end
  end

  defp to_cents(value) when is_number(value), do: round(value * 100)
  defp to_cents(_unusable), do: nil

  defp names(terms) when is_list(terms) do
    for %{"name" => name} <- terms, is_binary(name), do: clean(name)
  end

  defp names(_absent), do: []

  # Ordered: the first match wins, so a "Danse, Musique" billing reads as
  # dance rather than as a concert.
  @keywords [
    {~w(cirque danse théâtre theatre marionnette), :performing_arts},
    {~w(concert musique opéra), :concert},
    {~w(exposition), :exhibition},
    {~w(cinéma projection), :screening},
    {~w(rencontre conférence lecture atelier), :talk}
  ]

  defp category(categories) do
    text = categories |> Enum.join(" ") |> String.downcase()

    Enum.find_value(@keywords, :other, fn {keywords, category} ->
      if Enum.any?(keywords, &String.contains?(text, &1)), do: category
    end)
  end

  defp image_url(%{"url" => url}) when is_binary(url), do: url
  defp image_url(_absent), do: nil

  defp get_json(url) do
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
      {:ok, %Req.Response{status: 200, body: %{} = body}} -> {:ok, body}
      {:ok, %Req.Response{status: status}} -> {:error, {:http_status, status}}
      {:error, reason} -> {:error, reason}
    end
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
    "&rsquo;" => "'",
    "&laquo;" => "«",
    "&raquo;" => "»",
    "&ndash;" => "–",
    "&hellip;" => "…"
  }

  defp decode_entities(text) do
    @entities
    |> Enum.reduce(text, fn {entity, char}, acc -> String.replace(acc, entity, char) end)
    |> decode_numeric()
  end

  # WordPress emits typographic punctuation as numeric entities — `&#8211;` for
  # an en dash, and any other codepoint it likes. A named-entity table cannot
  # enumerate those, so decode them by their number.
  defp decode_numeric(text) do
    Regex.replace(~r/&#(x?)([0-9a-fA-F]+);/, text, fn whole, hex, digits ->
      base = if hex == "", do: 10, else: 16

      case Integer.parse(digits, base) do
        {code, ""} when code in 0x20..0x10FFFF -> <<code::utf8>>
        _unusable -> whole
      end
    end)
  end
end

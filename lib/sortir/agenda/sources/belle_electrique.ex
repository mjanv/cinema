defmodule Sortir.Agenda.Sources.BelleElectrique do
  @moduledoc """
  Scraper for La Belle Électrique, a music venue in Grenoble.

  Reads in two phases:

    * the listing (`/fr/programmation?from=YYYY-MM`) gives title, dates, room,
      genres, image and a detail link
    * each detail page adds description, price tiers and the ticketing link

  The listing carries several months and links onward; `@max_pages` bounds the
  walk. Requests are spaced by `@pace_ms`.

  A detail page that fails is logged and skipped, leaving the event with its
  listing fields only. An event whose end time falls before its start is
  treated as running past midnight and moved to the next day.
  """

  @behaviour Sortir.Agenda.Source

  alias Sortir.Agenda.Event

  require Logger

  @base "https://www.la-belle-electrique.com"
  @listing_path "/fr/programmation"

  # The venue prefixes a sold-out title rather than marking it in a field.
  @sold_out_prefix ~r/^\s*COMPLET\s*[•·-]\s*/iu

  @user_agent "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36"

  # Between detail-page fetches. A month is a handful of requests, but there is
  # no reason to burst them at a venue that has no obligation to serve us.
  @pace_ms 500

  # A page carries a couple of months; more than this means something is
  # looping, not that the venue programmed three years ahead.
  @max_pages 8

  @impl Sortir.Agenda.Source
  def fetch(opts \\ []) do
    get = Keyword.get(opts, :get, &get_html/1)

    case follow_pages(Keyword.get(opts, :from), get, 1, []) do
      {:ok, scraped} -> {:ok, Enum.map(scraped, &enrich(&1, get))}
      {:error, reason} -> {:error, reason}
    end
  end

  defp follow_pages(_from, _get, page, acc) when page > @max_pages, do: {:ok, acc}

  defp follow_pages(from, get, page, acc) do
    case get.(listing_url(from)) do
      {:ok, html} ->
        acc = acc ++ parse_listing(html)

        case next_page(html) do
          nil -> {:ok, acc}
          next -> follow_pages(next, get, page + 1, acc)
        end

      # A failure part-way through keeps what was already read: a venue that
      # rate limits on page four should not cost the first three.
      {:error, reason} when acc == [] ->
        {:error, reason}

      {:error, reason} ->
        Logger.warning("Belle Électrique: stopped at page #{page}: #{inspect(reason)}")
        {:ok, acc}
    end
  end

  # Phase two: the listing has no description, price or ticket link, so each
  # event's own page is fetched. A failure here costs that event its extras,
  # never the month.
  defp enrich(%{event: event} = scraped, get) do
    Process.sleep(pace_ms())

    case get.(event.url) do
      {:ok, html} ->
        extras = parse_detail(html)

        %{
          scraped
          | event: Map.put(event, :description, extras.description),
            occurrence:
              scraped.occurrence
              |> Map.put(:prices, extras.prices)
              |> Map.put(:ticket_url, extras.ticket_url)
        }

      {:error, reason} ->
        Logger.warning("Belle Électrique: no detail for #{event.external_id}: #{inspect(reason)}")
        scraped
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

  defp pace_ms, do: Application.get_env(:sortir, __MODULE__, [])[:pace_ms] || @pace_ms

  @doc """
  The `from` value of the next page, or nil on the last one.

  The venue paginates by page rather than by month: one page carries a couple
  of months and links onward, so following the link is the only way to know
  where the programme really ends.
  """
  @spec next_page(String.t()) :: Date.t() | nil
  def next_page(html) when is_binary(html) do
    with month when is_binary(month) <- capture(html, ~r|programmation\?from=(\d{4}-\d{2})|),
         [year, month] <- String.split(month, "-"),
         {:ok, date} <- Date.new(String.to_integer(year), String.to_integer(month), 1) do
      date
    else
      _no_next -> nil
    end
  end

  def next_page(_html), do: nil

  @doc "Events on one month's listing page, each with its single occurrence."
  @spec parse_listing(String.t()) :: [%{event: map(), occurrence: map()}]
  def parse_listing(html) when is_binary(html) do
    ~r|<article class="event-card.*?</article>|s
    |> Regex.scan(html)
    |> Enum.flat_map(fn [card] -> parse_card(card) end)
  end

  def parse_listing(_html), do: []

  @doc "The extras only a detail page carries: description, prices, ticketing."
  @spec parse_detail(String.t()) :: %{
          description: String.t() | nil,
          prices: [pos_integer()],
          ticket_url: String.t() | nil
        }
  def parse_detail(html) when is_binary(html) do
    %{
      description: detail_description(html),
      prices: detail_prices(html),
      ticket_url: detail_ticket_url(html)
    }
  end

  def parse_detail(_html), do: %{description: nil, prices: [], ticket_url: nil}

  # --- listing ------------------------------------------------------------

  defp parse_card(card) do
    with url when is_binary(url) <- capture(card, ~r|href="([^"]*/fr/agenda/[^"]+)"|),
         raw_title when is_binary(raw_title) <- capture(card, ~r/<h[23][^>]*>(.*?)<\/h[23]>/s),
         {:ok, starts_at, ends_at} <- parse_dates(card) do
      {title, status} = split_status(clean(raw_title))
      {labels, room} = parse_meta(card)

      [
        %{
          event: %{
            source: "belle_electrique",
            external_id: external_id(url),
            title: title,
            artists: artists(title),
            category: category(labels, room),
            labels: labels,
            image_url: capture(card, ~r|<img[^>]+src="([^"]+)"|),
            url: url
          },
          occurrence: %{
            room: room,
            starts_at: starts_at,
            ends_at: ends_at,
            status: status
          }
        }
      ]
    else
      _unparseable -> []
    end
  end

  # "Du 04.09.26 / 18h au 05.09.26 / 1h" or "09.09.26 / 19h"
  defp parse_dates(card) do
    text =
      card
      |> capture(~r/class="date-(?:xl|m)[^>]*>(.*?)<\/p>/s)
      |> case do
        nil -> ""
        raw -> clean(raw)
      end

    case Regex.run(~r|Du\s+(\S+)\s*/\s*(\S+)\s+au\s+(\S+)\s*/\s*(\S+)|u, text) do
      [_all, from_date, from_time, to_date, to_time] ->
        with {:ok, starts_at} <- to_naive(from_date, from_time),
             {:ok, ends_at} <- to_naive(to_date, to_time) do
          {:ok, starts_at, past_midnight(starts_at, ends_at)}
        end

      nil ->
        parse_single_date(text)
    end
  end

  defp parse_single_date(text) do
    case Regex.run(~r|(\d{2}\.\d{2}\.\d{2})\s*/\s*(\S+)|u, text) do
      [_all, date, time] ->
        with {:ok, starts_at} <- to_naive(date, time), do: {:ok, starts_at, nil}

      nil ->
        :error
    end
  end

  # "04.09.26" + "18h" or "23h55"
  defp to_naive(date, time) do
    with [day, month, year] <- String.split(date, "."),
         [_all, hour, minute] <- run_time(time),
         {:ok, date} <- Date.new(2000 + to_int(year), to_int(month), to_int(day)),
         {:ok, time} <- Time.new(to_int(hour), to_int(minute), 0) do
      NaiveDateTime.new(date, time)
    else
      _unparseable -> :error
    end
  end

  # "Du 05.09.26 / 16h au 05.09.26 / 1h" prints the same date twice, but 1h is
  # the next morning. An end before its start always means the day rolled over.
  defp past_midnight(starts_at, ends_at) do
    if NaiveDateTime.compare(ends_at, starts_at) == :lt do
      NaiveDateTime.add(ends_at, 1, :day)
    else
      ends_at
    end
  end

  # "18h" or "23h55" — the minutes are optional.
  defp run_time(time) do
    case Regex.run(~r/^(\d{1,2})h(\d{2})?$/u, time) do
      [all, hour] -> [all, hour, "0"]
      [all, hour, minute] -> [all, hour, minute]
      _no_match -> nil
    end
  end

  defp to_int(value) do
    value |> String.trim_leading("0") |> then(&if &1 == "", do: 0, else: String.to_integer(&1))
  end

  # The meta block is "genres<br>room", or just "room" when there are none.
  defp parse_meta(card) do
    lines =
      card
      |> capture(~r|class="h4[^>]*>(.*?)</p>|s)
      |> case do
        nil ->
          []

        raw ->
          raw |> String.split(~r|<br\s*/?>|) |> Enum.map(&clean/1) |> Enum.reject(&(&1 == ""))
      end

    case lines do
      [genres, room] -> {split_labels(genres), room}
      [room] -> {[], room}
      _none -> {[], nil}
    end
  end

  defp split_labels(text),
    do: text |> String.split("/") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))

  defp split_status(title) do
    if Regex.match?(@sold_out_prefix, title) do
      {String.replace(title, @sold_out_prefix, "") |> String.trim(), :sold_out}
    else
      {title, :unknown}
    end
  end

  # Best effort. "+" and "b2b" separate artists, but they also separate formats
  # ("Déambulation + projection + concert"), so anything with a format word is
  # left alone: a wrong split reads as data, an empty list reads as unknown.
  @format_words ~w(projection concert déambulation rencontre atelier stand-up soirée)

  defp artists(title) do
    lowered = String.downcase(title)

    if Enum.any?(@format_words, &String.contains?(lowered, &1)) do
      []
    else
      title
      |> String.split(~r|\s*\+\s*|u)
      |> Enum.flat_map(&String.split(&1, ~r|\s+b2b\s+|iu))
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
      |> case do
        [_only_one] -> []
        several -> several
      end
    end
  end

  defp category(labels, room) do
    text = Enum.join(labels ++ [room || ""], " ") |> String.downcase()

    cond do
      String.contains?(text, "nuits") -> :club_night
      String.contains?(text, "concert") -> :concert
      labels != [] -> :concert
      true -> :other
    end
  end

  defp external_id(url), do: url |> String.split("/") |> List.last()

  # --- detail -------------------------------------------------------------

  defp detail_prices(html) do
    html
    |> capture(~r|<p class="mt-2 mb-0 h4">(.*?)</p>|s)
    |> case do
      nil ->
        []

      raw ->
        ~r|(\d+)(?:[.,](\d{1,2}))?\s*€|u
        |> Regex.scan(clean(raw))
        |> Enum.map(fn
          [_all, euros] ->
            String.to_integer(euros) * 100

          [_all, euros, cents] ->
            String.to_integer(euros) * 100 + String.to_integer(String.pad_trailing(cents, 2, "0"))
        end)
        |> Enum.sort()
    end
  end

  defp detail_ticket_url(html), do: capture(html, ~r|href="(https?://billetterie[^"]+)"|)

  # The body copy sits in a "free-text" section, after the practical details.
  defp detail_description(html) do
    case capture(html, ~r|<section class="free-text[^"]*">(.*?)</section>|s) do
      nil -> nil
      raw -> raw |> clean() |> presence()
    end
  end

  defp presence(""), do: nil
  defp presence(text), do: text

  # --- shared -------------------------------------------------------------

  defp capture(html, regex) do
    case Regex.run(regex, html) do
      [_all, captured] -> captured
      _no_match -> nil
    end
  end

  defp clean(text) do
    text
    |> String.replace(~r|<[^>]+>|, " ")
    |> decode_entities()
    # Non-breaking spaces are all over this site's prices and dates.
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
    "&ocirc;" => "ô",
    "&icirc;" => "î",
    "&bull;" => "•"
  }

  defp decode_entities(text) do
    Enum.reduce(@entities, text, fn {entity, char}, acc ->
      String.replace(acc, entity, char)
    end)
  end

  @doc "Where a listing page lives."
  @spec listing_url(Date.t() | nil) :: String.t()
  def listing_url(nil), do: "#{@base}#{@listing_path}"

  def listing_url(%Date{} = from) do
    "#{@base}#{@listing_path}?from=#{from.year}-#{String.pad_leading(to_string(from.month), 2, "0")}"
  end

  @impl Sortir.Agenda.Source
  @doc "The venue this source scrapes."
  @spec venue() :: %{
          slug: String.t(),
          name: String.t(),
          city: String.t(),
          kind: atom(),
          url: String.t()
        }
  def venue do
    %{
      slug: "la-belle-electrique",
      name: "La Belle Électrique",
      city: "Grenoble",
      kind: :music_hall,
      url: @base
    }
  end

  @doc false
  def slug_for(title), do: Event.slug(title)
end

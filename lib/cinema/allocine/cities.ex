defmodule Cinema.Allocine.Cities do
  @moduledoc """
  Scrapes AlloCiné's cinema directory: which cities exist, and which theaters
  each one has.

  HTML rather than JSON — unlike showtimes, AlloCiné exposes no API for this.
  The parsing is deliberately loose (anchors and ids, never CSS structure) so a
  layout change degrades to fewer results instead of an exception.
  """

  alias Cinema.{City, Theater}

  @index_url "https://www.allocine.fr/salle/"
  @city_url "https://www.allocine.fr/salle/cinema"

  @user_agent "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36"

  # Cities change about never; theaters about yearly. Both are cached for a day.
  @ttl :timer.hours(24)

  # How long a failed lookup is remembered before retrying. Long enough to stop
  # a page refresh turning into a request storm, short enough to self-heal.
  @failure_ttl :timer.minutes(5)
  @cache __MODULE__.Cache

  # A city page lists ~15 theaters; more than this many pages means something
  # is looping, not that Paris grew.
  @max_pages 5

  require Logger

  @doc false
  def init_cache, do: Cinema.Store.open(@cache)

  @doc false
  def reset_cache do
    init_cache()
    Cinema.Store.clear(@cache)
  end

  # AlloCiné's own directory, captured. The city list is effectively static, so
  # a rate limit or an outage should degrade to this rather than to an empty
  # app: with no cities there is nothing for the UI to render at all.
  @fallback [
    {"ville-87860", "Aix-en-Provence"},
    {"ville-96943", "Bordeaux"},
    {"ville-85268", "Cannes"},
    {"ville-110514", "Clermont-Ferrand"},
    {"ville-91241", "Dijon"},
    {"ville-98857", "Grenoble"},
    {"ville-114889", "Le Mans"},
    {"ville-107951", "Lille"},
    {"ville-113315", "Lyon"},
    {"ville-87914", "Marseille"},
    {"ville-124868", "Monaco"},
    {"ville-97612", "Montpellier"},
    {"ville-101187", "Nantes"},
    {"ville-85327", "Nice"},
    {"ville-95640", "Nîmes"},
    {"ville-332870", "Papeete"},
    {"ville-115755", "Paris"},
    {"ville-98024", "Rennes"},
    {"ville-112664", "Strasbourg"},
    {"ville-96373", "Toulouse"},
    {"ville-98662", "Tours"}
  ]

  @doc "The built-in city list used when AlloCiné cannot be reached."
  @spec fallback() :: [City.t()]
  def fallback, do: Enum.map(@fallback, fn {id, name} -> City.new(id, name) end)

  @doc "Every city AlloCiné lists, by name."
  @spec list(keyword()) :: [City.t()]
  def list(opts \\ []) do
    fetch = Keyword.get(opts, :fetch, &get_html/1)

    case cached(:index, fn -> fetch_index(fetch) end) do
      [] -> fallback()
      cities -> cities
    end
  end

  defp fetch_index(fetch) do
    case fetch.(@index_url) do
      {:ok, html} -> parse_index(html)
      {:error, _reason} -> []
    end
  end

  @doc "The theaters in one city, following pagination."
  @spec theaters(City.t(), keyword()) :: [Theater.t()]
  def theaters(%City{} = city, opts \\ []) do
    fetch = Keyword.get(opts, :fetch, &get_html/1)

    cached({:theaters, city.external_id}, fn -> collect_theaters(city, fetch, 1, [], nil) end)
  end

  defp collect_theaters(_city, _fetch, page, acc, max) when is_integer(max) and page > max,
    do: dedupe(acc)

  defp collect_theaters(_city, _fetch, page, acc, _max) when page > @max_pages, do: dedupe(acc)

  defp collect_theaters(city, fetch, page, acc, max) do
    case fetch.(city_url(city.external_id, page)) do
      {:ok, html} ->
        found = parse_theaters(html, city.name)
        max = max || max_page(html)
        collect_theaters(city, fetch, page + 1, acc ++ found, max)

      {:error, _reason} ->
        dedupe(acc)
    end
  end

  defp dedupe(theaters) do
    theaters
    |> Enum.uniq_by(& &1.external_id)
    |> Enum.sort_by(& &1.name)
  end

  @doc false
  @spec parse_index(String.t()) :: [City.t()]
  def parse_index(html) when is_binary(html) do
    ~r|/salle/cinema/(ville-\d+)/[^"]*"[^>]*>\s*([^<]{2,60})|
    |> Regex.scan(html)
    |> Enum.map(fn [_all, external_id, name] -> City.new(external_id, clean(name)) end)
    |> Enum.reject(&(&1.name == ""))
    |> Enum.uniq_by(& &1.external_id)
    |> Enum.sort_by(& &1.name)
  end

  def parse_index(_html), do: []

  @doc false
  @spec parse_theaters(String.t(), String.t()) :: [Theater.t()]
  def parse_theaters(html, city_name) when is_binary(html) do
    # Ids are an opaque alphanumeric code (P0071, W7461, G0699, G06DB). Match
    # the shape rather than a list of prefixes: anchoring on [PW]\d+ silently
    # dropped Véo Cartoucherie from Toulouse.
    ~r|salle_gen_csalle=([A-Z0-9]+)\.html"[^>]*>\s*([^<]{2,80})|
    |> Regex.scan(html)
    |> Enum.map(fn [_all, id, name] ->
      %Theater{external_id: id, name: clean(name), city: city_name}
    end)
    |> Enum.reject(&(&1.name == ""))
    |> Enum.uniq_by(& &1.external_id)
  end

  def parse_theaters(_html, _city_name), do: []

  @doc false
  @spec max_page(String.t()) :: pos_integer()
  def max_page(html) when is_binary(html) do
    ~r|/salle/cinema/ville-\d+/\?page=(\d+)|
    |> Regex.scan(html)
    |> Enum.map(fn [_all, page] -> String.to_integer(page) end)
    |> case do
      [] -> 1
      pages -> pages |> Enum.max() |> min(@max_pages)
    end
  end

  def max_page(_html), do: 1

  # Named entities that actually occur in AlloCiné's theater and city names.
  # Numeric ones are handled generically below; a full entity library would be
  # a dependency for five cases.
  @entities %{
    "&amp;" => "&",
    "&quot;" => "\"",
    "&apos;" => "'",
    "&nbsp;" => " ",
    "&eacute;" => "é",
    "&egrave;" => "è",
    "&ecirc;" => "ê",
    "&agrave;" => "à",
    "&acirc;" => "â",
    "&ccedil;" => "ç",
    "&ocirc;" => "ô",
    "&icirc;" => "î",
    "&ucirc;" => "û",
    "&ugrave;" => "ù",
    "&iuml;" => "ï",
    "&ouml;" => "ö"
  }

  defp clean(text) do
    text
    |> decode_entities()
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  defp decode_entities(text) do
    text
    |> then(
      &Enum.reduce(@entities, &1, fn {entity, char}, acc ->
        String.replace(acc, entity, char)
      end)
    )
    |> String.replace(~r/&#(\d+);/, fn match ->
      case Regex.run(~r/\d+/, match) do
        [digits] -> digits |> String.to_integer() |> List.wrap() |> List.to_string()
        _no_match -> match
      end
    end)
  end

  defp city_url(slug, 1), do: "#{@city_url}/#{slug}/"
  defp city_url(slug, page), do: "#{@city_url}/#{slug}/?page=#{page}"

  defp cached(key, fun) do
    case Cinema.Store.fetch(@cache, key, @ttl) do
      {:ok, value} -> value
      :miss -> store(key, fun.())
    end
  end

  # An empty result means the fetch failed. Remember it briefly anyway: retrying
  # on every page load is what earns a 429 in the first place. Backdating the
  # entry gives it the shorter failure TTL without a second timestamp field.
  defp store(key, []) do
    Cinema.Store.put(@cache, key, [],
      stored_at: System.os_time(:millisecond) - @ttl + @failure_ttl
    )

    []
  end

  defp store(key, value) do
    Cinema.Store.put(@cache, key, value)
    value
  end

  defp get_html(url) do
    case Req.get(url,
           headers: [{"user-agent", @user_agent}],
           receive_timeout: 15_000,
           # Do not retry a 429: retrying a rate limit is what deepens it. The
           # fallback list and the failure cache cover us instead.
           retry: fn _req, resp_or_err ->
             case resp_or_err do
               %Req.Response{status: 429} -> false
               %Req.Response{status: status} when status >= 500 -> true
               %Req.Response{} -> false
               _exception -> true
             end
           end,
           max_retries: 1,
           redirect: true
         ) do
      {:ok, %Req.Response{status: 200, body: body}} when is_binary(body) ->
        {:ok, body}

      {:ok, %Req.Response{status: status}} ->
        Logger.warning("AlloCiné returned HTTP #{status} for #{url}")
        {:error, {:http_status, status}}

      {:error, reason} ->
        Logger.warning("AlloCiné request failed for #{url}: #{inspect(reason)}")
        {:error, reason}
    end
  end
end

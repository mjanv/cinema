defmodule Cinema.Allocine do
  @moduledoc """
  `Cinema.Source` backed by AlloCiné's internal showtimes endpoint:

      /_/showtimes/theater-{id}/d-{YYYY-MM-DD}/p-{page}/

  This endpoint is undocumented and may change without notice, which is why
  parsing is isolated in `Cinema.Allocine.Parser` and covered by tests against
  captured responses.
  """

  @behaviour Cinema.Source

  alias Cinema.Allocine.{Cities, Parser}
  alias Cinema.Theater

  require Logger

  @base "https://www.allocine.fr/_/showtimes"

  # AlloCiné rejects requests without a browser-like User-Agent.
  @user_agent "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36"

  # Guards against a pagination bug turning into an unbounded request loop.
  @max_pages 10

  @impl Cinema.Source
  def cities, do: Cities.list()

  @impl Cinema.Source
  def theaters(%Cinema.City{} = city), do: Cities.theaters(city)

  @impl Cinema.Source
  def fetch_day(theater, date), do: fetch_day(theater, date, [])

  @spec fetch_day(Theater.t(), Date.t(), keyword()) ::
          {:ok, [Cinema.Screening.t()]} | {:error, term()}
  def fetch_day(%Theater{} = theater, %Date{} = date, opts) do
    fetch = Keyword.get(opts, :fetch, &get_json/1)
    collect_pages(theater, date, fetch, 1, [])
  end

  defp collect_pages(theater, date, fetch, page, acc) when page <= @max_pages do
    case fetch.(url(theater.external_id, date, page)) do
      {:ok, body} ->
        screenings =
          body
          |> Parser.parse(theater.external_id)
          |> Enum.map(&%{&1 | theater_name: theater.name})

        acc = acc ++ screenings

        if page < total_pages(body) do
          collect_pages(theater, date, fetch, page + 1, acc)
        else
          {:ok, acc}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp collect_pages(_theater, _date, _fetch, _page, acc), do: {:ok, acc}

  defp total_pages(%{"pagination" => %{"totalPages" => total}}) when is_integer(total), do: total
  defp total_pages(_body), do: 1

  defp url(theater_id, date, page) do
    base = "#{@base}/theater-#{theater_id}/d-#{Date.to_iso8601(date)}/"
    if page > 1, do: base <> "p-#{page}/", else: base
  end

  defp get_json(url) do
    case Req.get(url,
           headers: [{"user-agent", @user_agent}, {"accept", "application/json"}],
           receive_timeout: 15_000,
           # Never retry a 429: retrying a rate limit deepens it, and Paris
           # alone is 75 theaters x 7 days. Transport errors and 5xx still get
           # one retry.
           retry: fn _req, resp_or_err ->
             case resp_or_err do
               %Req.Response{status: 429} -> false
               %Req.Response{status: status} when status >= 500 -> true
               %Req.Response{} -> false
               _exception -> true
             end
           end,
           max_retries: 1
         ) do
      {:ok, %Req.Response{status: 200, body: body}} when is_map(body) ->
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

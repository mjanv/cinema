defmodule Cinema.Allocine.Parser do
  @moduledoc """
  Turns an AlloCiné showtimes payload into a flat list of `Cinema.Screening`.

  Pure: no network. Every field AlloCiné may omit is treated as optional, so a
  missing poster or booking link degrades the row instead of failing the page.
  """

  alias Cinema.Screening

  @spec parse(map(), String.t()) :: [Screening.t()]
  def parse(%{"results" => results}, theater_id) when is_list(results) do
    Enum.flat_map(results, &screenings_for_movie(&1, theater_id))
  end

  def parse(_payload, _theater_id), do: []

  defp screenings_for_movie(%{"movie" => movie, "showtimes" => showtimes}, theater_id) do
    showtimes
    |> Enum.flat_map(fn
      {_bucket, list} when is_list(list) -> list
      {_bucket, _other} -> []
    end)
    |> Enum.flat_map(&build(&1, movie, theater_id))
  end

  defp screenings_for_movie(_result, _theater_id), do: []

  defp build(%{"startsAt" => starts_at} = showtime, movie, theater_id)
       when is_binary(starts_at) do
    case NaiveDateTime.from_iso8601(starts_at) do
      {:ok, naive} ->
        [
          %Screening{
            theater_id: theater_id,
            title: title(movie),
            original_title: movie["originalTitle"],
            runtime_min: runtime_min(movie["runtime"]),
            genres: genres(movie["genres"]),
            poster_url: poster_url(get_in(movie, ["poster", "url"])),
            starts_at: naive,
            date: NaiveDateTime.to_date(naive),
            version: version(showtime["diffusionVersion"]),
            booking_url: booking_url(showtime)
          }
        ]

      {:error, _reason} ->
        []
    end
  end

  defp build(_showtime, _movie, _theater_id), do: []

  defp title(%{"title" => title}) when is_binary(title) and title != "", do: title
  defp title(%{"originalTitle" => title}) when is_binary(title) and title != "", do: title
  defp title(_movie), do: "Titre inconnu"

  # LOCAL is a French film shown in French: a viewer reads that as VF.
  defp version("ORIGINAL"), do: :vost
  defp version(_other), do: :vf

  # AlloCiné ships runtime as a human string like "1h 47min".
  defp runtime_min(runtime) when is_binary(runtime) do
    hours = capture_int(runtime, ~r/(\d+)\s*h/)
    minutes = capture_int(runtime, ~r/(\d+)\s*min/)

    case hours * 60 + minutes do
      0 -> nil
      total -> total
    end
  end

  defp runtime_min(_runtime), do: nil

  defp capture_int(string, regex) do
    case Regex.run(regex, string) do
      [_full, value] -> String.to_integer(value)
      _no_match -> 0
    end
  end

  # AlloCiné serves ~260 KB originals; the CDN resizes via a path segment. At
  # ~8 KB this is still tiny, and 180px wide keeps the 80px render sharp on a
  # retina phone.
  @poster_size "c_180_240"

  # Paths vary (/img/..., /pictures/...); the size segment goes right after the
  # host in every case. Anything unexpected falls through to the original URL.
  defp poster_url("https://" <> rest = url) do
    case String.split(rest, "/", parts: 2) do
      [host, path] when path != "" -> "https://#{host}/#{@poster_size}/#{path}"
      _unexpected -> url
    end
  end

  defp poster_url(_url), do: nil

  defp genres(genres) when is_list(genres) do
    Enum.flat_map(genres, fn
      %{"translate" => name} when is_binary(name) -> [name]
      _other -> []
    end)
  end

  defp genres(_genres), do: []

  defp booking_url(%{"data" => %{"ticketing" => [%{"urls" => [url | _rest]} | _more]}})
       when is_binary(url),
       do: url

  defp booking_url(_showtime), do: nil
end

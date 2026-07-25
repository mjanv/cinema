defmodule Cinema.AllocineTest do
  use ExUnit.Case, async: true

  alias Cinema.{Allocine, Theater}

  @theater %Theater{external_id: "P0070", name: "Le Méliès", city: "Grenoble"}

  test "fetches and parses a day into screenings" do
    body = Cinema.Fixtures.load!("theater_P0070_2026-07-26")

    fetch = fn url ->
      assert url == "https://www.allocine.fr/_/showtimes/theater-P0070/d-2026-07-26/"
      {:ok, body}
    end

    assert {:ok, [_ | _] = screenings} =
             Allocine.fetch_day(@theater, ~D[2026-07-26], fetch: fetch)

    assert Enum.all?(screenings, &(&1.theater_name == "Le Méliès"))
    assert Enum.all?(screenings, &(&1.date == ~D[2026-07-26]))
  end

  test "follows pagination until the last page" do
    page = fn n, total ->
      %{
        "pagination" => %{"page" => n, "totalPages" => total},
        "results" => [
          %{
            "movie" => %{"title" => "Film page #{n}"},
            "showtimes" => %{
              "multiple" => [
                %{"startsAt" => "2026-07-26T1#{n}:00:00", "diffusionVersion" => "DUBBED"}
              ]
            }
          }
        ]
      }
    end

    fetch = fn
      "https://www.allocine.fr/_/showtimes/theater-P0070/d-2026-07-26/" -> {:ok, page.(1, 3)}
      "https://www.allocine.fr/_/showtimes/theater-P0070/d-2026-07-26/p-2/" -> {:ok, page.(2, 3)}
      "https://www.allocine.fr/_/showtimes/theater-P0070/d-2026-07-26/p-3/" -> {:ok, page.(3, 3)}
    end

    assert {:ok, screenings} = Allocine.fetch_day(@theater, ~D[2026-07-26], fetch: fetch)

    assert Enum.map(screenings, & &1.title) == [
             "Film page 1",
             "Film page 2",
             "Film page 3"
           ]
  end

  test "propagates transport failures instead of raising" do
    fetch = fn _url -> {:error, :timeout} end

    assert {:error, :timeout} = Allocine.fetch_day(@theater, ~D[2026-07-26], fetch: fetch)
  end
end

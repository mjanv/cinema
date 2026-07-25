defmodule Cinema.Allocine.ParserTest do
  use ExUnit.Case, async: true

  alias Cinema.Allocine.Parser

  test "extracts screenings with title, start time and theater from a real response" do
    screenings =
      Cinema.Fixtures.load!("theater_P0070_2026-07-26")
      |> Parser.parse("P0070")

    assert [screening | _] = screenings
    assert screening.theater_id == "P0070"
    assert is_binary(screening.title) and screening.title != ""
    assert %NaiveDateTime{} = screening.starts_at
    assert screening.date == ~D[2026-07-26]
  end

  test "maps subtitled originals to :vost and everything else to :vf" do
    screenings =
      Cinema.Fixtures.load!("theater_P1032_2026-07-26")
      |> Parser.parse("P1032")

    versions = screenings |> Enum.map(& &1.version) |> Enum.uniq() |> Enum.sort()
    assert versions == [:vf, :vost]
  end

  test "requests a thumbnail-sized poster from the CDN rather than the full-size original" do
    screenings =
      Cinema.Fixtures.load!("theater_P1032_2026-07-26")
      |> Parser.parse("P1032")

    posters = screenings |> Enum.map(& &1.poster_url) |> Enum.reject(&is_nil/1) |> Enum.uniq()

    assert posters != []
    assert Enum.all?(posters, &String.contains?(&1, "/c_180_240/"))
    assert Enum.all?(posters, &String.starts_with?(&1, "https://"))
  end

  test "resizes both poster URL shapes AlloCiné serves" do
    for {original, expected} <- [
          {"https://fr.web.img2.acsta.net/img/ba/a6/abc.jpg",
           "https://fr.web.img2.acsta.net/c_180_240/img/ba/a6/abc.jpg"},
          {"https://fr.web.img5.acsta.net/pictures/17/10/23/09/41/4746507.jpg",
           "https://fr.web.img5.acsta.net/c_180_240/pictures/17/10/23/09/41/4746507.jpg"}
        ] do
      payload = %{
        "results" => [
          %{
            "movie" => %{"title" => "Film", "poster" => %{"url" => original}},
            "showtimes" => %{
              "multiple" => [
                %{"startsAt" => "2026-07-26T20:30:00", "diffusionVersion" => "DUBBED"}
              ]
            }
          }
        ]
      }

      assert [%{poster_url: ^expected}] = Parser.parse(payload, "P0070")
    end
  end

  test "leaves a missing poster as nil instead of building a broken URL" do
    payload = %{
      "results" => [
        %{
          "movie" => %{"title" => "Sans affiche", "poster" => nil},
          "showtimes" => %{
            "multiple" => [%{"startsAt" => "2026-07-26T20:30:00", "diffusionVersion" => "DUBBED"}]
          }
        }
      ]
    }

    assert [screening] = Parser.parse(payload, "P0070")
    assert screening.poster_url == nil
  end

  test "returns an empty list for a theater with no programming" do
    assert Cinema.Fixtures.load!("theater_P0758_empty") |> Parser.parse("P0758") == []
  end

  test "returns an empty list rather than raising on an unexpected payload" do
    assert Parser.parse(%{}, "P0070") == []
    assert Parser.parse(%{"results" => nil}, "P0070") == []
    assert Parser.parse(%{"results" => [%{"movie" => %{}, "showtimes" => %{}}]}, "P0070") == []
  end

  test "keeps a screening whose optional fields are missing" do
    payload = %{
      "results" => [
        %{
          "movie" => %{"title" => "Film sans métadonnées"},
          "showtimes" => %{
            "multiple" => [%{"startsAt" => "2026-07-26T20:30:00", "diffusionVersion" => "DUBBED"}]
          }
        }
      ]
    }

    assert [screening] = Parser.parse(payload, "P0070")
    assert screening.title == "Film sans métadonnées"
    assert screening.starts_at == ~N[2026-07-26 20:30:00]
    assert screening.version == :vf
    assert screening.poster_url == nil
    assert screening.runtime_min == nil
    assert screening.booking_url == nil
    assert screening.genres == []
  end
end

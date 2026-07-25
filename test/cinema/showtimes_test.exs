defmodule Cinema.ShowtimesTest do
  # The cache tests share one ETS table, so this module cannot run concurrently.
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox

  alias Cinema.{Screening, Showtimes, Theater}

  defp screening(theater_id, theater_name, title, starts_at, version \\ :vf) do
    naive = NaiveDateTime.from_iso8601!(starts_at)

    %Screening{
      theater_id: theater_id,
      theater_name: theater_name,
      title: title,
      starts_at: naive,
      date: NaiveDateTime.to_date(naive),
      version: version
    }
  end

  defp source(screenings_by_theater) do
    theaters =
      for {id, name} <- [{"T1", "Cinéma Un"}, {"T2", "Cinéma Deux"}],
          do: %Theater{external_id: id, name: name, city: "Grenoble"}

    fetch = fn %Theater{external_id: id}, date ->
      case Map.fetch(screenings_by_theater, {id, date}) do
        {:ok, {:error, reason}} -> {:error, reason}
        {:ok, screenings} -> {:ok, screenings}
        :error -> {:ok, []}
      end
    end

    {theaters, fetch}
  end

  test "groups screenings by date, then theater, sorted chronologically" do
    {theaters, fetch} =
      source(%{
        {"T1", ~D[2026-07-26]} => [
          screening("T1", "Cinéma Un", "Tardif", "2026-07-26T21:00:00"),
          screening("T1", "Cinéma Un", "Matinal", "2026-07-26T11:00:00")
        ],
        {"T2", ~D[2026-07-26]} => [
          screening("T2", "Cinéma Deux", "Autre", "2026-07-26T18:00:00")
        ]
      })

    assert [day] = Showtimes.build(theaters, fetch, ~D[2026-07-26], 1)

    assert day.date == ~D[2026-07-26]
    assert Enum.map(day.theaters, & &1.name) == ["Cinéma Un", "Cinéma Deux"]

    [first_theater | _] = day.theaters
    assert Enum.map(first_theater.movies, & &1.title) == ["Matinal", "Tardif"]
  end

  test "groups repeated showings of one movie under a single entry" do
    {theaters, fetch} =
      source(%{
        {"T1", ~D[2026-07-26]} => [
          screening("T1", "Cinéma Un", "Toy Story 5", "2026-07-26T14:00:00"),
          screening("T1", "Cinéma Un", "Toy Story 5", "2026-07-26T16:30:00"),
          screening("T1", "Cinéma Un", "Toy Story 5", "2026-07-26T20:00:00", :vost)
        ]
      })

    assert [day] = Showtimes.build(theaters, fetch, ~D[2026-07-26], 1)
    assert [theater] = day.theaters
    assert [movie] = theater.movies

    assert movie.title == "Toy Story 5"

    assert Enum.map(movie.screenings, &NaiveDateTime.to_time(&1.starts_at)) ==
             [~T[14:00:00], ~T[16:30:00], ~T[20:00:00]]
  end

  test "covers the requested number of days starting from the given date" do
    {theaters, fetch} = source(%{})

    days = Showtimes.build(theaters, fetch, ~D[2026-07-26], 3)

    assert Enum.map(days, & &1.date) == [~D[2026-07-26], ~D[2026-07-27], ~D[2026-07-28]]
  end

  test "omits theaters with no programming for a day" do
    {theaters, fetch} =
      source(%{
        {"T1", ~D[2026-07-26]} => [screening("T1", "Cinéma Un", "Film", "2026-07-26T14:00:00")]
      })

    assert [day] = Showtimes.build(theaters, fetch, ~D[2026-07-26], 1)
    assert Enum.map(day.theaters, & &1.name) == ["Cinéma Un"]
  end

  describe "today/1" do
    test "uses the local Grenoble date when it differs from UTC" do
      # 00:30 in Paris (summer) is still 22:30 UTC the previous day. Reading UTC
      # would roll the board over early and hide the late showings.
      just_after_midnight = ~U[2026-07-26 22:30:00Z]

      assert Showtimes.today(just_after_midnight) == ~D[2026-07-27]
      assert DateTime.to_date(just_after_midnight) == ~D[2026-07-26]
    end

    test "agrees with UTC during the rest of the day" do
      afternoon = ~U[2026-07-26 12:00:00Z]

      assert Showtimes.today(afternoon) == ~D[2026-07-26]
    end
  end

  describe "opening_date/2" do
    defp day_with(date, times) do
      screenings = Enum.map(times, &screening("T1", "Cinéma Un", "Film", "#{date}T#{&1}"))

      %{
        date: Date.from_iso8601!(date),
        theaters: [
          %{
            id: "T1",
            name: "Cinéma Un",
            movies: [
              %{
                title: "Film",
                original_title: nil,
                runtime_min: nil,
                genres: [],
                poster_url: nil,
                versions: [:vf],
                screenings: screenings
              }
            ]
          }
        ]
      }
    end

    test "stays on today while a screening is still to come" do
      days = [day_with("2026-07-26", ["14:00:00", "21:00:00"])]

      assert Showtimes.opening_date(days, ~N[2026-07-26 20:00:00]) == ~D[2026-07-26]
    end

    test "stays on today during the 30 minutes after the last screening started" do
      days = [day_with("2026-07-26", ["21:00:00"])]

      # A film that started 29 minutes ago is still worth showing: you may be in it.
      assert Showtimes.opening_date(days, ~N[2026-07-26 21:29:00]) == ~D[2026-07-26]
    end

    test "moves to tomorrow once the last screening is more than 30 minutes gone" do
      days = [day_with("2026-07-26", ["21:00:00"]), day_with("2026-07-27", ["14:00:00"])]

      assert Showtimes.opening_date(days, ~N[2026-07-26 21:31:00]) == ~D[2026-07-27]
    end

    test "stays on today when there is no tomorrow to move to" do
      days = [day_with("2026-07-26", ["21:00:00"])]

      assert Showtimes.opening_date(days, ~N[2026-07-27 09:00:00]) == ~D[2026-07-26]
    end

    test "skips an empty today and lands on the next day that has screenings" do
      days = [
        %{date: ~D[2026-07-26], theaters: []},
        day_with("2026-07-27", ["14:00:00"])
      ]

      assert Showtimes.opening_date(days, ~N[2026-07-26 10:00:00]) == ~D[2026-07-27]
    end

    test "falls back to the first day when nothing is programmed at all" do
      days = [%{date: ~D[2026-07-26], theaters: []}]

      assert Showtimes.opening_date(days, ~N[2026-07-26 10:00:00]) == ~D[2026-07-26]
    end

    test "returns nil for an empty schedule" do
      assert Showtimes.opening_date([], ~N[2026-07-26 10:00:00]) == nil
    end
  end

  describe "film/2" do
    defp day_for(date, entries) do
      %{
        date: Date.from_iso8601!(date),
        theaters:
          for {theater_id, name, title, times} <- entries do
            %{
              id: theater_id,
              name: name,
              movies: [
                %{
                  title: title,
                  original_title: nil,
                  runtime_min: 120,
                  genres: ["Drame"],
                  poster_url: "p.jpg",
                  versions: [:vf],
                  screenings:
                    Enum.map(times, &screening(theater_id, name, title, "#{date}T#{&1}"))
                }
              ]
            }
          end
      }
    end

    test "collects one film's screenings across every day, keeping days in order" do
      days = [
        day_for("2026-07-26", [{"T1", "Cinéma Un", "L'Odyssée", ["14:00:00", "20:00:00"]}]),
        day_for("2026-07-27", [{"T2", "Cinéma Deux", "L'Odyssée", ["18:00:00"]}])
      ]

      assert %{} = film = Showtimes.film(days, "L'Odyssée")

      assert film.title == "L'Odyssée"
      assert film.runtime_min == 120
      assert film.genres == ["Drame"]
      assert Enum.map(film.days, & &1.date) == [~D[2026-07-26], ~D[2026-07-27]]
    end

    test "groups each day's screenings by cinema" do
      days = [
        day_for("2026-07-26", [
          {"T1", "Cinéma Un", "L'Odyssée", ["14:00:00"]},
          {"T2", "Cinéma Deux", "L'Odyssée", ["20:00:00"]}
        ])
      ]

      assert %{days: [day]} = Showtimes.film(days, "L'Odyssée")
      assert Enum.map(day.theaters, & &1.name) == ["Cinéma Un", "Cinéma Deux"]
    end

    test "omits days on which the film is not showing" do
      days = [
        day_for("2026-07-26", [{"T1", "Cinéma Un", "L'Odyssée", ["14:00:00"]}]),
        day_for("2026-07-27", [{"T1", "Cinéma Un", "Autre film", ["18:00:00"]}])
      ]

      assert %{days: [only]} = Showtimes.film(days, "L'Odyssée")
      assert only.date == ~D[2026-07-26]
    end

    test "returns nil for a film that is not in the schedule at all" do
      days = [day_for("2026-07-26", [{"T1", "Cinéma Un", "L'Odyssée", ["14:00:00"]}])]

      assert Showtimes.film(days, "Film inexistant") == nil
      assert Showtimes.film([], "L'Odyssée") == nil
    end
  end

  describe "horizon/2" do
    test "keeps the full horizon for a normal city" do
      assert Showtimes.horizon(5, 7) == 7
      assert Showtimes.horizon(16, 7) == 7
    end

    test "trims the horizon for a city with many theaters" do
      # Paris is 75 theaters: at 7 days that is 525 requests in one burst, which
      # trips AlloCiné's rate limit and 429s every other city with it.
      assert Showtimes.horizon(75, 7) == 3
    end

    test "never extends a horizon that is already short" do
      assert Showtimes.horizon(75, 1) == 1
    end
  end

  describe "cache" do
    setup do
      # The cache is in SQLite now, so these need a checked-out connection.
      pid = Sandbox.start_owner!(Cinema.Repo, shared: true)
      on_exit(fn -> Sandbox.stop_owner(pid) end)
      Cinema.Showtimes.reset_cache()
      :ok
    end

    test "keeps serving the last good schedule when every source is down" do
      defmodule WorkingSource do
        @behaviour Cinema.Source
        @impl true
        def cities, do: [Cinema.City.new("ville-98857", "Grenoble")]
        @impl true
        def theaters(_city), do: [%Cinema.Theater{external_id: "T1", name: "Cinéma Un"}]
        @impl true
        def fetch_day(_theater, date) do
          {:ok,
           [
             %Cinema.Screening{
               theater_id: "T1",
               theater_name: "Cinéma Un",
               title: "Film",
               starts_at: NaiveDateTime.new!(date, ~T[20:00:00]),
               date: date,
               version: :vf
             }
           ]}
        end
      end

      defmodule DeadSource do
        @behaviour Cinema.Source
        @impl true
        def cities, do: [Cinema.City.new("ville-98857", "Grenoble")]
        @impl true
        def theaters(_city), do: [%Cinema.Theater{external_id: "T1", name: "Cinéma Un"}]
        @impl true
        def fetch_day(_theater, _date), do: {:error, :econnrefused}
      end

      put_source(WorkingSource)
      city = Cinema.City.new("ville-98857", "Grenoble")
      Cinema.Showtimes.list_days(city, days: 1, refresh: true)
      Oban.drain_queue(queue: :allocine)
      good = Cinema.Showtimes.list_days(city, days: 1, refresh: true)
      assert [%{theaters: [_ | _]}] = good

      put_source(DeadSource)
      Oban.drain_queue(queue: :allocine)
      during_outage = Cinema.Showtimes.list_days(city, days: 1, refresh: true)

      assert during_outage == good, "an outage must not blank the board"
    end

    test "reports a fresh schedule as not stale" do
      defmodule LiveSource do
        @behaviour Cinema.Source
        @impl true
        def cities, do: [Cinema.City.new("ville-98857", "Grenoble")]
        @impl true
        def theaters(_city), do: [%Cinema.Theater{external_id: "T1", name: "Cinéma Un"}]
        @impl true
        def fetch_day(_theater, date) do
          {:ok,
           [
             %Cinema.Screening{
               theater_id: "T1",
               theater_name: "Cinéma Un",
               title: "Film",
               starts_at: NaiveDateTime.new!(date, ~T[20:00:00]),
               date: date,
               version: :vf
             }
           ]}
        end
      end

      put_source(LiveSource)
      city = Cinema.City.new("ville-98857", "Grenoble")
      Cinema.Showtimes.list_days(city, days: 1, refresh: true)

      status = Cinema.Showtimes.status(city)
      refute status.stale?
      assert %DateTime{} = status.fetched_at
    end
  end

  defp put_source(module) do
    previous = Application.get_env(:cinema, Cinema.Showtimes, [])
    Application.put_env(:cinema, Cinema.Showtimes, Keyword.put(previous, :source, module))
    on_exit(fn -> Application.put_env(:cinema, Cinema.Showtimes, previous) end)
  end

  test "regroups a day by movie, listing every cinema showing it" do
    day = %{
      date: ~D[2026-07-26],
      theaters: [
        %{
          id: "T1",
          name: "Cinéma Un",
          movies: [
            %{
              title: "L'Odyssée",
              original_title: nil,
              runtime_min: 120,
              genres: [],
              poster_url: "poster.jpg",
              versions: [:vf],
              screenings: [screening("T1", "Cinéma Un", "L'Odyssée", "2026-07-26T20:00:00")]
            }
          ]
        },
        %{
          id: "T2",
          name: "Cinéma Deux",
          movies: [
            %{
              title: "L'Odyssée",
              original_title: nil,
              runtime_min: 120,
              genres: [],
              poster_url: nil,
              versions: [:vost],
              screenings: [
                screening("T2", "Cinéma Deux", "L'Odyssée", "2026-07-26T18:00:00", :vost)
              ]
            },
            %{
              title: "Autre film",
              original_title: nil,
              runtime_min: 90,
              genres: [],
              poster_url: nil,
              versions: [:vf],
              screenings: [screening("T2", "Cinéma Deux", "Autre film", "2026-07-26T14:00:00")]
            }
          ]
        }
      ]
    }

    assert [autre, odyssee] = Showtimes.by_movie(day)

    # Earliest screening first, so the day still reads chronologically.
    assert autre.title == "Autre film"
    assert odyssee.title == "L'Odyssée"

    assert Enum.map(odyssee.theaters, & &1.name) == ["Cinéma Deux", "Cinéma Un"]
    assert odyssee.versions == [:vf, :vost]
    # A poster from any cinema showing it is good enough.
    assert odyssee.poster_url == "poster.jpg"
  end

  test "keeps working when one theater fails to respond" do
    {theaters, fetch} =
      source(%{
        {"T1", ~D[2026-07-26]} => {:error, :timeout},
        {"T2", ~D[2026-07-26]} => [
          screening("T2", "Cinéma Deux", "Survivant", "2026-07-26T18:00:00")
        ]
      })

    assert [day] = Showtimes.build(theaters, fetch, ~D[2026-07-26], 1)
    assert Enum.map(day.theaters, & &1.name) == ["Cinéma Deux"]
  end
end

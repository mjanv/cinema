defmodule Cinema.StubSource do
  @moduledoc """
  Deterministic `Cinema.Source` for tests, so nothing hits AlloCiné.
  """

  @behaviour Cinema.Source

  alias Cinema.{City, Screening, Theater}

  @theater %Theater{external_id: "T1", name: "Cinéma Test", city: "Grenoble"}

  @cities [
    City.new("ville-98857", "Grenoble"),
    City.new("ville-113315", "Lyon")
  ]

  @impl Cinema.Source
  def cities, do: @cities

  @impl Cinema.Source
  def theaters(%City{slug: "lyon"}),
    do: [%Theater{external_id: "T2", name: "Cinéma Lyonnais", city: "Lyon"}]

  def theaters(%City{}), do: [@theater]

  @impl Cinema.Source
  def fetch_day(%Theater{external_id: "T2"}, date) do
    {:ok, [screening(date, ~T[18:00:00], "Film Lyonnais", :vf, "T2", "Cinéma Lyonnais")]}
  end

  def fetch_day(%Theater{external_id: "T1"}, date) do
    # Anchored either side of midnight so "past" and "upcoming" are deterministic
    # whatever time the suite runs at.
    {:ok,
     [
       screening(date, ~T[00:01:00], "Toy Story 5", :vf),
       screening(date, ~T[23:59:00], "Kill Bill", :vost)
     ]}
  end

  def fetch_day(_theater, _date), do: {:ok, []}

  defp screening(date, time, title, version, id \\ "T1", theater_name \\ "Cinéma Test") do
    %Screening{
      theater_id: id,
      theater_name: theater_name,
      title: title,
      runtime_min: 100,
      genres: ["Animation", "Aventure"],
      starts_at: NaiveDateTime.new!(date, time),
      date: date,
      version: version,
      booking_url: "https://example.test/book"
    }
  end
end

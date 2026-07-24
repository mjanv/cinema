defmodule Cinema.StubSource do
  @moduledoc """
  Deterministic `Cinema.Source` for tests, so nothing hits AlloCiné.
  """

  @behaviour Cinema.Source

  alias Cinema.{Screening, Theater}

  @theater %Theater{external_id: "T1", name: "Cinéma Test", city: "Grenoble"}

  @impl Cinema.Source
  def theaters, do: [@theater]

  @impl Cinema.Source
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

  defp screening(date, time, title, version) do
    %Screening{
      theater_id: "T1",
      theater_name: @theater.name,
      title: title,
      runtime_min: 100,
      starts_at: NaiveDateTime.new!(date, time),
      date: date,
      version: version,
      booking_url: "https://example.test/book"
    }
  end
end

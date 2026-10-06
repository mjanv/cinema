defmodule Sortir.Agenda.Fixtures do
  @moduledoc """
  Loads captured venue pages so scraper tests run against real markup.
  """

  @dir Path.join(__DIR__, "fixtures/agenda")

  def html!(name), do: @dir |> Path.join("#{name}.html") |> File.read!()

  @doc "A captured API response, decoded as the source's own `get` would return it."
  def json!(name) do
    @dir |> Path.join("#{name}.json") |> File.read!() |> Jason.decode!()
  end
end

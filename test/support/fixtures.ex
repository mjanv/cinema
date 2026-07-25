defmodule Cinema.Fixtures do
  @moduledoc """
  Loads captured AlloCiné API responses so parser tests run against real payloads.
  """

  @dir Path.join(__DIR__, "fixtures")

  def load!(name) do
    @dir
    |> Path.join("#{name}.json")
    |> File.read!()
    |> Jason.decode!()
  end

  @doc "Raw HTML fixture, for the pages that are scraped rather than fetched as JSON."
  def html!(name), do: @dir |> Path.join("#{name}.html") |> File.read!()
end

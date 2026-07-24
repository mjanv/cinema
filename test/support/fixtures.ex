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
end

defmodule Cinema.Warmer do
  @moduledoc """
  Fills the showtimes cache at boot so the first visitor after a restart does
  not pay for ~35 live requests.

  Runs as a transient task: if the fetch fails, the cache simply stays empty and
  the next request retries. It must never keep the app from starting.
  """

  use Task, restart: :temporary

  require Logger

  def start_link(opts) do
    Task.start_link(__MODULE__, :run, [opts])
  end

  def run(_opts) do
    if enabled?() do
      started = System.monotonic_time(:millisecond)
      city = Cinema.find_city(nil)
      %{days: days} = Cinema.refresh(city)
      count = Enum.sum(Enum.map(days, &length(&1.theaters)))
      elapsed = System.monotonic_time(:millisecond) - started

      Logger.info("Showtimes cache warmed: #{length(days)} days, #{count} theaters, #{elapsed}ms")
    end
  rescue
    error -> Logger.warning("Showtimes cache warm failed: #{inspect(error)}")
  end

  defp enabled? do
    Application.get_env(:cinema, Cinema.Showtimes, [])
    |> Keyword.get(:warm_on_boot, false)
  end
end

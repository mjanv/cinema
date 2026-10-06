defmodule Sortir.Videos.Warmer do
  @moduledoc """
  Queues a fetch at boot, so a fresh deploy does not wait for the next cron tick.

  Transient: it returns once the job is enqueued, and a failure must never keep
  the app from starting.
  """

  use Task, restart: :temporary

  require Logger

  def start_link(opts), do: Task.start_link(__MODULE__, :run, [opts])

  def run(_opts) do
    if enabled?(), do: Sortir.Videos.refresh()
  rescue
    error -> Logger.warning("Videos warm failed: #{inspect(error)}")
  end

  defp enabled? do
    :sortir |> Application.get_env(__MODULE__, []) |> Keyword.get(:fetch_on_boot, false)
  end
end

defmodule Sortir.Agenda.Warmer do
  @moduledoc """
  Queues a scrape at boot when the agenda has gone stale.

  Unlike the showtimes cache, the agenda persists across restarts and reaches
  months ahead, so there is nothing to warm on a normal deploy. A scrape is
  queued only when the newest event is older than `@stale_after_hours` — or
  when there is nothing at all, which is the first boot on a fresh database.

  Runs as a transient task; scraping happens on the `:agenda` queue, so this
  returns as soon as the jobs are enqueued.
  """

  use Task, restart: :temporary

  require Logger

  @stale_after_hours 24

  def start_link(opts) do
    Task.start_link(__MODULE__, :run, [opts])
  end

  def run(_opts) do
    if enabled?(), do: scrape_if_stale(Sortir.Agenda.scraped_at())
  rescue
    error -> Logger.warning("Agenda warm failed: #{inspect(error)}")
  end

  defp scrape_if_stale(nil), do: queue("agenda is empty")

  defp scrape_if_stale(at) do
    hours = DateTime.diff(DateTime.utc_now(), at, :hour)

    if hours >= @stale_after_hours do
      queue("last scrape #{hours}h ago")
    else
      Logger.info("Agenda is fresh (last scrape #{hours}h ago), not scraping")
    end
  end

  defp queue(reason) do
    {:ok, queued} = Sortir.Agenda.refresh()

    Logger.info("Agenda scrape queued (#{reason}): #{queued} sources")
  end

  defp enabled? do
    Application.get_env(:sortir, __MODULE__, [])
    |> Keyword.get(:scrape_on_boot, false)
  end
end

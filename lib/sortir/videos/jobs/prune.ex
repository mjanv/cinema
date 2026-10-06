defmodule Sortir.Videos.Jobs.Prune do
  @moduledoc """
  Deletes videos published more than a month ago.

  Runs daily from cron, after the venues' 04:00 scrape. Videos are only worth
  browsing while the races are recent, and the table would otherwise grow with
  every upload for as long as the app runs.
  """

  use Oban.Worker, queue: :videos, max_attempts: 3

  alias Sortir.Videos

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    case Videos.prune() do
      0 -> :ok
      count -> Logger.info("Pruned #{count} videos older than a month")
    end

    :ok
  end
end

defmodule Sortir.Videos.Jobs.Fetch do
  @moduledoc """
  Reads the channel's feed and saves every video in it.

  The feed holds only the 15 newest uploads, about three days' worth, so this
  runs every three hours from cron and whenever someone opens the page (rate
  limited, see `Sortir.Videos.request_refresh/0`): anything pushed past the
  15th between two runs is lost for good. Returns the error on failure so Oban
  retries.

  The feed module is read from config so tests never reach YouTube.
  """

  use Oban.Worker,
    queue: :videos,
    max_attempts: 5,
    unique: [
      period: 3600,
      fields: [:worker, :args],
      states: Oban.Job.states() -- [:completed, :discarded, :cancelled]
    ]

  alias Sortir.Videos

  require Logger

  @doc """
  Queues a fetch. `opts` are `Oban.Job.new/2` options, to override the
  uniqueness: see `Sortir.Videos.request_refresh/0`.
  """
  @spec enqueue(keyword()) :: {:ok, 0 | 1}
  def enqueue(opts \\ []) do
    case Oban.insert(new(%{}, opts)) do
      {:ok, %Oban.Job{conflict?: true}} -> {:ok, 0}
      {:ok, _job} -> {:ok, 1}
      {:error, _reason} -> {:ok, 0}
    end
  end

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    with {:ok, fetched} <- feed().fetch() do
      %{fetched: total, saved: saved, new: new} = Videos.ingest(fetched)

      Logger.info("Fetched #{saved}/#{total} videos, #{new} new")

      :ok
    end
  end

  defp feed do
    :sortir |> Application.get_env(Sortir.Videos, []) |> Keyword.get(:feed, Sortir.Videos.Feed)
  end
end

defmodule Sortir.Cinema.Supervisor do
  @moduledoc """
  The showtimes domain's own processes.

  Starts after `Sortir.Core.Supervisor` and assumes the repo, Oban and PubSub
  are already running: the warmer enqueues jobs at boot and the notifier
  broadcasts as they complete.
  """

  use Supervisor

  def start_link(args \\ []) do
    Supervisor.start_link(__MODULE__, args, name: __MODULE__)
  end

  @impl Supervisor
  def init(_args) do
    children = [
      Sortir.Cinema.Jobs.Notifier,
      Sortir.Cinema.Warmer
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end

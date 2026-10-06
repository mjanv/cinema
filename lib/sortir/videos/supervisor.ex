defmodule Sortir.Videos.Supervisor do
  @moduledoc """
  The videos domain's own processes.

  Starts after `Sortir.Core.Supervisor`: the warmer enqueues a job, so the repo
  and Oban must be running.
  """

  use Supervisor

  def start_link(args \\ []) do
    Supervisor.start_link(__MODULE__, args, name: __MODULE__)
  end

  @impl Supervisor
  def init(_args) do
    Supervisor.init([Sortir.Videos.Warmer], strategy: :one_for_one)
  end
end

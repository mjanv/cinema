defmodule Sortir.Agenda.Supervisor do
  @moduledoc """
  The events domain's own processes.

  Starts after `Sortir.Core.Supervisor` and assumes the repo and Oban are
  running: the warmer enqueues scrape jobs at boot.
  """

  use Supervisor

  def start_link(args \\ []) do
    Supervisor.start_link(__MODULE__, args, name: __MODULE__)
  end

  @impl Supervisor
  def init(_args) do
    children = [
      Sortir.Agenda.Warmer
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end

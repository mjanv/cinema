defmodule Sortir.Supervisor do
  @moduledoc """
  Everything behind the web layer: shared infrastructure and the domains.

  `Sortir.Core.Supervisor` owns the repo, Oban and PubSub, so it starts first
  and the domains may assume all of it is running. The domains are independent
  of each other and could start in either order.

  `:rest_for_one`, so a domain restarts if the infrastructure under it does.
  """

  use Supervisor

  def start_link(args \\ []) do
    Supervisor.start_link(__MODULE__, args, name: __MODULE__)
  end

  @impl Supervisor
  def init(_args) do
    children = [
      Sortir.Core.Supervisor,
      Sortir.Cinema.Supervisor,
      Sortir.Agenda.Supervisor,
      Sortir.Videos.Supervisor
    ]

    Supervisor.init(children, strategy: :rest_for_one)
  end
end

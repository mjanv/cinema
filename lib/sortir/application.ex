defmodule Sortir.Application do
  @moduledoc """
  Application entry point: the system, then the web layer that serves it.

  `Sortir.Supervisor` holds the infrastructure and the domains;
  `SortirWeb.Supervisor` starts last so no request can arrive before the repo
  and job queue are up.
  """

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      Sortir.Supervisor,
      SortirWeb.Supervisor
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: __MODULE__)
  end

  @impl true
  def config_change(changed, _new, removed) do
    SortirWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end

defmodule Cinema.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    Cinema.init_cache()

    children = [
      CinemaWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:cinema, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Cinema.PubSub},
      CinemaWeb.Endpoint,
      Cinema.Warmer
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: Cinema.Supervisor)
  end

  @impl true
  def config_change(changed, _new, removed) do
    CinemaWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end

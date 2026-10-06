defmodule CinemaWeb.Supervisor do
  @moduledoc false

  use Supervisor

  def start_link(args \\ []) do
    Supervisor.start_link(__MODULE__, args, name: __MODULE__)
  end

  @impl Supervisor
  def init(_args) do
    children = [
      CinemaWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:cinema, :dns_cluster_query) || :ignore},
      CinemaWeb.Endpoint
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end

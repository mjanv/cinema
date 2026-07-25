defmodule Cinema.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    Cinema.init_cache()

    children = [
      Cinema.Supervisor,
      CinemaWeb.Supervisor
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: __MODULE__)
  end

  @impl true
  def config_change(changed, _new, removed) do
    CinemaWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end

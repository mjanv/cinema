defmodule Cinema.Supervisor do
  @moduledoc false

  use Supervisor

  def start_link(init_arg \\ []) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl Supervisor
  def init(_init_arg) do
    Cinema.init_cache()

    children = [
      Cinema.Warmer
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end

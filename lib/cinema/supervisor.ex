defmodule Cinema.Supervisor do
  @moduledoc false

  use Supervisor

  def start_link(init_arg \\ []) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl Supervisor
  def init(_init_arg) do
    children = [
      # PubSub lives here, not in the web tree: the domain broadcasts schedule
      # updates and starts first.
      {Phoenix.PubSub, name: Cinema.PubSub},
      # The Repo backs the caches, so it starts before anything that reads them.
      Cinema.Repo,
      Cinema.Release.Migrator,
      # After the migrator: Oban needs its tables to exist.
      {Oban, Application.fetch_env!(:cinema, Oban)},
      Cinema.Jobs.Notifier,
      Cinema.Warmer
    ]

    Supervisor.init(children, strategy: :rest_for_one)
  end
end

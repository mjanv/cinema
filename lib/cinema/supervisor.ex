defmodule Cinema.Supervisor do
  @moduledoc false

  use Supervisor

  alias Cinema.Release.Migrator

  def start_link(init_arg \\ []) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl Supervisor
  def init(_init_arg) do
    # Migrations run here rather than as a child: Oban verifies its tables at
    # start_link, so a sibling migrator can still lose the race.
    Migrator.run()

    children = [
      # PubSub lives here, not in the web tree: the domain broadcasts schedule
      # updates and starts first.
      {Phoenix.PubSub, name: Cinema.PubSub},
      # The Repo backs the caches, so it starts before anything that reads them.
      Cinema.Repo,
      {Oban, Application.fetch_env!(:cinema, Oban)},
      Cinema.Jobs.Notifier,
      Cinema.Warmer
    ]

    Supervisor.init(children, strategy: :rest_for_one)
  end
end

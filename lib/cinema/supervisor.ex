defmodule Cinema.Supervisor do
  @moduledoc false

  use Supervisor

  alias Cinema.Release.Migrator

  def start_link(args \\ []) do
    Supervisor.start_link(__MODULE__, args, name: __MODULE__)
  end

  @impl Supervisor
  def init(_args) do
    Migrator.run()

    children = [
      {Phoenix.PubSub, name: Cinema.PubSub},
      Cinema.Repo,
      {Oban, Application.fetch_env!(:cinema, Oban)},
      Cinema.Jobs.Notifier,
      Cinema.Warmer
    ]

    Supervisor.init(children, strategy: :rest_for_one)
  end
end

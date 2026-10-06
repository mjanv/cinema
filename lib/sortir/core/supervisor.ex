defmodule Sortir.Core.Supervisor do
  @moduledoc """
  Infrastructure shared by every domain.

  Starts the database, the migrator, the job queue and PubSub — the things
  `Sortir.Cinema` and `Sortir.Agenda` both need and neither owns. Domain
  supervisors start after this one and may assume all of it is running.

  `:rest_for_one`, so a child that dies restarts everything started after it:
  Oban holds a connection pool and cannot outlive the repo.
  """

  use Supervisor

  alias Sortir.Core.Release.Migrator

  def start_link(args \\ []) do
    Supervisor.start_link(__MODULE__, args, name: __MODULE__)
  end

  @impl Supervisor
  def init(_args) do
    # Synchronously, before any child: Oban verifies its tables on start and
    # would race a migrator running as a sibling.
    Migrator.run()

    children = [
      {Phoenix.PubSub, name: Sortir.Core.PubSub},
      Sortir.Core.Repo,
      {Oban, Application.fetch_env!(:sortir, Oban)}
    ]

    Supervisor.init(children, strategy: :rest_for_one)
  end
end

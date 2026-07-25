defmodule Cinema.Release.Migrator do
  @moduledoc """
  Runs migrations at boot.

  A release has no Mix, and the schema here is one table backing a cache, so a
  separate deploy step would be ceremony for no benefit. Runs as a transient
  task: it must complete before the caches are read, but it is not something to
  keep alive.
  """

  use Task, restart: :transient

  require Logger

  def start_link(opts), do: Task.start_link(__MODULE__, :run, [opts])

  def run(_opts \\ []) do
    # Not in test: the pool there is the Ecto sandbox, and checking a
    # connection out at boot deadlocks before any test has claimed one.
    # test_helper.exs migrates once instead.
    if Application.get_env(:cinema, :run_migrations_on_boot, true) do
      migrate()
    end

    :ok
  end

  defp migrate do
    for repo <- Application.fetch_env!(:cinema, :ecto_repos) do
      # pool_size: 1 and a generous busy_timeout: SQLite allows one writer, and
      # the migrator's temporary connection otherwise races the supervised pool
      # for the file lock on boot.
      {:ok, _fun_return, _apps} =
        Ecto.Migrator.with_repo(
          repo,
          &Ecto.Migrator.run(&1, :up, all: true),
          pool_size: 1,
          busy_timeout: 10_000
        )
    end

    :ok
  rescue
    error ->
      # A cache that cannot migrate is a degraded cache, not a dead app.
      Logger.error("Migration failed: #{inspect(error)}")
      :ok
  end
end

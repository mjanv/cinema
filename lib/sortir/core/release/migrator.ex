defmodule Sortir.Core.Release.Migrator do
  @moduledoc """
  Runs migrations at boot.

  A release ships without Mix, so migrations cannot be run by a mix task on the
  server. The schema is small and additive, so migrating at boot is safer than
  a separate deploy step that can be forgotten.

  Called synchronously from `Sortir.Core.Supervisor` before any child starts:
  Oban verifies its tables on start and would race a migrator running as a
  sibling process.
  """

  require Logger

  @doc "Migrates every configured repo. Returns `:ok` even when it could not."
  @spec run(keyword()) :: :ok
  def run(_opts \\ []) do
    # Not in test: the pool there is the Ecto sandbox, and checking a
    # connection out at boot deadlocks before any test has claimed one.
    # test_helper.exs migrates once instead.
    if Application.get_env(:sortir, :run_migrations_on_boot, true) do
      migrate()
    end

    :ok
  end

  defp migrate do
    for repo <- Application.fetch_env!(:sortir, :ecto_repos) do
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

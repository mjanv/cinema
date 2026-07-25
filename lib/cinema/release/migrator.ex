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
    for repo <- Application.fetch_env!(:cinema, :ecto_repos) do
      {:ok, _fun_return, _apps} =
        Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end

    :ok
  rescue
    error ->
      # A cache that cannot migrate is a degraded cache, not a dead app.
      Logger.error("Migration failed: #{inspect(error)}")
      :ok
  end
end

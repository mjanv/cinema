defmodule CinemaWeb.ConnCase do
  @moduledoc """
  This module defines the test case to be used by
  tests that require setting up a connection.

  Such tests rely on `Phoenix.ConnTest` and also
  import other functionality to make it easier
  to build common data structures and query the data layer.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use CinemaWeb.ConnCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate

  alias Ecto.Adapters.SQL.Sandbox

  using do
    quote do
      # The default endpoint for testing
      @endpoint CinemaWeb.Endpoint

      use CinemaWeb, :verified_routes

      # Import conveniences for testing with connections
      import Plug.Conn
      import Phoenix.ConnTest
      import CinemaWeb.ConnCase
    end
  end

  setup tags do
    pid = Sandbox.start_owner!(Cinema.Repo, shared: not tags[:async])
    on_exit(fn -> Sandbox.stop_owner(pid) end)

    # Fetching is queued now, so tests that render a board must run the jobs
    # first. Opt in with `@moduletag :schedule` — a plain view test does not
    # need the round trip.
    if tags[:schedule] do
      # First pass queues the jobs, the drain runs them, the refresh rebuilds
      # the schedule from what they cached. Without the refresh the board keeps
      # serving the empty entry written before the jobs landed.
      for city <- Cinema.cities(), do: Cinema.schedule(city)
      Oban.drain_queue(queue: :allocine)
      for city <- Cinema.cities(), do: Cinema.refresh(city)
    end

    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end
end

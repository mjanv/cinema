defmodule Cinema.DataCase do
  @moduledoc """
  Test case for anything touching the Repo: the caches and the job queue.
  """

  use ExUnit.CaseTemplate

  alias Ecto.Adapters.SQL.Sandbox

  using do
    quote do
      import Ecto.Query
      import Cinema.DataCase
    end
  end

  setup tags do
    pid = Sandbox.start_owner!(Cinema.Repo, shared: not tags[:async])
    on_exit(fn -> Sandbox.stop_owner(pid) end)
    :ok
  end
end

defmodule Sortir.Cinema.DataCase do
  @moduledoc """
  Test case for anything touching the Repo: the caches and the job queue.
  """

  use ExUnit.CaseTemplate

  alias Ecto.Adapters.SQL.Sandbox

  using do
    quote do
      import Ecto.Query
      import Sortir.Cinema.DataCase
    end
  end

  setup tags do
    pid = Sandbox.start_owner!(Sortir.Core.Repo, shared: not tags[:async])
    on_exit(fn -> Sandbox.stop_owner(pid) end)
    :ok
  end

  @doc """
  Changeset errors as a map of field to messages, for readable assertions.
  """
  def errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _whole, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end

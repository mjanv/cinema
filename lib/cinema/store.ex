defmodule Cinema.Store do
  @moduledoc """
  A TTL cache on SQLite, so it survives a redeploy.

  The caches here are expensive to refill: a cold Paris is hundreds of requests
  to AlloCiné, and doing that for every city at once is what trips their rate
  limit. Keeping the data on disk means a restart resumes warm instead of
  stampeding.

  Entries are timestamped with **wall-clock** time (`System.os_time/1`), not
  monotonic time, which resets when the VM does and would make every persisted
  entry look freshly written however old it is.

  Every operation degrades to a miss rather than raising: an unwritable or
  locked database must slow the app down, never take it out.
  """

  import Ecto.Query

  alias Cinema.Cache.Entry
  alias Cinema.Repo

  require Logger

  @doc """
  Kept for symmetry with the previous ETS/DETS stores; the Repo owns the
  connection now, so there is nothing to open.
  """
  @spec open(atom(), keyword()) :: :ok
  def open(_namespace, _opts \\ []), do: :ok

  @doc false
  @spec close(atom()) :: :ok
  def close(_namespace), do: :ok

  @doc "The value for `key`, if it was written less than `ttl` milliseconds ago."
  @spec fetch(atom(), term(), non_neg_integer() | :infinity) :: {:ok, term()} | :miss
  def fetch(namespace, key, ttl) do
    query =
      from(e in Entry,
        where: e.namespace == ^to_string(namespace) and e.key == ^encode_key(key),
        select: {e.value, e.stored_at}
      )

    case Repo.one(query) do
      {value, stored_at} ->
        if fresh?(stored_at, ttl), do: {:ok, :erlang.binary_to_term(value)}, else: :miss

      nil ->
        :miss
    end
  rescue
    error ->
      Logger.warning("Cache read failed for #{namespace}: #{inspect(error)}")
      :miss
  catch
    :exit, _reason -> :miss
  end

  @doc """
  Stores a value under `key`.

  `:stored_at` backdates the entry, which is how a failed fetch is remembered
  for a shorter window than a successful one.
  """
  @spec put(atom(), term(), term(), keyword()) :: :ok
  def put(namespace, key, value, opts \\ []) do
    entry = %{
      namespace: to_string(namespace),
      key: encode_key(key),
      value: :erlang.term_to_binary(value),
      stored_at: Keyword.get(opts, :stored_at, System.os_time(:millisecond))
    }

    Repo.insert_all(Entry, [entry],
      on_conflict: {:replace, [:value, :stored_at]},
      conflict_target: [:namespace, :key]
    )

    :ok
  rescue
    error ->
      Logger.warning("Cache write failed for #{namespace}: #{inspect(error)}")
      :ok
  catch
    :exit, _reason -> :ok
  end

  @doc "Removes one entry."
  @spec delete(atom(), term()) :: :ok
  def delete(namespace, key) do
    from(e in Entry,
      where: e.namespace == ^to_string(namespace) and e.key == ^encode_key(key)
    )
    |> Repo.delete_all()

    :ok
  rescue
    _error -> :ok
  catch
    :exit, _reason -> :ok
  end

  @doc "Empties one namespace."
  @spec clear(atom()) :: :ok
  def clear(namespace) do
    from(e in Entry, where: e.namespace == ^to_string(namespace))
    |> Repo.delete_all()

    :ok
  rescue
    _error -> :ok
  catch
    :exit, _reason -> :ok
  end

  defp fresh?(_stored_at, :infinity), do: true
  defp fresh?(stored_at, ttl), do: System.os_time(:millisecond) - stored_at < ttl

  # Keys are tuples like {:days, "grenoble"} or bare atoms; inspect gives a
  # stable, readable text form without needing a column per key shape.
  defp encode_key(key) when is_binary(key), do: key
  defp encode_key(key), do: inspect(key)
end

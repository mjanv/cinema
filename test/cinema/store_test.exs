defmodule Cinema.StoreTest do
  use ExUnit.Case, async: false

  alias Cinema.Repo
  alias Cinema.Store
  alias Ecto.Adapters.SQL.Sandbox

  @table :store_test

  setup do
    :ok = Sandbox.checkout(Repo)
    Store.clear(@table)
    :ok
  end

  test "reads back what it wrote" do
    Store.put(@table, :key, "value")

    assert {:ok, "value"} = Store.fetch(@table, :key, :timer.hours(1))
  end

  test "misses on an unknown key" do
    assert Store.fetch(@table, :absent, :timer.hours(1)) == :miss
  end

  test "misses once the entry is older than the ttl" do
    Store.put(@table, :key, "value")

    assert Store.fetch(@table, :key, 0) == :miss
  end

  test "round-trips a nested term, not just a scalar" do
    # The cache holds whole schedules: structs inside maps inside lists.
    value = %{days: [%{date: ~D[2026-07-26], theaters: [%{id: "P1", name: "Un"}]}]}
    Store.put(@table, :key, value)

    assert {:ok, ^value} = Store.fetch(@table, :key, :timer.hours(1))
  end

  test "keeps namespaces apart" do
    Store.put(:ns_a, :same_key, "a")
    Store.put(:ns_b, :same_key, "b")

    assert {:ok, "a"} = Store.fetch(:ns_a, :same_key, :timer.hours(1))
    assert {:ok, "b"} = Store.fetch(:ns_b, :same_key, :timer.hours(1))

    Store.clear(:ns_a)
    Store.clear(:ns_b)
  end

  test "ages entries on wall-clock time, not monotonic time" do
    # Monotonic time resets when the VM restarts, so a persisted entry would
    # look brand new however old it really is.
    Store.put(@table, :key, "value")

    # Backdate the entry to simulate a long gap across the restart.
    Store.put(@table, :old, "value", stored_at: System.os_time(:millisecond) - :timer.hours(2))

    assert Store.fetch(@table, :old, :timer.hours(1)) == :miss
    assert {:ok, "value"} = Store.fetch(@table, :key, :timer.hours(1))
  end

  test "delete removes a single entry" do
    Store.put(@table, :key, "value")
    Store.delete(@table, :key)

    assert Store.fetch(@table, :key, :timer.hours(1)) == :miss
  end

  test "clear empties the table" do
    Store.put(@table, :a, 1)
    Store.put(@table, :b, 2)
    Store.clear(@table)

    assert Store.fetch(@table, :a, :timer.hours(1)) == :miss
    assert Store.fetch(@table, :b, :timer.hours(1)) == :miss
  end

  test "misses on an unknown namespace rather than raising" do
    assert Store.fetch(:never_used, :key, :timer.hours(1)) == :miss
  end
end

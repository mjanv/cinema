defmodule Sortir.Core.ClockTest do
  use ExUnit.Case, async: true

  alias Sortir.Core.Clock

  describe "now/1" do
    test "reads an instant in the configured zone" do
      # 23:30 UTC in winter is already the next day in Paris; a board that
      # rendered UTC would show the wrong date for half an hour every night.
      at = ~U[2026-01-15 23:30:00Z]

      assert %DateTime{hour: 0, day: 16} = Clock.now(at)
    end

    test "follows summer time" do
      at = ~U[2026-07-15 12:00:00Z]

      assert %DateTime{hour: 14} = Clock.now(at)
    end
  end

  describe "today/1" do
    test "is the local date, not the UTC one" do
      assert Clock.today(~U[2026-01-15 23:30:00Z]) == ~D[2026-01-16]
    end
  end

  describe "to_utc/1" do
    test "reads a naive time as local before storing it" do
      # Venues publish wall-clock times with no offset; storing them as UTC
      # unshifted moves every event by an hour or two.
      assert Clock.to_utc(~N[2026-07-15 20:00:00]) == ~U[2026-07-15 18:00:00Z]
    end

    test "passes a zoned time through" do
      at = ~U[2026-07-15 18:00:00Z]

      assert Clock.to_utc(at) == at
    end

    test "keeps an hour that does not exist locally" do
      # The spring-forward hour has no local reading. Dropping the event would
      # lose it outright, so it is taken as UTC instead.
      assert %DateTime{} = Clock.to_utc(~N[2026-03-29 02:30:00])
    end

    test "passes nil through" do
      assert Clock.to_utc(nil) == nil
    end
  end

  describe "to_local/1" do
    test "shifts a stored time back into the zone" do
      assert %DateTime{hour: 20} = Clock.to_local(~U[2026-07-15 18:00:00Z])
    end
  end

  describe "timezone/0" do
    test "defaults to the city's zone" do
      assert Clock.timezone() == "Europe/Paris"
    end
  end
end

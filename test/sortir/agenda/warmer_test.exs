defmodule Sortir.Agenda.WarmerTest do
  use Sortir.Cinema.DataCase, async: false

  import ExUnit.CaptureLog

  alias Sortir.Agenda
  alias Sortir.Agenda.Warmer
  alias Sortir.Core.Repo

  setup do
    Repo.delete_all(Oban.Job)

    Application.put_env(:sortir, Warmer, scrape_on_boot: true)
    on_exit(fn -> Application.delete_env(:sortir, Warmer) end)

    :ok
  end

  defp queued, do: Repo.aggregate(Oban.Job, :count)

  test "scrapes when the agenda is empty" do
    # First boot on a fresh database: there is nothing to serve, so the venues
    # must be read even though a scrape is expensive.
    capture_log(fn -> Warmer.run([]) end)

    assert queued() == length(Agenda.sources())
  end

  test "does not scrape when the agenda was read recently" do
    # A redeploy must not re-read every venue: the data survives restarts and
    # reaches months ahead.
    {:ok, venue} = Agenda.upsert_venue(%{slug: "v", name: "V", city: "Grenoble"})

    {:ok, _event} =
      Agenda.save(
        %{
          event: %{source: "s", external_id: "e", title: "T"},
          occurrence: %{starts_at: ~N[2026-09-04 20:00:00]}
        },
        venue
      )

    capture_log(fn -> Warmer.run([]) end)

    assert queued() == 0
  end

  test "does nothing when not enabled" do
    Application.put_env(:sortir, Warmer, scrape_on_boot: false)

    capture_log(fn -> Warmer.run([]) end)

    assert queued() == 0
  end

  test "a failure does not bring down the boot" do
    # The warmer is started by a supervisor: raising here would take the
    # application with it, over a cache that could simply stay cold.
    Application.put_env(:sortir, Warmer, scrape_on_boot: "not a boolean")

    assert capture_log(fn -> assert Warmer.run([]) end)
  end
end

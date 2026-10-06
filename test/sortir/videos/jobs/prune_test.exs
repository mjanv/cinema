defmodule Sortir.Videos.Jobs.PruneTest do
  use Sortir.Cinema.DataCase, async: false

  use Oban.Testing,
    repo: Sortir.Core.Repo,
    engine: Oban.Engines.Lite,
    notifier: Oban.Notifiers.PG

  alias Sortir.Videos
  alias Sortir.Videos.Jobs.{Fetch, Prune}

  defp video(id, days_ago) do
    %{
      youtube_id: id,
      title: id,
      published_at: DateTime.add(DateTime.utc_now(), -days_ago * 86_400),
      views: 1
    }
  end

  test "deletes videos older than a month and keeps the rest" do
    {:ok, _} = Videos.save(video("old", 40))
    {:ok, _} = Videos.save(video("recent", 2))

    assert :ok = perform_job(Prune, %{})
    assert ["recent"] = Enum.map(Videos.list(), & &1.youtube_id)
  end

  test "is a no-op on an empty table" do
    assert :ok = perform_job(Prune, %{})
  end

  test "is scheduled by cron, daily, alongside the 3-hourly fetch" do
    {Oban.Plugins.Cron, opts} =
      :sortir
      |> Application.fetch_env!(Oban)
      |> Keyword.fetch!(:plugins)
      |> List.keyfind!(Oban.Plugins.Cron, 0)

    crontab = Keyword.fetch!(opts, :crontab)

    assert {"30 4 * * *", Prune} in crontab
    assert {"0 */3 * * *", Fetch} in crontab
  end
end

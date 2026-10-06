defmodule Sortir.Videos.StubFeed do
  @moduledoc "Deterministic feed for tests, so nothing hits YouTube."

  def fetch(_opts \\ []) do
    {:ok,
     [
       %{
         youtube_id: "stub-1",
         title: "Tour de Lombardie : Pogacar s'impose",
         published_at: ~U[2026-10-05 12:00:00Z],
         views: 1234
       }
     ]}
  end
end

defmodule Sortir.Videos.FailingFeed do
  @moduledoc "A feed that is down."

  def fetch(_opts \\ []), do: {:error, {:http_status, 500}}
end

defmodule Sortir.Videos.StaleFeed do
  @moduledoc """
  A feed whose last entry is older than the retention period, as when the
  channel has gone quiet and the 15th video is weeks old.
  """

  def fetch(_opts \\ []) do
    {:ok,
     [
       %{
         youtube_id: "fresh",
         title: "Recent",
         published_at: DateTime.add(DateTime.utc_now(), -86_400),
         views: 1
       },
       %{
         youtube_id: "stale",
         title: "Old",
         published_at: DateTime.add(DateTime.utc_now(), -60 * 86_400),
         views: 1
       }
     ]}
  end
end

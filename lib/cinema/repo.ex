defmodule Cinema.Repo do
  @moduledoc """
  SQLite, used for one thing: making the caches survive a redeploy.

  There is no domain model here. Refilling a cold cache is hundreds of requests
  to AlloCiné — a cold Paris alone is enough to trip their rate limit — so the
  cost of losing it on every deploy is measured in outages, not milliseconds.
  """

  use Ecto.Repo,
    otp_app: :cinema,
    adapter: Ecto.Adapters.SQLite3
end

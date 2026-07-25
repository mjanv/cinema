defmodule Cinema.Repo do
  @moduledoc false

  use Ecto.Repo,
    otp_app: :cinema,
    adapter: Ecto.Adapters.SQLite3
end

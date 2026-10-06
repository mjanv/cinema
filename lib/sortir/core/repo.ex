defmodule Sortir.Core.Repo do
  @moduledoc false

  use Ecto.Repo,
    otp_app: :sortir,
    adapter: Ecto.Adapters.SQLite3
end

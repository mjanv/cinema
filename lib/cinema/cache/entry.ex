defmodule Cinema.Cache.Entry do
  @moduledoc """
  One cached value.

  `namespace` keeps the schedule and the city directory apart; `key` is opaque
  and encoded by the caller. Values are Erlang terms, stored as a binary blob:
  the cache holds nested structs, and reshaping those into columns would buy
  nothing a key/value table does not already give.
  """

  use Ecto.Schema

  @primary_key false
  schema "cache_entries" do
    field(:namespace, :string, primary_key: true)
    field(:key, :string, primary_key: true)
    field(:value, :binary)
    # Wall-clock milliseconds: monotonic time resets with the VM, which would
    # make every persisted entry look freshly written.
    field(:stored_at, :integer)
  end
end

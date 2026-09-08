defmodule Cinema.Traffic.Hit do
  @moduledoc """
  How many times one path was served during one hour.

  `bucket` is a UTC hour written as `"2026-09-08T14"`. Fixed-width and
  zero-padded, so string comparison is chronological comparison and a range
  query needs no date functions.
  """

  use Ecto.Schema

  @primary_key false
  schema "traffic" do
    field(:bucket, :string, primary_key: true)
    field(:path, :string, primary_key: true)
    field(:count, :integer)
  end
end

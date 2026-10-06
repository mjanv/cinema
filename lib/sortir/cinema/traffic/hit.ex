defmodule Cinema.Traffic.Hit do
  @moduledoc """
  How many times one path, showing one city, was viewed during one hour.

  `bucket` is a UTC hour written as `"2026-09-08T14"`. Fixed-width and
  zero-padded, so string comparison is chronological comparison and a range
  query needs no date functions.

  `city` is a city slug, or `""` for a page that shows no city at all. It is
  part of the key rather than nullable because SQLite treats NULLs in a unique
  index as distinct, which would make every upsert insert a fresh row.
  """

  use Ecto.Schema

  @primary_key false
  schema "traffic" do
    field(:bucket, :string, primary_key: true)
    field(:path, :string, primary_key: true)
    field(:city, :string, primary_key: true)
    field(:count, :integer)
  end
end

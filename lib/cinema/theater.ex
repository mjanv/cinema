defmodule Cinema.Theater do
  @moduledoc """
  A cinema, as exposed by some `Cinema.Source`.

  `external_id` is opaque and only meaningful to the source that issued it
  (an AlloCiné theater code today), which keeps the behaviour source-agnostic.
  """

  @enforce_keys [:external_id, :name]
  defstruct [:external_id, :name, :city]

  @type t :: %__MODULE__{
          external_id: String.t(),
          name: String.t(),
          city: String.t() | nil
        }
end

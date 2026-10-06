defmodule Cinema.City do
  @moduledoc """
  A city you can browse showtimes for.

  Two identifiers, deliberately separated:

    * `slug` — this app's public identity, derived from the name (`grenoble`).
      It appears in URLs and is what users bookmark.
    * `external_id` — the source's own key (`ville-98857` for AlloCiné).
      Internal. It must never reach a URL or a template: leaking it would tie
      every bookmark to one scraper, so changing or adding a `Cinema.Source`
      would break them all.
  """

  @enforce_keys [:slug, :name]
  defstruct [:slug, :name, :external_id]

  @type t :: %__MODULE__{
          slug: String.t(),
          name: String.t(),
          external_id: String.t() | nil
        }

  @doc "Builds a city, deriving the public slug from its name."
  @spec new(String.t() | nil, String.t()) :: t()
  def new(external_id, name) do
    %__MODULE__{slug: slug(name), name: name, external_id: external_id}
  end

  @typedoc "Whether this covers one town or a whole department."
  @type kind :: :city | :department

  @doc """
  Whether this is a single town or a department.

  Derived from the source's id rather than stored: AlloCiné exposes both under
  the same page shape, and the distinction only matters for grouping the
  picker. Anything unrecognised reads as a city.
  """
  @spec kind(t()) :: kind()
  def kind(%__MODULE__{external_id: "departement-" <> _rest}), do: :department
  def kind(%__MODULE__{}), do: :city

  @doc """
  The URL-safe slug for a city name.

  Accents are folded to ASCII and everything else collapses to single hyphens,
  so `Aix-en-Provence` and `Nîmes` become `aix-en-provence` and `nimes`.
  """
  @spec slug(String.t()) :: String.t()
  def slug(name) when is_binary(name) do
    name
    |> String.normalize(:nfd)
    # Strip the combining marks NFD just split off, folding é to e.
    |> String.replace(~r/[\x{0300}-\x{036F}]/u, "")
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
  end
end

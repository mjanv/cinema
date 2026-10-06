defmodule Sortir.Videos.Video do
  @moduledoc """
  One video of the channel.

  `title` is kept so a search can match against it, and is never rendered: on
  this channel it usually states the result. The thumbnail is not stored; it is
  derived from `youtube_id`.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "videos" do
    field(:youtube_id, :string)
    field(:title, :string)
    field(:published_at, :utc_datetime)
    field(:views, :integer, default: 0)
    # Set by `Sortir.Videos.list/1` when searching: the part of the title the
    # query matched, spelled as the title spells it. Never the whole title.
    field(:match, :string, virtual: true)
    # Also set when searching: the whole title as `{:hidden, length}` and
    # `{:shown, text}` parts in order, so a page can draw the matched text in
    # place with bars for the rest. Hidden parts are only ever a length.
    field(:segments, :any, virtual: true)

    timestamps(type: :utc_datetime)
  end

  def changeset(video, attrs) do
    video
    |> cast(attrs, [:youtube_id, :title, :published_at, :views])
    |> validate_required([:youtube_id, :title, :published_at])
    |> validate_number(:views, greater_than_or_equal_to: 0)
    |> unique_constraint(:youtube_id)
  end
end

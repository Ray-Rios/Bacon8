defmodule ChatChannels.StreamingSession do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "streaming_sessions" do
    belongs_to :channel, ChatChannels.Channel
    belongs_to :streamer, Bacon8.Accounts.User
    
    field :title, :string
    field :stream_type, :string # audio, video, screen
    field :is_active, :boolean, default: true
    field :viewer_count, :integer, default: 0
    field :started_at, :utc_datetime
    field :ended_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  def changeset(session, attrs) do
    session
    |> cast(attrs, [:channel_id, :streamer_id, :title, :stream_type, :is_active, :viewer_count, :started_at, :ended_at])
    |> validate_required([:channel_id, :streamer_id, :title, :stream_type])
    |> validate_inclusion(:stream_type, ["audio", "video", "screen"])
    |> maybe_set_started_at()
  end

  defp maybe_set_started_at(changeset) do
    if is_nil(get_field(changeset, :started_at)) do
      put_change(changeset, :started_at, DateTime.truncate(DateTime.utc_now(), :second))
    else
      changeset
    end
  end
end

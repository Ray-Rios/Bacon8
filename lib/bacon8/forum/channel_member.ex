defmodule Bacon8.Forum.ChannelMember do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "channel_members" do
    belongs_to :channel, Bacon8.Forum.Channel
    belongs_to :user, Bacon8.Accounts.User
    
    field :role, :string, default: "member" # owner, admin, moderator, member
    field :nickname, :string
    field :is_muted, :boolean, default: false
    field :is_banned, :boolean, default: false
    field :last_read_message_id, :binary_id
    field :last_seen_at, :utc_datetime
    field :joined_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  def changeset(member, attrs) do
    member
    |> cast(attrs, [:channel_id, :user_id, :role, :nickname, :is_muted, :is_banned, :joined_at, :last_read_message_id, :last_seen_at])
    |> validate_required([:channel_id, :user_id])
    |> validate_inclusion(:role, ["owner", "moderator", "member", "banned"])
    |> unique_constraint([:channel_id, :user_id])
    |> maybe_set_joined_at()
  end

  defp maybe_set_joined_at(changeset) do
    if is_nil(get_field(changeset, :joined_at)) do
      # Truncate to seconds so Ecto's :utc_datetime field requirements are satisfied
      put_change(changeset, :joined_at, DateTime.truncate(DateTime.utc_now(), :second))
    else
      changeset
    end
  end
end

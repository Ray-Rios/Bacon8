defmodule Bacon8.Notifications.UserNotification do
  @moduledoc """
  Schema for user notifications (mentions, replies, etc.)
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "user_notifications" do
    field :type, :string  # "mention", "reply", "invite", etc.
    field :title, :string
    field :content, :string
    field :read, :boolean, default: false
    field :read_at, :utc_datetime
    
    # Link to the resource
    field :resource_type, :string  # "message", "channel", "thread"
    field :resource_id, :binary_id
    
    # Additional context for navigation
    field :metadata, :map, default: %{}
    
    belongs_to :user, Bacon8.Accounts.User
    belongs_to :actor, Bacon8.Accounts.User  # Who triggered the notification

    # What it came from (a plugin's own kind and id, e.g. "chat_channel"). The old
    # channel_id column is still in the table, unused, until the plan's last phase.
    field :source_kind, :string
    field :source_id, :binary_id

    timestamps(type: :utc_datetime)
  end

  def changeset(notification, attrs) do
    notification
    |> cast(attrs, [:type, :title, :content, :read, :read_at, :resource_type, :resource_id, :metadata, :user_id, :actor_id, :source_kind, :source_id])
    |> validate_required([:type, :user_id])
    |> validate_inclusion(:type, ["mention", "reply", "invite", "system"])
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:actor_id)
  end

  def mark_read_changeset(notification) do
    notification
    |> change(%{read: true, read_at: DateTime.truncate(DateTime.utc_now(), :second)})
  end
end

defmodule ChatChannels.UserSettings do
  @moduledoc """
  A user's chat settings, one row per user (`chat_user_settings`): how many channels they may
  create, the order they keep their channel list in, and whether others may invite them.

  These used to be columns on the hub's `users` table. They live here so the plugin owns its
  data: delete the plugin and the hub's user table doesn't know chat existed. A user without a
  row has the defaults (`ChatChannels.default_channel_allowance/0`, no custom order, invites on).
  """
  use Ecto.Schema

  @primary_key {:user_id, :binary_id, autogenerate: false}
  @foreign_key_type :binary_id

  schema "chat_user_settings" do
    field :channel_allowance, :integer, default: 5
    field :channel_order, {:array, :binary_id}, default: []
    field :allow_invites, :boolean, default: true

    timestamps(type: :utc_datetime)
  end
end

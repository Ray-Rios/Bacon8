defmodule Bacon8.Repo.Migrations.DropNotificationChannelId do
  use Ecto.Migration

  @moduledoc """
  `user_notifications.channel_id` has been unread since notifications got generic sources
  (20261025020000), and its foreign key pointed at the chat plugin's table. Dropping the column
  (and with it the key) frees the hub of any reference to chat. A fresh database never had it.
  """

  def up, do: execute("ALTER TABLE user_notifications DROP COLUMN IF EXISTS channel_id")

  def down, do: :ok
end

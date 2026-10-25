defmodule Bacon8.Repo.Migrations.NotificationSources do
  use Ecto.Migration

  # A notification used to point at a forum channel (`channel_id`). Chat is becoming a
  # plugin, so the hub stops knowing about channels: a notification says what it came from
  # (`source_kind` and `source_id`, both the plugin's own) and carries the address to open
  # in its metadata (`path`). `channel_id` and its foreign key stay, unused, until the last
  # phase of docs/chat-channels-plugin.md moves the chat tables out of the core.
  #
  # The backfill is for any mention notification that was stored with a channel. (There
  # should be none: mentions crashed before they were saved, because they read a user field
  # that doesn't exist. It is here so none is stranded without a link if there are.)

  def up do
    execute "ALTER TABLE user_notifications ADD COLUMN IF NOT EXISTS source_kind varchar(255)"
    execute "ALTER TABLE user_notifications ADD COLUMN IF NOT EXISTS source_id uuid"

    execute """
    CREATE INDEX IF NOT EXISTS user_notifications_source_kind_source_id_index
      ON user_notifications (source_kind, source_id)
    """

    execute """
    UPDATE user_notifications
       SET source_kind = 'chat_channel',
           source_id = channel_id,
           metadata = COALESCE(metadata, '{}'::jsonb)
                      || jsonb_build_object('path', '/chat/' || channel_id::text,
                                            'source_name', COALESCE(metadata->>'channel_name', ''))
     WHERE channel_id IS NOT NULL AND source_kind IS NULL
    """
  end

  def down do
    execute "DROP INDEX IF EXISTS user_notifications_source_kind_source_id_index"
    execute "ALTER TABLE user_notifications DROP COLUMN IF EXISTS source_id"
    execute "ALTER TABLE user_notifications DROP COLUMN IF EXISTS source_kind"
  end
end

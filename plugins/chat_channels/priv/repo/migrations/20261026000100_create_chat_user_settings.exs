defmodule ChatChannels.Repo.Migrations.CreateChatUserSettings do
  use Ecto.Migration

  @moduledoc """
  Chat's per-user settings move off the hub's `users` table (BACON8.md, chat phase 4).

  `users.channel_allowance`, `channel_order` and `allow_channel_invites` are copied here for every
  user who isn't on the defaults, once. The old columns are left in place, unread, until the owner
  has checked the copy in production (a later migration drops them); a fresh database never had them.
  """

  def up do
    execute("""
    CREATE TABLE IF NOT EXISTS chat_user_settings (
      user_id uuid PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
      channel_allowance integer NOT NULL DEFAULT 5,
      channel_order uuid[] NOT NULL DEFAULT ARRAY[]::uuid[],
      allow_invites boolean NOT NULL DEFAULT true,
      inserted_at timestamp(0) without time zone NOT NULL,
      updated_at timestamp(0) without time zone NOT NULL
    )
    """)

    execute("""
    DO $$ BEGIN
      IF EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_schema = 'public' AND table_name = 'users' AND column_name = 'channel_allowance') THEN
        INSERT INTO chat_user_settings (user_id, channel_allowance, channel_order, allow_invites, inserted_at, updated_at)
        SELECT id, channel_allowance, COALESCE(channel_order, ARRAY[]::uuid[]), COALESCE(allow_channel_invites, true),
               now() AT TIME ZONE 'utc', now() AT TIME ZONE 'utc'
        FROM users
        WHERE channel_allowance <> 5
           OR COALESCE(cardinality(channel_order), 0) > 0
           OR allow_channel_invites IS NOT TRUE
        ON CONFLICT (user_id) DO NOTHING;
      END IF;
    END $$
    """)
  end

  def down, do: execute("DROP TABLE IF EXISTS chat_user_settings")
end

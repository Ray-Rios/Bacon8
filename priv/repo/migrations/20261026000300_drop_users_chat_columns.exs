defmodule Bacon8.Repo.Migrations.DropUsersChatColumns do
  use Ecto.Migration

  @moduledoc """
  Chat's per-user settings live in the plugin's `chat_user_settings` (20261026000100). The owner
  checked the copy in production on 2026-10-26 (3 non-default users, 3 settings rows, 0 differences),
  so the old, unread columns go. A database made after the baseline dropped them never had them.
  """

  def up do
    execute "ALTER TABLE users DROP COLUMN IF EXISTS channel_allowance"
    execute "ALTER TABLE users DROP COLUMN IF EXISTS channel_order"
    execute "ALTER TABLE users DROP COLUMN IF EXISTS allow_channel_invites"
  end

  def down, do: :ok
end

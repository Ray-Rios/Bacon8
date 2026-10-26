defmodule Bacon8.Repo.Migrations.CommentSpamFlag do
  use Ecto.Migration

  @moduledoc """
  A comment can now be marked spam (kept out of the public list and the pending queue, but kept
  on record so repeats can be recognised). `is_approved` stays as it was.
  """

  def up do
    execute "ALTER TABLE comments ADD COLUMN IF NOT EXISTS is_spam boolean NOT NULL DEFAULT false"
    execute "CREATE INDEX IF NOT EXISTS comments_post_id_is_approved_index ON comments (post_id, is_approved) WHERE is_spam = false"
    execute "CREATE INDEX IF NOT EXISTS comments_user_id_inserted_at_index ON comments (user_id, inserted_at)"
  end

  def down do
    execute "DROP INDEX IF EXISTS comments_user_id_inserted_at_index"
    execute "DROP INDEX IF EXISTS comments_post_id_is_approved_index"
    execute "ALTER TABLE comments DROP COLUMN IF EXISTS is_spam"
  end
end

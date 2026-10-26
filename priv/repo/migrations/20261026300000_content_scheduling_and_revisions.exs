defmodule Bacon8.Repo.Migrations.ContentSchedulingAndRevisions do
  use Ecto.Migration

  @moduledoc """
  `scheduled_at`: a draft with a time goes live by itself at that time (`Bacon8.Content.Publisher`).
  `content_revisions`: earlier versions of a page or post, kept so an edit can be undone
  (`Bacon8.Content.Revisions`). `record_id` points at a page or a post, by `kind`, so it has no
  foreign key; the revisions of a deleted record are removed with it by the context.
  """

  def up do
    execute "ALTER TABLE posts ADD COLUMN IF NOT EXISTS scheduled_at timestamp(0) without time zone"
    execute "ALTER TABLE pages ADD COLUMN IF NOT EXISTS scheduled_at timestamp(0) without time zone"
    execute "CREATE INDEX IF NOT EXISTS posts_scheduled_at_index ON posts (scheduled_at) WHERE scheduled_at IS NOT NULL"
    execute "CREATE INDEX IF NOT EXISTS pages_scheduled_at_index ON pages (scheduled_at) WHERE scheduled_at IS NOT NULL"

    execute """
    CREATE TABLE IF NOT EXISTS content_revisions (
      id uuid PRIMARY KEY,
      kind varchar(255) NOT NULL,
      record_id uuid NOT NULL,
      title varchar(255),
      excerpt text,
      content text,
      user_id uuid REFERENCES users(id) ON DELETE SET NULL,
      inserted_at timestamp(0) without time zone NOT NULL
    )
    """

    execute "CREATE INDEX IF NOT EXISTS content_revisions_record_index ON content_revisions (kind, record_id, inserted_at)"
  end

  def down do
    execute "DROP TABLE IF EXISTS content_revisions"
    execute "DROP INDEX IF EXISTS pages_scheduled_at_index"
    execute "DROP INDEX IF EXISTS posts_scheduled_at_index"
    execute "ALTER TABLE pages DROP COLUMN IF EXISTS scheduled_at"
    execute "ALTER TABLE posts DROP COLUMN IF EXISTS scheduled_at"
  end
end

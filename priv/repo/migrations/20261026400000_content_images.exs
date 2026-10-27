defmodule Bacon8.Repo.Migrations.ContentImages do
  use Ecto.Migration

  @moduledoc """
  The image library (`Bacon8.Content.Library`): one row for each picture added to a page or post.
  `sha256` identifies the picture itself, so a picture reused on several pages is listed once.
  Pictures uploaded before this table existed are added by `Library.sync_from_disk/0`.
  """

  def up do
    execute """
    CREATE TABLE IF NOT EXISTS content_images (
      id uuid PRIMARY KEY,
      url varchar(1024) NOT NULL,
      filename varchar(255) NOT NULL,
      context varchar(255) NOT NULL,
      sha256 varchar(64) NOT NULL,
      byte_size bigint NOT NULL DEFAULT 0,
      mime_type varchar(255),
      user_id uuid REFERENCES users(id) ON DELETE SET NULL,
      inserted_at timestamp(0) without time zone NOT NULL
    )
    """

    execute "CREATE UNIQUE INDEX IF NOT EXISTS content_images_url_index ON content_images (url)"
    execute "CREATE INDEX IF NOT EXISTS content_images_sha256_index ON content_images (sha256, inserted_at)"
  end

  def down do
    execute "DROP TABLE IF EXISTS content_images"
  end
end

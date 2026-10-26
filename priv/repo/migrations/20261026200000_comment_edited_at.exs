defmodule Bacon8.Repo.Migrations.CommentEditedAt do
  use Ecto.Migration

  @moduledoc """
  A member can edit their own comment; `edited_at` lets the page say so.
  """

  def up do
    execute "ALTER TABLE comments ADD COLUMN IF NOT EXISTS edited_at timestamp(0) without time zone"
  end

  def down do
    execute "ALTER TABLE comments DROP COLUMN IF EXISTS edited_at"
  end
end

defmodule Bacon8.Repo.Migrations.MoveDefaultAvatarIntoRelease do
  use Ecto.Migration

  # The old default avatar was another site's artwork on the uploads volume and
  # was removed on 2026-10-20. Its replacement ships with the release at
  # /images/default-avatar.png; point any account that stored the old path at it.
  def up do
    execute """
    UPDATE users SET avatar_url = '/images/default-avatar.png'
    WHERE avatar_url = '/uploads/public/images/default_avatar.jpg'
    """
  end

  def down, do: :ok
end

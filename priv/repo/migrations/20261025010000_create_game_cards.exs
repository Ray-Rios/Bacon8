defmodule Bacon8.Repo.Migrations.CreateGameCards do
  use Ecto.Migration

  # A plugin game's card on /games as changed by an admin (Bacon8.GameCards). The
  # plugin's own folder (priv/static/card/) gives the card; a row here overrides it.
  def change do
    create table(:game_cards, primary_key: false) do
      add :plugin_slug, :string, primary_key: true
      add :data, :map, null: false, default: %{}
      add :updated_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      timestamps(type: :utc_datetime_usec)
    end
  end
end

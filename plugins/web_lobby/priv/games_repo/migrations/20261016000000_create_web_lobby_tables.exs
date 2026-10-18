defmodule WebLobby.Repo.Migrations.CreateWebLobbyTables do
  use Ecto.Migration

  @moduledoc """
  Web Lobby's own tables, in the games database next to `game_characters`
  (BACON8.md §9). Every table a plugin owns is prefixed with its slug.

  Characters are not here: Web Lobby uses the platform's `game_characters`
  (game slug "web_lobby"), keeping its HP/MP/PvP in `stats` and its model,
  type, zone and position in `settings`.

  Plugin migrations share the games database's schema_migrations table with
  core, so their version numbers must be unique - use the current timestamp,
  as `mix ecto.gen.migration` does.
  """

  def up do
    create table(:web_lobby_zones, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :slug, :string, null: false
      add :description, :text
      add :spawn_x, :float, null: false, default: 0.0
      add :spawn_y, :float, null: false, default: 0.0
      add :spawn_z, :float, null: false, default: 0.0
      add :spawn_heading, :float, null: false, default: 0.0
      timestamps(type: :utc_datetime)
    end

    create unique_index(:web_lobby_zones, [:slug])

    create table(:web_lobby_spells, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :slug, :string, null: false
      add :name, :string, null: false
      add :description, :text
      add :mp_cost, :integer, null: false, default: 0
      add :base_damage, :integer, null: false, default: 0
      add :range, :float, null: false, default: 20.0
      add :recast_ms, :integer, null: false, default: 1000
      add :projectile_type, :string, null: false, default: "stone"
      add :targeting_type, :string, null: false, default: "single"
      timestamps(type: :utc_datetime)
    end

    create unique_index(:web_lobby_spells, [:slug])

    create table(:web_lobby_character_spells, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :character_id, references(:game_characters, type: :binary_id, on_delete: :delete_all), null: false
      add :spell_id, references(:web_lobby_spells, type: :binary_id, on_delete: :delete_all), null: false
      add :unlocked_at, :utc_datetime, null: false
      timestamps(type: :utc_datetime)
    end

    create unique_index(:web_lobby_character_spells, [:character_id, :spell_id])

    # Starter content, so a fresh install is playable without seeds.
    execute """
    INSERT INTO web_lobby_zones (id, name, slug, description, inserted_at, updated_at)
    VALUES (gen_random_uuid(), 'Lobby', 'lobby', 'Default spawn: a large 80s style arcade room.', NOW(), NOW())
    ON CONFLICT (slug) DO NOTHING
    """

    execute """
    INSERT INTO web_lobby_spells (id, slug, name, description, mp_cost, base_damage, range, recast_ms,
                                  projectile_type, targeting_type, inserted_at, updated_at)
    VALUES (gen_random_uuid(), 'throw_stone', 'Throw Stone', 'Hurl a stone at your target. Deals 1 damage if it hits.',
            1, 1, 20.0, 500, 'stone', 'single', NOW(), NOW())
    ON CONFLICT (slug) DO NOTHING
    """
  end

  def down do
    drop table(:web_lobby_character_spells)
    drop table(:web_lobby_spells)
    drop table(:web_lobby_zones)
  end
end

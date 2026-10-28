defmodule BaconWorld.GamesRepo.Migrations.CreateBaconWorldPlacements do
  use Ecto.Migration

  @moduledoc """
  World building in game (2026-10-28, `BaconWorld.Building`): everything a player put in the world
  in build mode (` key), and who may place what.

    * `bacon_world_placements` - one row per placed object: the zone, the catalogue asset
      (`"P_Barrel"`, `"K_Wall_Stone"`, `"mob:goblin"`, `"npc:clothier"`...), where it stands
      (metres), its turn about the vertical (radians), its size, a little per-kind data (a
      creature spawn's count and radius, an NPC's name) and who placed it.
    * `bacon_world_asset_rules` - the lowest role that may place (and so move and delete) an
      asset, set by admins in game. An asset with no row uses the catalogue's default.
  """

  def change do
    create table(:bacon_world_placements, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :zone, :string, null: false
      add :asset, :string, null: false
      add :x, :float, null: false
      add :y, :float, null: false, default: 0.0
      add :z, :float, null: false
      add :rot, :float, null: false, default: 0.0
      add :scale, :float, null: false, default: 1.0
      add :data, :map, null: false, default: %{}
      add :placed_by, :binary_id
      add :character_id, :binary_id
      timestamps(type: :utc_datetime)
    end

    create index(:bacon_world_placements, [:zone])
    create index(:bacon_world_placements, [:zone, :asset])

    create table(:bacon_world_asset_rules, primary_key: false) do
      add :asset, :string, primary_key: true
      add :min_role, :string, null: false
      add :updated_by, :binary_id
      timestamps(type: :utc_datetime)
    end
  end
end

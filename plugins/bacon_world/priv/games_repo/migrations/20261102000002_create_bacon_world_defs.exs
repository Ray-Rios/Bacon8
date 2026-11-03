defmodule BaconWorld.GamesRepo.Migrations.CreateBaconWorldDefs do
  # 2026-11-02 (owner chose "move everything into the DB"): the game's other definitions, one row
  # each: `kind` "monster" (creature types, BaconWorld.Mobs.Spawns) and "merchant" (the merchants and
  # NPCs in code, BaconWorld.Merchants). `data` is JSON (BaconWorld.Defs encodes ranges and tuples).
  # Filled once from priv/seed/<kind>s.json the first time the game reads them.
  use Ecto.Migration

  def change do
    create table(:bacon_world_defs, primary_key: false) do
      add :kind, :string, primary_key: true
      add :id, :string, primary_key: true
      add :data, :map, null: false, default: %{}
      add :position, :integer, null: false, default: 0
      timestamps(type: :utc_datetime)
    end
  end
end

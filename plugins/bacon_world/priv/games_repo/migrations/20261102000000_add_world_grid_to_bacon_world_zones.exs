defmodule BaconWorld.GamesRepo.Migrations.AddWorldGridToBaconWorldZones do
  # 2026-11-02 (owner): a world of zones on a grid around the starter zone (Crater Lake, the
  # "lobby"), each 4096 m with its own terrain (BaconWorld.WorldGen, /admin/bacon_world/world).
  #
  #   number           the zone's number (/zone x y z <number>); the lobby is 0
  #   grid_x, grid_z   its cell on the world grid (the lobby is 0,0; +x east, +z south)
  #   terrain          the terrain files' id (World/Terrain/<terrain>_*.bin or World/Zones/...)
  #   terrain_version  bumped when its terrain is replaced (clients refetch; nodes re-seat)
  #   status           "planned", "generating", "ready", "failed"
  #   meta             the terrain's numbers: size_m, samples, water_samples, x0, z0, lo, hi, step, sea, margin, dir
  use Ecto.Migration

  def change do
    alter table(:bacon_world_zones) do
      add :number, :integer
      add :grid_x, :integer
      add :grid_z, :integer
      add :terrain, :string
      add :terrain_version, :integer, default: 1, null: false
      add :status, :string, default: "ready", null: false
      add :meta, :map, default: %{}
    end

    create unique_index(:bacon_world_zones, [:number])
    create unique_index(:bacon_world_zones, [:grid_x, :grid_z])

    execute(
      "UPDATE bacon_world_zones SET number = 0, grid_x = 0, grid_z = 0, terrain = 'crater_lake' WHERE slug = 'lobby'",
      ""
    )
  end
end

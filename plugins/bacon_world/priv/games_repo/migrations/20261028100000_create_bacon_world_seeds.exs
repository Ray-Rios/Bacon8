defmodule BaconWorld.GamesRepo.Migrations.CreateBaconWorldSeeds do
  use Ecto.Migration

  @moduledoc """
  Which of the code's layouts have been turned into placements (`BaconWorld.Building.ensure_seeded/1`,
  2026-10-28): one row per zone and key (`"village"`, `"camps:island"`, `"camps:crater_lake"`). Written
  once, in the same transaction as the placements, so a village deleted piece by piece in build mode
  never comes back.
  """

  def change do
    create table(:bacon_world_seeds, primary_key: false) do
      add :zone, :string, null: false, primary_key: true
      add :key, :string, null: false, primary_key: true
      add :count, :integer, null: false, default: 0
      timestamps(type: :utc_datetime, updated_at: false)
    end
  end
end

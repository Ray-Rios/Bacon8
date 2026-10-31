defmodule BaconWorld.GamesRepo.Migrations.AddHpToBaconWorldAssetRules do
  use Ecto.Migration

  def change do
    alter table(:bacon_world_asset_rules) do
      add :hp, :integer, default: 10, null: false
    end
  end
end

defmodule BaconWorld.GamesRepo.Migrations.CreateBaconWorldItemDefs do
  # 2026-11-02 (owner chose "move everything into the DB"): every item's definition is a row,
  # edited on /admin/bacon_world/database. `data` holds the item (BaconWorld.Items' fields), `position`
  # the catalogue's order. Filled once from priv/seed/items.json (the code catalogue as it was) the
  # first time the game reads it (BaconWorld.Items).
  use Ecto.Migration

  def change do
    create table(:bacon_world_item_defs, primary_key: false) do
      add :id, :string, primary_key: true
      add :data, :map, null: false, default: %{}
      add :position, :integer, null: false, default: 0
      timestamps(type: :utc_datetime)
    end
  end
end

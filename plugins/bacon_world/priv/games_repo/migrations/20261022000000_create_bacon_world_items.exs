defmodule BaconWorld.GamesRepo.Migrations.CreateBaconWorldItems do
  use Ecto.Migration

  @moduledoc """
  What Bacon World characters carry: one row per occupied slot (equipped in
  "main"/"off", or in a bag slot "bag0".."bag23"). Items themselves are a fixed
  catalogue in code (`BaconWorld.Items`); `item_id` is its key. Coins are a number
  in the character's `stats` ("coins", in copper).
  """

  def change do
    create table(:bacon_world_items, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :character_id, references(:game_characters, type: :binary_id, on_delete: :delete_all), null: false
      add :item_id, :string, null: false
      add :slot, :string, null: false
      add :quantity, :integer, null: false, default: 1
      timestamps(type: :utc_datetime)
    end

    create unique_index(:bacon_world_items, [:character_id, :slot])
  end
end

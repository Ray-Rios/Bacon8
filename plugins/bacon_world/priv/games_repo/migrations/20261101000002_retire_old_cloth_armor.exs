defmodule BaconWorld.GamesRepo.Migrations.RetireOldClothArmor do
  # 2026-11-01: the cloth armour was replaced by ten full sets and ten robes made as real garments
  # (BaconWorld.Items @armor_sets, @robes). Anything owned moves to the closest new piece.
  use Ecto.Migration

  @moves %{
    "cloth_tunic" => "wayfarer_chest",
    "blue_dyed_tunic" => "ranger_chest",
    "cloth_tank" => "corsair_chest",
    "wool_sweater" => "frost_chest",
    "cloth_trousers" => "wayfarer_legs",
    "cloth_shorts" => "corsair_legs",
    "cloth_shoes" => "wayfarer_feet",
    "leather_boots" => "ranger_feet",
    "linen_arm_wraps" => "wayfarer_wrist"
  }

  def up do
    for {from, to} <- @moves do
      execute("UPDATE bacon_world_items SET item_id = '#{to}' WHERE item_id = '#{from}'")
    end
  end

  def down, do: :ok
end

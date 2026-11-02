defmodule BaconWorld.GamesRepo.Migrations.RetireOldUnderwear do
  # 2026-11-01: the underwear was replaced by ten new sets (BaconWorld.Items @under). Items still
  # owned in a retired set move to the closest new one; the linen starter and Rose Lace keep their ids.
  use Ecto.Migration

  @moves %{
    "athletic_top" => "ranger_top",
    "athletic_bottom" => "ranger_bottom",
    "coral_top" => "twist_top",
    "coral_bottom" => "twist_bottom",
    "polka_dot_top" => "keyhole_top",
    "polka_dot_bottom" => "keyhole_bottom",
    "emerald_top" => "corset_top",
    "emerald_bottom" => "corset_bottom"
  }

  def up do
    for {from, to} <- @moves do
      execute("UPDATE bacon_world_items SET item_id = '#{to}' WHERE item_id = '#{from}'")
    end
  end

  def down, do: :ok
end

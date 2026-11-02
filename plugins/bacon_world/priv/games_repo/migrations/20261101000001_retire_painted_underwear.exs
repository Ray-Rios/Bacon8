defmodule BaconWorld.GamesRepo.Migrations.RetirePaintedUnderwear do
  # 2026-11-01 (second pass): the texture-painted underwear sets of the same morning were replaced
  # by ten sets made as real garments (BaconWorld.Items @under). Anything owned moves to the
  # closest new set; 20261101000000 ran first, so the 2026-10-23 sets arrive here already moved.
  use Ecto.Migration

  @moves %{
    "linen_bikini" => "homespun",
    "ranger" => "seafoam",
    "twist" => "brocade",
    "keyhole" => "nightweave",
    "corset" => "velvet",
    "rose_lace" => "thornrose",
    "crossfront" => "linen",
    "asymmetric" => "georgette",
    "dragonscale" => "moonsilk",
    "runic" => "waffle"
  }

  def up do
    for {from, to} <- @moves, part <- ~w(top bottom) do
      execute("UPDATE bacon_world_items SET item_id = '#{to}_#{part}' WHERE item_id = '#{from}_#{part}'")
    end
  end

  def down, do: :ok
end

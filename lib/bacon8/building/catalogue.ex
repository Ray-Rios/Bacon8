defmodule Bacon8.Building.Catalogue do
  @moduledoc """
  The models every game may place in build mode (2026-11-14, the owner: every game builds from
  Bacon World's catalogue): the village props (`P_<Id>`, `/models/World/B8_Props.glb`), sorted
  into trees and plants, rocks and the rest; the building kit's pieces (`K_<Id>`, `B8_BuildKit.glb`,
  a 3 m grid); and two made in Bacon World's code (`X_Plinth`, `X_RobinHat`). Each game adds its own
  kinds after these (Bacon World: creature spawns and NPCs), passing them to `Bacon8.Building`.

  An entry: `%{id, name, category, kind: "model", default_role, model, file}`, `model` the node in
  `file` (`"props"` or `"kit"`; nil for the code-made ones).
  """

  @props ~w(Amphora Anvil ArcheryTarget Banner Barrel BarrelSide BarrelWater Basket Bed Bedroll Bench Book
            Bookshelf Bottle Boulder BoulderGranite Bowl Brazier Bucket Bush BushFlowers Cabinet Campfire
            Candelabra Candle Cart Cauldron Chair Chest ClayPot CoinPile Crate CrateSmall CrateStack
            CrystalsBlue CrystalsGreen CrystalsPurple Desk FishingFish FoodBread FoodCheese FoodMeat
            FoodPumpkin Forge GemPile Goblet GrassTuft Haystack Jug Key LampPost LanternProp Lever Log
            LogCluster LogHollow LootBag MarketStall Mug Mushrooms OreDarkVein PebblesScatter PlateFood
            PotionBlue PotionGreen PotionRed PressurePlate Rock1 Rock2 Rock3 RockGraniteCluster RockMossy
            RockMossyCluster RopeCoil Rug Sack SackPile SaplingBirch SaplingOak SaplingPine Scarecrow Scroll
            SignHanging Signpost Skull Statue SteppingStones Stool Stump StumpHollow StumpMossy Table
            TableRound Tent Throne Tombstone TorchSconce TrainingDummy TreeBirch TreeBlossom TreeDead
            TreeEnchanted TreeOak TreePine TreeWillow Waystone WeaponRack Well Wheelbarrow Woodpile
            Workbench)
  @kit ~w(Arch_Brick Arch_Passageway_Stone Arch_Ruined_Stone Arch_Stone Arch_Stone_Ornate Arch_Wood_Rough
          Beam_Wood Chimney_Stone Door_Barn_Sliding Door_Cathedral_Arched Door_Gate_Double_Wood Door_Gate_Iron_Ornate
          Door_Iron_Studded Door_Jail_Heavy Door_Rustic_Wood Door_Wood Door_Wooden_Dilapidated Fence_Gate
          Fence_Stone Fence_Wood Floor_Brick_Herringbone Floor_Clay_Tile Floor_Cobblestone_Broken Floor_Cobblestone_Uneven
          Floor_Dirt_Flat Floor_Flagstone_Dungeon Floor_Flagstone_Mossy Floor_Forest_Leaves Floor_Grass_Fern_Lush
          Floor_Grass_Patchy Floor_Grate_Rusty_Iron Floor_Gravel_Mud Floor_Mud_Cracked Floor_Rug_Wood_Worn
          Floor_Sand_Desert Floor_Stone Floor_Stone_Path_Overgrown Floor_Stone_Paver_Fine Floor_Terracotta_Patterned
          Floor_Timber_Sturdy Floor_Wood Floor_Wood_Rotting Foundation_Stone Foundation_Wood Gate_Dungeon
          Gate_Wood Hatch_Cellar Ladder_Rope Ladder_Steep_Steps Ladder_Wood Ladder_Wood_Double Pillar_Stone
          Pillar_Wood Portcullis_Iron Railing_Wood Ramp_Stone_Heavy Ramp_Timber_Mud Ramp_Wood_Short Roof_Copper_Peak
          Roof_Flat Roof_Gable_Wood_Ornate Roof_Metal_Corrugated_Rusty Roof_Overgrown_Leafy Roof_Ridge
          Roof_Shingle Roof_Shingle_Damaged Roof_Shingle_Wood_Peak Roof_Shingle_Wood_Slope Roof_Slate_Mossy
          Roof_Slate_Slope Roof_Slate_Valley Roof_Stone_Flat_Parapet Roof_Thatch Roof_Thatch_Corner Roof_Thatch_Peak
          Roof_Thatch_Ruined Roof_Tile Roof_Tile_Red_Peak Roof_Tile_Red_Slope Scaffolding_Base Scaffolding_Extension
          Scaffolding_Platform_Ladder Shutters_Wood Stairs_Metal_Industrial Stairs_Spiral_Stone Stairs_Spiral_Wood
          Stairs_Stone Stairs_Stone_Basic Stairs_Stone_Chipped Stairs_Stone_Curved Stairs_Stone_Grand
          Stairs_Wood Stairs_Wood_Basic Wall_Ancient_Mossy Wall_Brick_Burnt_Red Wall_Brick_Fine_Red Wall_Brick_Industrial
          Wall_Cobblestone_Coarse Wall_Dry_Stone Wall_Granite_Rough Wall_Iron_Reinforced Wall_Log_Cabin_H
          Wall_Log_Corner_Angled Wall_Marble_Decorative Wall_Palisade_Vertical Wall_Plaster_Exposed_Brick
          Wall_Plaster_Stone_Base Wall_Plate_Rusting Wall_Ruin_Brick_Blasted Wall_Ruin_Stone_Crumbled
          Wall_Ruin_Timber_Collapsed Wall_Sandstone_Brick Wall_Stone Wall_Stone_Corner_Angled Wall_Stone_Curved
          Wall_Stone_Door Wall_Stone_Gable Wall_Stone_Gateway Wall_Stone_Half Wall_Stone_T_Junction Wall_Stone_Window
          Wall_Thatch_Mud Wall_Timber_Decayed Wall_Timber_Intact Wall_Timber_Tudor Wall_Wood Wall_Wood_Carved
          Wall_Wood_Door Wall_Wood_Gable Wall_Wood_Half Wall_Wood_Plank_H Wall_Wood_Rough Wall_Wood_Window
          Window_Arrow_Slit Window_Circular_Glass Window_Double_Pane Window_Glass Window_Leaded_Glass
          Window_Square_Small Window_Stained_Glass_Ornate Window_Standard_Glass)
  @plants ~w(Bush BushFlowers GrassTuft Mushrooms Stump StumpHollow StumpMossy Log LogHollow LogCluster
             TreeBirch TreeBlossom TreeDead TreeEnchanted TreeOak TreePine TreeWillow SaplingBirch
             SaplingOak SaplingPine Haystack)
  @rocks ~w(Boulder BoulderGranite Rock1 Rock2 Rock3 RockGraniteCluster RockMossy RockMossyCluster
            OreDarkVein CrystalsBlue CrystalsPurple CrystalsGreen PebblesScatter SteppingStones)
  # the waystone will be the binding stone (BACON_WORLD.md): admins only, like the bosses
  @admin_props ~w(Waystone)

  @doc """
  Tears of Babylon's own pieces (2026-11-25, the owner: the exploding barrels "will need to be rolled into the rest of
  the buildable objects"): the explosive barrel, drawn with the props' barrel and made to blow up by the game.
  """
  def tears_of_babylon do
    [%{id: "X_ExplosiveBarrel", name: "Explosive barrel", category: "Props", kind: "model", default_role: "member", model: "Barrel", file: "props"}]
  end

  @doc "The shared models, props then building pieces."
  def models do
    props =
      for p <- @props do
        category =
          cond do
            p in @plants -> "Trees & plants"
            p in @rocks -> "Rocks"
            true -> "Props"
          end

        %{id: "P_" <> p, name: words(p), category: category, kind: "model", default_role: if(p in @admin_props, do: "admin", else: "member"), model: "P_" <> p, file: "props"}
      end

    kit = for k <- @kit, do: %{id: "K_" <> k, name: k |> String.replace("_", " ") |> words(), category: "Building", kind: "model", default_role: "member", model: "K_" <> k, file: "kit"}

    props ++
      kit ++
      [
        # the stone plinth the village's houses stand on (world-dressing.ts makes it; no file of its own)
        %{id: "X_Plinth", name: "Stone plinth", category: "Building", kind: "model", default_role: "member", model: "X_Plinth", file: nil},
        # the Robin Hood hat (2026-10-29), made in code (crafted.ts) like the plinth
        %{id: "X_RobinHat", name: "Robin Hood hat", category: "Props", kind: "model", default_role: "member", model: "X_RobinHat", file: nil}
      ]
  end

  @doc "\"TreeOak\" -> \"Tree oak\"."
  def words(s) do
    s
    |> String.replace(~r/([a-z])([A-Z0-9])/, "\\1 \\2")
    |> String.downcase()
    |> cap()
  end

  @doc "The first letter upper case."
  def cap(<<c::utf8, rest::binary>>), do: String.upcase(<<c::utf8>>) <> rest
  def cap(s), do: s
end

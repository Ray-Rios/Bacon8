defmodule BaconWorld.Items do
  @moduledoc """
  Every item in Bacon World: a fixed catalogue, in code. Characters' copies are
  rows in `bacon_world_items` (`BaconWorld.Inventory`).

  Weapons read like EverQuest's: **DMG** is the most one hit does before bonuses,
  **DLY** the time between swings in tenths of a second, so a DMG 6 DLY 12 sword
  swings every 1.2 s. Each weapon is drawn with a model from
  `/models/Weapons/B8_Weapons.glb` (node `W_<model>`, icon
  `Weapons/icons/W_<model>.png`) and animated with an animation set from the B8
  packs (`anims.json` "sets": `sword_1h`, `two_hand`, ...).

  Clothes are items too: underwear (`"under_top"`, `"under_bottom"`) and cloth armour
  (`"chest"`, `"legs"`, `"feet"`). A worn item is drawn on the character: `wear` says
  which garment of each body model shows it and, for the garments made from the body,
  which design (`Humans/Wardrobe/<garment>__<design>.webp`); `colors` tints it (`main`,
  `trim`, `accent`; shoes use `upper`, `sole` and `laces`). Characters start in the
  linen set; Tilda the clothier sells the rest (`BaconWorld.Merchants`).

  Fields:

    * `id`, `name`
    * `kind` - `"weapon"`, `"shield"`, `"light"`, `"armor"` or `"junk"`
    * `slots` - where it can be equipped: `"main"` (right hand), `"off"` (left), or a
      worn slot (`"under_top"`, `"under_bottom"`, `"chest"`, `"legs"`, `"feet"`)
    * `hands` - 2 for two-handed weapons, which need the off hand empty
    * `set` - the animation set it is held and swung with
    * `skill` - EverQuest's weapon skill line, shown on the item
    * `dmg`, `dly`, `reach` (metres, from the grip), `ac` (shields)
    * `stack` - how many fit in one slot; `value` - in copper
    * `model` - the weapon model, or nil (the icon then comes from `icon`)
    * `icon_url` - an icon of its own (the plugin's `priv/static/icons`), for items without a model
      or weapon icon on the models volume (fishing, 2026-10-26)
    * `wear`, `colors` - how a worn item is drawn (above)
  """

  @fist %{id: "fist", name: "Fist", kind: "weapon", slots: [], hands: 1, set: "unarmed", skill: "Hand to Hand", dmg: 3, dly: 9, reach: 0.75, ac: 0, stack: 1, value: 0, model: nil, icon: nil}

  @items [
    # The starter kit: every new character gets these once.
    %{id: "worn_short_sword", name: "Worn Short Sword", kind: "weapon", slots: ["main", "off"], hands: 1, set: "sword_1h", skill: "1H Slashing", dmg: 6, dly: 12, reach: 0.95, model: "Sword", value: 8},
    %{id: "worn_dagger", name: "Worn Dagger", kind: "weapon", slots: ["main", "off"], hands: 1, set: "dagger", skill: "Piercing", dmg: 4, dly: 8, reach: 0.5, model: "Dagger", value: 5},
    %{id: "worn_club", name: "Worn Club", kind: "weapon", slots: ["main", "off"], hands: 1, set: "blunt_1h", skill: "1H Blunt", dmg: 6, dly: 13, reach: 0.85, model: "Club", value: 4},
    %{id: "worn_spear", name: "Worn Spear", kind: "weapon", slots: ["main"], hands: 2, set: "polearm", skill: "2H Piercing", dmg: 11, dly: 17, reach: 1.9, model: "Spear", value: 10},
    %{id: "worn_quarterstaff", name: "Worn Quarterstaff", kind: "weapon", slots: ["main"], hands: 2, set: "staff", skill: "2H Blunt", dmg: 10, dly: 16, reach: 1.6, model: "Quarterstaff", value: 6},
    %{id: "worn_round_shield", name: "Worn Round Shield", kind: "shield", slots: ["off"], hands: 1, set: "shield", skill: "Bash", dmg: 3, dly: 14, reach: 0.6, ac: 4, model: "RoundShield", value: 8},
    %{id: "torch", name: "Torch", kind: "light", slots: ["off"], hands: 1, set: "torch", skill: "1H Blunt", dmg: 3, dly: 12, reach: 0.6, model: "Torch", value: 2},

    # What skeletons carry (and drop).
    %{id: "rusty_short_sword", name: "Rusty Short Sword", kind: "weapon", slots: ["main", "off"], hands: 1, set: "sword_1h", skill: "1H Slashing", dmg: 7, dly: 12, reach: 0.95, model: "Sword", value: 14},
    %{id: "rusty_scimitar", name: "Rusty Scimitar", kind: "weapon", slots: ["main", "off"], hands: 1, set: "sword_1h", skill: "1H Slashing", dmg: 8, dly: 13, reach: 0.9, model: "Scimitar", value: 16},
    %{id: "rusty_cutlass", name: "Rusty Cutlass", kind: "weapon", slots: ["main", "off"], hands: 1, set: "sword_1h", skill: "1H Slashing", dmg: 7, dly: 11, reach: 0.85, model: "Cutlass", value: 15},
    %{id: "rusty_hand_axe", name: "Rusty Hand Axe", kind: "weapon", slots: ["main", "off"], hands: 1, set: "axe_1h", skill: "1H Slashing", dmg: 8, dly: 13, reach: 0.7, model: "Axe", value: 15},
    %{id: "rusty_dagger", name: "Rusty Dagger", kind: "weapon", slots: ["main", "off"], hands: 1, set: "dagger", skill: "Piercing", dmg: 5, dly: 8, reach: 0.5, model: "Dagger", value: 9},
    %{id: "bone_club", name: "Bone Club", kind: "weapon", slots: ["main", "off"], hands: 1, set: "blunt_1h", skill: "1H Blunt", dmg: 7, dly: 12, reach: 0.85, model: "Club", value: 6},
    %{id: "dented_mace", name: "Dented Mace", kind: "weapon", slots: ["main", "off"], hands: 1, set: "blunt_1h", skill: "1H Blunt", dmg: 8, dly: 13, reach: 0.8, model: "Mace", value: 18},
    %{id: "cracked_morning_star", name: "Cracked Morning Star", kind: "weapon", slots: ["main", "off"], hands: 1, set: "blunt_1h", skill: "1H Blunt", dmg: 9, dly: 14, reach: 0.85, model: "MorningStar", value: 22},
    %{id: "pitted_war_hammer", name: "Pitted War Hammer", kind: "weapon", slots: ["main", "off"], hands: 1, set: "blunt_1h", skill: "1H Blunt", dmg: 9, dly: 14, reach: 0.8, model: "WarHammer", value: 20},
    %{id: "pitted_longsword", name: "Pitted Longsword", kind: "weapon", slots: ["main", "off"], hands: 1, set: "sword_1h", skill: "1H Slashing", dmg: 10, dly: 13, reach: 1.15, model: "Longsword", value: 40},
    %{id: "rusty_two_handed_sword", name: "Rusty Two-Handed Sword", kind: "weapon", slots: ["main"], hands: 2, set: "two_hand", skill: "2H Slashing", dmg: 15, dly: 19, reach: 1.5, model: "Greatsword", value: 30},
    %{id: "notched_battle_axe", name: "Notched Battle Axe", kind: "weapon", slots: ["main"], hands: 2, set: "two_hand", skill: "2H Slashing", dmg: 16, dly: 20, reach: 1.25, model: "BattleAxe", value: 32},
    %{id: "cracked_maul", name: "Cracked Maul", kind: "weapon", slots: ["main"], hands: 2, set: "two_hand", skill: "2H Blunt", dmg: 16, dly: 21, reach: 1.2, model: "Maul", value: 28},
    %{id: "splintered_spear", name: "Splintered Spear", kind: "weapon", slots: ["main"], hands: 2, set: "polearm", skill: "2H Piercing", dmg: 12, dly: 17, reach: 1.9, model: "Spear", value: 18},
    %{id: "rusty_halberd", name: "Rusty Halberd", kind: "weapon", slots: ["main"], hands: 2, set: "polearm", skill: "2H Slashing", dmg: 15, dly: 20, reach: 2.0, model: "Halberd", value: 34},
    %{id: "dented_buckler", name: "Dented Buckler", kind: "shield", slots: ["off"], hands: 1, set: "shield", skill: "Bash", dmg: 3, dly: 12, reach: 0.55, ac: 3, model: "Buckler", value: 10},
    %{id: "cracked_kite_shield", name: "Cracked Kite Shield", kind: "shield", slots: ["off"], hands: 1, set: "shield", skill: "Bash", dmg: 4, dly: 15, reach: 0.6, ac: 6, model: "KiteShield", value: 24},

    # Junk, for selling one day (EverQuest's bone chips).
    %{id: "bone_chips", name: "Bone Chips", kind: "junk", slots: [], hands: 1, set: nil, skill: nil, dmg: 0, dly: 0, reach: 0, stack: 20, model: nil, icon: "Bone", value: 1},
    %{id: "skull_fragment", name: "Skull Fragment", kind: "junk", slots: [], hands: 1, set: nil, skill: nil, dmg: 0, dly: 0, reach: 0, stack: 20, model: nil, icon: "Skull", value: 2},

    # Baconator's hoard (2026-10-24): its scales and fangs sell well; the weapons are the
    # best in the game so far.
    %{id: "dragon_scale", name: "Dragon Scale", kind: "junk", slots: [], hands: 1, set: nil, skill: nil, dmg: 0, dly: 0, reach: 0, stack: 20, model: nil, icon: "DragonScale", value: 250},
    %{id: "baconator_fang", name: "Baconator's Fang", kind: "junk", slots: [], hands: 1, set: nil, skill: nil, dmg: 0, dly: 0, reach: 0, stack: 5, model: nil, icon: "DragonFang", value: 1500},
    %{id: "emberforged_longsword", name: "Emberforged Longsword", kind: "weapon", slots: ["main", "off"], hands: 1, set: "sword_1h", skill: "1H Slashing", dmg: 15, dly: 13, reach: 1.15, model: "Longsword", value: 2400},
    %{id: "dragonbone_greataxe", name: "Dragonbone Greataxe", kind: "weapon", slots: ["main"], hands: 2, set: "two_hand", skill: "2H Slashing", dmg: 24, dly: 21, reach: 1.3, model: "BattleAxe", value: 3200},
    %{id: "scaleplate_shield", name: "Scaleplate Shield", kind: "shield", slots: ["off"], hands: 1, set: "shield", skill: "Bash", dmg: 5, dly: 14, reach: 0.6, ac: 11, model: "KiteShield", value: 2000},

    # Fishing (2026-10-26, BaconWorld.Water): the pole is held two-handed and cast at the water
    # (BaconWorldWeb.FishingEvents); what bites goes in the bags and sells to any merchant. Icons
    # are the plugin's own (priv/static/icons, rendered by library/pipeline/scripts/fishing_icons.py).
    %{id: "fishing_pole", name: "Fishing Pole", kind: "weapon", slots: ["main"], hands: 2, set: "staff", skill: "Fishing", dmg: 1, dly: 30, reach: 1.0, model: "FishingPole", value: 30, icon_url: "/plugins/bacon_world/icons/fishing_pole.png"},
    %{id: "pond_perch", name: "Pond Perch", kind: "junk", slots: [], hands: 1, set: nil, skill: nil, dmg: 0, dly: 0, reach: 0, stack: 20, model: nil, icon_url: "/plugins/bacon_world/icons/pond_perch.png", value: 3},
    %{id: "brook_trout", name: "Brook Trout", kind: "junk", slots: [], hands: 1, set: nil, skill: nil, dmg: 0, dly: 0, reach: 0, stack: 20, model: nil, icon_url: "/plugins/bacon_world/icons/brook_trout.png", value: 6},
    %{id: "mud_carp", name: "Mud Carp", kind: "junk", slots: [], hands: 1, set: nil, skill: nil, dmg: 0, dly: 0, reach: 0, stack: 20, model: nil, icon_url: "/plugins/bacon_world/icons/mud_carp.png", value: 4},
    %{id: "golden_carp", name: "Golden Carp", kind: "junk", slots: [], hands: 1, set: nil, skill: nil, dmg: 0, dly: 0, reach: 0, stack: 20, model: nil, icon_url: "/plugins/bacon_world/icons/golden_carp.png", value: 120},
    %{id: "old_boot", name: "Old Boot", kind: "junk", slots: [], hands: 1, set: nil, skill: nil, dmg: 0, dly: 0, reach: 0, stack: 20, model: nil, icon_url: "/plugins/bacon_world/icons/old_boot.png", value: 1},
    %{id: "sea_mackerel", name: "Sea Mackerel", kind: "junk", slots: [], hands: 1, set: nil, skill: nil, dmg: 0, dly: 0, reach: 0, stack: 20, model: nil, icon_url: "/plugins/bacon_world/icons/sea_mackerel.png", value: 4},
    %{id: "striped_bass", name: "Striped Bass", kind: "junk", slots: [], hands: 1, set: nil, skill: nil, dmg: 0, dly: 0, reach: 0, stack: 20, model: nil, icon_url: "/plugins/bacon_world/icons/striped_bass.png", value: 8},
    %{id: "red_snapper", name: "Red Snapper", kind: "junk", slots: [], hands: 1, set: nil, skill: nil, dmg: 0, dly: 0, reach: 0, stack: 20, model: nil, icon_url: "/plugins/bacon_world/icons/red_snapper.png", value: 12},
    %{id: "silver_tuna", name: "Silver Tuna", kind: "junk", slots: [], hands: 1, set: nil, skill: nil, dmg: 0, dly: 0, reach: 0, stack: 20, model: nil, icon_url: "/plugins/bacon_world/icons/silver_tuna.png", value: 90},
    %{id: "tangle_of_kelp", name: "Tangle of Kelp", kind: "junk", slots: [], hands: 1, set: nil, skill: nil, dmg: 0, dly: 0, reach: 0, stack: 20, model: nil, icon_url: "/plugins/bacon_world/icons/tangle_of_kelp.png", value: 1}
  ]

  # What can be worn. Underwear: six sets (top and bottom are separate items), the
  # linen one given to every character. The male (MakeHuman, 2026-10-23) wears no top; his
  # bottoms are his own Under_Bottom shell in briefs or boxer briefs (@male_bottom).
  @under [
    {"linen_bikini", "Linen Bikini", {"classic", "classic"}, {"#EAE0C8", "#D2C3A3", "#D2C3A3"}, 20, {"Top", "Bottom"}},
    {"athletic", "Athletic", {"sport", "boyshort"}, {"#2E3138", "#1F8A8A", "#E7F1FD"}, 60, {"Top", "Shorts"}},
    {"rose_lace", "Rose Lace", {"lace", "lace"}, {"#E2AFA6", "#B9776E", "#F7DDD7"}, 90, {"Bralette", "Briefs"}},
    {"coral", "Coral", {"bandeau", "highcut"}, {"#E0644E", "#FFFFFF", "#B8402F"}, 70, {"Bandeau", "High-Cut Bottom"}},
    {"polka_dot", "Polka Dot", {"halter", "string"}, {"#1E2E5C", "#F4F4F4", "#F4F4F4"}, 80, {"Halter Top", "Tie-Side Bottom"}},
    {"emerald", "Emerald", {"longline", "highwaist"}, {"#1F6B4A", "#D6A92B", "#D6A92B"}, 120, {"Longline Top", "High-Waist Bottom"}}
  ]
  @band_tops ~w(sport bandeau longline)
  # the male's cut for each of her bottom designs
  @male_bottom %{"classic" => "classic", "lace" => "classic", "boyshort" => "boyshort", "highcut" => "classic",
                 "string" => "classic", "highwaist" => "boyshort"}

  @underwear Enum.flat_map(@under, fn {id, name, {top, bottom}, {main, trim, accent}, value, {tn, bn}} ->
               colors = %{"main" => main, "trim" => trim, "accent" => accent}
               top_garment = if top in @band_tops, do: "Under_Top_Band", else: "Under_Top_Contour"

               [
                 %{id: "#{id}_top", name: "#{name} #{tn}", kind: "armor", slots: ["under_top"], value: value, colors: colors,
                   wear: %{"female" => %{"garment" => top_garment, "design" => top}, "male" => nil}},
                 %{id: "#{id}_bottom", name: "#{name} #{bn}", kind: "armor", slots: ["under_bottom"], value: value, colors: colors,
                   wear: %{"female" => %{"garment" => "Under_Bottom", "design" => bottom}, "male" => %{"garment" => "Under_Bottom", "design" => @male_bottom[bottom]}}}
               ]
             end)

  # Cloth armour: the same garments and designs on both bodies (each body has its own textures).
  @cloth [
    %{id: "cloth_tunic", name: "Cloth Tunic", slots: ["chest"], ac: 2, value: 40, garment: "Top_Tee", colors: %{"main" => "#8A6A4A", "trim" => "#5C4630"}},
    %{id: "blue_dyed_tunic", name: "Blue Dyed Tunic", slots: ["chest"], ac: 2, value: 60, garment: "Top_Tee", colors: %{"main" => "#247DF1", "trim" => "#1B5FBA"}},
    %{id: "cloth_tank", name: "Cloth Tank Top", slots: ["chest"], ac: 1, value: 30, garment: "Top_Tank", design: "tank", colors: %{"main" => "#E7F1FD", "trim" => "#9AA3AD", "accent" => "#C8D2DC"}},
    %{id: "wool_sweater", name: "Wool Sweater", slots: ["chest"], ac: 3, value: 90, garment: "Top_LongSleeve", colors: %{"main" => "#6B7A35", "trim" => "#4F5A27"}},
    %{id: "cloth_trousers", name: "Cloth Trousers", slots: ["legs"], ac: 2, value: 50, garment: "Bottom_Pants", design: "pants", colors: %{"main" => "#4A4F57", "trim" => "#2B2F36", "accent" => "#2B2F36"}},
    %{id: "cloth_shorts", name: "Cloth Shorts", slots: ["legs"], ac: 1, value: 30, garment: "Bottom_Shorts", design: "shorts", colors: %{"main" => "#1E2E5C", "trim" => "#14203F", "accent" => "#14203F"}},
    %{id: "cloth_shoes", name: "Cloth Shoes", slots: ["feet"], ac: 1, value: 25, garment: "Shoes_Sneakers", colors: %{"upper" => "#3A3F47", "sole" => "#F4F4F4", "laces" => "#E8E8E8"}},
    %{id: "leather_boots", name: "Tall Leather Boots", slots: ["feet"], ac: 3, value: 150, garment: "Shoes_Boots", colors: %{"upper" => "#6B4A2F", "sole" => "#2A2522", "laces" => "#3D2B1F"}}
  ]

  @wearables @underwear ++
               Enum.map(@cloth, fn c ->
                 female = %{"garment" => c.garment} |> then(&if(c[:design], do: Map.put(&1, "design", c.design), else: &1))

                 c
                 |> Map.drop([:garment, :design])
                 |> Map.merge(%{kind: "armor", wear: %{"female" => female, "male" => female}})
               end)

  @wear_slots ~w(under_top under_bottom chest legs feet)

  @armor_defaults %{hands: 1, set: nil, skill: nil, dmg: 0, dly: 0, reach: 0, ac: 0, stack: 1, model: nil, icon: nil, icon_url: nil}

  @defaults %{ac: 0, stack: 1, icon: nil, icon_url: nil, wear: nil, colors: nil}
  @by_id Map.new(@items, fn i -> {i.id, Map.merge(@defaults, i)} end)
         |> Map.merge(Map.new(@wearables, fn i -> {i.id, @defaults |> Map.merge(@armor_defaults) |> Map.merge(i)} end))

  @starter_wear [{"linen_bikini_top", "under_top"}, {"linen_bikini_bottom", "under_bottom"}]

  @starter_kit [
    {"worn_short_sword", "main"},
    {"worn_round_shield", nil},
    {"worn_dagger", nil},
    {"worn_club", nil},
    {"worn_spear", nil},
    {"worn_quarterstaff", nil},
    {"torch", nil}
  ]

  @doc "All items, as maps."
  def all, do: Map.values(@by_id)

  @doc "An item by id, or nil."
  def get(id) when is_binary(id), do: Map.get(@by_id, id)
  def get(_), do: nil

  @doc "What an empty hand swings with."
  def fist, do: @fist

  @doc "The starter kit, as `{item_id, slot or nil (first free bag slot)}`."
  def starter_kit, do: @starter_kit

  @doc "What every character starts out wearing, as `{item_id, slot}`."
  def starter_wear, do: @starter_wear

  @doc "The slots worn items go in (besides the hands)."
  def wear_slots, do: @wear_slots

  @doc "True for an item that is worn (underwear, cloth armour)."
  def wearable?(%{kind: "armor"}), do: true
  def wearable?(_), do: false

  @doc "True when `item` may go in equipment slot `slot` (a hand or a worn slot)."
  def equippable?(%{slots: slots}, slot), do: slot in slots
  def equippable?(_, _), do: false

  def two_handed?(%{hands: 2}), do: true
  def two_handed?(_), do: false

  @doc "What the 3D client needs about every item (no secrets here: it is all shown in tooltips)."
  def catalog_payload do
    Map.new(all(), fn i ->
      {i.id,
       %{
         name: i.name,
         kind: i.kind,
         slots: i.slots,
         hands: i.hands,
         set: i.set,
         skill: i.skill,
         dmg: i.dmg,
         dly: i.dly,
         reach: i.reach,
         ac: i.ac,
         stack: i.stack,
         value: i.value,
         model: i.model,
         icon: i.model || i.icon,
         icon_path: icon_path(i),
         # a picture of its own (the plugin's static files), instead of the models volume's
         icon_url: i.icon_url,
         wear: i.wear,
         colors: i.colors
       }}
    end)
  end

  # Where the inventory icon is, under /models.
  defp icon_path(%{kind: "armor", id: id}), do: "Humans/Wardrobe/icons/#{id}.png"
  defp icon_path(%{model: m}) when is_binary(m), do: "Weapons/icons/W_#{m}.png"
  defp icon_path(%{icon: i}) when is_binary(i), do: "Weapons/icons/W_#{i}.png"
  defp icon_path(_), do: nil
end

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

  Fields:

    * `id`, `name`
    * `kind` - `"weapon"`, `"shield"`, `"light"` or `"junk"`
    * `slots` - where it can be equipped: `"main"` (right hand), `"off"` (left)
    * `hands` - 2 for two-handed weapons, which need the off hand empty
    * `set` - the animation set it is held and swung with
    * `skill` - EverQuest's weapon skill line, shown on the item
    * `dmg`, `dly`, `reach` (metres, from the grip), `ac` (shields)
    * `stack` - how many fit in one slot; `value` - in copper
    * `model` - the weapon model, or nil (the icon then comes from `icon`)
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
    %{id: "skull_fragment", name: "Skull Fragment", kind: "junk", slots: [], hands: 1, set: nil, skill: nil, dmg: 0, dly: 0, reach: 0, stack: 20, model: nil, icon: "Skull", value: 2}
  ]

  @defaults %{ac: 0, stack: 1, icon: nil}
  @by_id Map.new(@items, fn i -> {i.id, Map.merge(@defaults, i)} end)

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

  @doc "True when `item` may go in equipment slot `slot` (\"main\" or \"off\")."
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
         icon: i.model || i.icon
       }}
    end)
  end
end

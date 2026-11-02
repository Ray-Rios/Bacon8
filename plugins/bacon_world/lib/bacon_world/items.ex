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

  Clothes are items too: underwear (`"under_top"`, `"under_bottom"`), cloth armour
  (`"head"`, `"hands"`, `"arms"`, `"wrist"`, `"chest"`, `"legs"`, `"feet"`) and robes (`"chest"`). A worn item is drawn on the character: `wear` says
  which garment of each body model shows it and, for the garments made from the body,
  which design (`Humans/Wardrobe/<garment>__<design>.webp`); `colors` tints it (`main`,
  `trim`, `accent`; shoes use `upper`, `sole` and `laces`). Characters start in the
  linen set; Tilda the clothier sells the rest (`BaconWorld.Merchants`).

  Fields:

    * `id`, `name`
    * `kind` - `"weapon"`, `"shield"`, `"light"`, `"armor"` or `"junk"`
    * `slots` - where it can be equipped: `"main"` (right hand), `"off"` (left), or a
      worn slot (`"head"`, `"under_top"`, `"under_bottom"`, `"chest"`, `"legs"`, `"feet"`)
    * `hands` - 2 for two-handed weapons, which need the off hand empty
    * `set` - the animation set it is held and swung with
    * `skill` - EverQuest's weapon skill line, shown on the item
    * `dmg`, `dly`, `reach` (metres, from the grip), `ac` (shields)
    * `stack` - how many fit in one slot; `value` - in copper
    * `model` - the weapon model, or nil (the icon then comes from `icon`)
    * `icon_url` - an icon of its own (the plugin's `priv/static/icons`), for items without a model
      or weapon icon on the models volume (fishing, 2026-10-26)
    * `wear`, `colors` - how a worn item is drawn (above)
    * `ranged` - a bow (2026-10-28): shoots endless arrows out to `reach` (`BaconWorld.Melee`)
  """

  @fist %{id: "fist", name: "Fist", kind: "weapon", slots: [], hands: 1, set: "unarmed", skill: "Hand to Hand", dmg: 3, dly: 9, reach: 0.75, ac: 0, stack: 1, value: 0, model: nil, icon: nil}

  @items [
    # The starter kit: every new character gets these once.
    %{id: "worn_short_sword", name: "Worn Short Sword", kind: "weapon", slots: ["main", "off"], hands: 1, set: "sword_1h", skill: "1H Slashing", dmg: 6, dly: 12, reach: 0.95, model: "Sword", value: 8},
    %{id: "worn_dagger", name: "Worn Dagger", kind: "weapon", slots: ["main", "off"], hands: 1, set: "dagger", skill: "Piercing", dmg: 4, dly: 8, reach: 0.5, model: "Dagger", value: 5},
    # the starter piercing weapon (2026-10-29): the site's grill fork, drawn in code (crafted.ts)
    %{id: "grill_fork", name: "Grill Fork", kind: "weapon", slots: ["main", "off"], hands: 1, set: "dagger", skill: "Piercing", dmg: 4, dly: 8, reach: 0.6, model: "GrillFork", value: 5,
      icon_url: "/plugins/bacon_world/icons/grill_fork.png"},
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
    # The Kraken's (2026-10-27): what it leaves, and what it sometimes held in its arms. Icons are the
    # plugin's own (priv/static/icons, rendered from the model by library/pipeline/scripts/kraken_icons.py).
    %{id: "kraken_ink_sac", name: "Kraken Ink Sac", kind: "junk", slots: [], hands: 1, set: nil, skill: nil, dmg: 0, dly: 0, reach: 0, stack: 10, model: nil, icon_url: "/plugins/bacon_world/icons/kraken_ink_sac.png", value: 300},
    %{id: "abyssal_hook", name: "Abyssal Hook", kind: "junk", slots: [], hands: 1, set: nil, skill: nil, dmg: 0, dly: 0, reach: 0, stack: 20, model: nil, icon_url: "/plugins/bacon_world/icons/abyssal_hook.png", value: 220},
    %{id: "kraken_beak", name: "Kraken Beak", kind: "junk", slots: [], hands: 1, set: nil, skill: nil, dmg: 0, dly: 0, reach: 0, stack: 5, model: nil, icon_url: "/plugins/bacon_world/icons/kraken_beak.png", value: 2500},
    %{id: "abyssal_harpoon", name: "Abyssal Harpoon", kind: "weapon", slots: ["main"], hands: 2, set: "polearm", skill: "2H Piercing", dmg: 26, dly: 19, reach: 2.0, model: "Spear", value: 3400},
    %{id: "krakenfang_cutlass", name: "Krakenfang Cutlass", kind: "weapon", slots: ["main", "off"], hands: 1, set: "sword_1h", skill: "1H Slashing", dmg: 16, dly: 12, reach: 1.0, model: "Cutlass", value: 2800},
    %{id: "barnacled_buckler", name: "Barnacled Buckler", kind: "shield", slots: ["off"], hands: 1, set: "shield", skill: "Bash", dmg: 5, dly: 13, reach: 0.6, ac: 12, model: "Buckler", value: 2300},

    # Bows (2026-10-28): two-handed, held in the left hand, and they never run out of arrows (the
    # owner: "I don't want to deal with arrows"). `ranged`: one arrow at whatever is in a narrow
    # cone along where the archer looks, out to `reach` (BaconWorld.Melee). Drawn in code
    # (items.ts PROCEDURAL), with the library's Bow_* clips. Old Bram sells the hunting bow; goblin
    # archers carry the short bow; orc chieftains sometimes the longbow.
    %{id: "hunting_bow", name: "Hunting Bow", kind: "weapon", slots: ["main"], hands: 2, set: "bow", skill: "Archery", dmg: 9, dly: 16, reach: 32.0, model: "Bow", ranged: true, value: 60, icon_url: "/plugins/bacon_world/icons/hunting_bow.png"},
    %{id: "goblin_shortbow", name: "Goblin Short Bow", kind: "weapon", slots: ["main"], hands: 2, set: "bow", skill: "Archery", dmg: 8, dly: 15, reach: 26.0, model: "ShortBow", ranged: true, value: 35, icon_url: "/plugins/bacon_world/icons/goblin_shortbow.png"},
    %{id: "ashwood_longbow", name: "Ashwood Longbow", kind: "weapon", slots: ["main"], hands: 2, set: "bow", skill: "Archery", dmg: 14, dly: 18, reach: 38.0, model: "Longbow", ranged: true, value: 420, icon_url: "/plugins/bacon_world/icons/ashwood_longbow.png"},

    # What the rats, goblins and orcs leave (2026-10-28).
    %{id: "rat_tail", name: "Rat Tail", kind: "junk", slots: [], hands: 1, set: nil, skill: nil, dmg: 0, dly: 0, reach: 0, stack: 20, model: nil, icon_url: "/plugins/bacon_world/icons/rat_tail.png", value: 1},
    %{id: "rat_pelt", name: "Rat Pelt", kind: "junk", slots: [], hands: 1, set: nil, skill: nil, dmg: 0, dly: 0, reach: 0, stack: 20, model: nil, icon_url: "/plugins/bacon_world/icons/rat_pelt.png", value: 3},
    %{id: "goblin_ear", name: "Goblin Ear", kind: "junk", slots: [], hands: 1, set: nil, skill: nil, dmg: 0, dly: 0, reach: 0, stack: 20, model: nil, icon_url: "/plugins/bacon_world/icons/goblin_ear.png", value: 4},
    %{id: "tarnished_trinket", name: "Tarnished Trinket", kind: "junk", slots: [], hands: 1, set: nil, skill: nil, dmg: 0, dly: 0, reach: 0, stack: 10, model: nil, icon_url: "/plugins/bacon_world/icons/tarnished_trinket.png", value: 25},
    %{id: "orc_tusk", name: "Orc Tusk", kind: "junk", slots: [], hands: 1, set: nil, skill: nil, dmg: 0, dly: 0, reach: 0, stack: 20, model: nil, icon_url: "/plugins/bacon_world/icons/orc_tusk.png", value: 12},
    %{id: "orcish_war_belt", name: "Orcish War Belt", kind: "junk", slots: [], hands: 1, set: nil, skill: nil, dmg: 0, dly: 0, reach: 0, stack: 5, model: nil, icon_url: "/plugins/bacon_world/icons/orcish_war_belt.png", value: 60},
    # what orcs swing (and drop): heavier than the skeletons' rusty iron
    %{id: "orcish_cleaver", name: "Orcish Cleaver", kind: "weapon", slots: ["main", "off"], hands: 1, set: "axe_1h", skill: "1H Slashing", dmg: 11, dly: 14, reach: 0.75, model: "Axe", value: 45},
    %{id: "orcish_greataxe", name: "Orcish Greataxe", kind: "weapon", slots: ["main"], hands: 2, set: "two_hand", skill: "2H Slashing", dmg: 19, dly: 21, reach: 1.25, model: "BattleAxe", value: 90},
    %{id: "spiked_club", name: "Spiked Club", kind: "weapon", slots: ["main", "off"], hands: 1, set: "blunt_1h", skill: "1H Blunt", dmg: 9, dly: 13, reach: 0.85, model: "MorningStar", value: 20},

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
    %{id: "tangle_of_kelp", name: "Tangle of Kelp", kind: "junk", slots: [], hands: 1, set: nil, skill: nil, dmg: 0, dly: 0, reach: 0, stack: 20, model: nil, icon_url: "/plugins/bacon_world/icons/tangle_of_kelp.png", value: 1},

    # The first hat (2026-10-29): the site's Robin Hood hat, worn in the head slot on the head bone
    # (crafted.ts wearHat), sold by Tilda. Also placeable in build mode (X_RobinHat).
    %{id: "robin_hood_hat", name: "Robin Hood Hat", kind: "armor", slots: ["head"], hands: 1, set: nil, skill: nil, dmg: 0, dly: 0, reach: 0, ac: 1, value: 75, model: "RobinHat",
      icon_url: "/plugins/bacon_world/icons/robin_hood_hat.png"}
  ]

  # The metal bikinis (2026-11-01, Gemini's chain and plate sets): worth more than cloth, and a
  # little armour. Copper value and AC by set; the cloth sets keep 6c and none.
  @under_value %{"chain_iron" => 40, "chain_brass" => 60, "chain_steel" => 80, "chain_gold" => 150,
                 "plate_steel" => 120, "plate_dark" => 200, "plate_gold" => 220, "plate_draconic" => 260, "plate_mythril" => 300}
  @under_ac %{"chain_iron" => 1, "chain_brass" => 1, "chain_steel" => 1, "chain_gold" => 1,
              "plate_steel" => 2, "plate_dark" => 2, "plate_gold" => 2, "plate_draconic" => 2, "plate_mythril" => 2}

  # What can be worn. Underwear (2026-11-01, second pass; owner: "photo-realistic"): ten sets made
  # as real garments, each its own GLB per body (Humans/Garments/<Body>/uw_<set>_top|bottom.glb,
  # library/pipeline/scripts/b8_garments.py + b8_garment_designs.py) in photographed CC0 fabrics
  # (Humans/Fabrics): the cotton starter every character gets and nine more Tilda sells, 6 copper
  # a piece. The female wears top and bottom; the male the bottom only, in his own cut. The
  # texture-painted sets of the same morning are retired (games migration 20261101000001).
  @under [
    {"homespun", "Homespun", {"Bralette", "Briefs"}, %{"main" => "#E8DFCB", "trim" => "#D9CBAE"}},
    {"moonsilk", "Moonsilk", {"Balconette", "Bottoms"}, %{"main" => "#1E2340", "trim" => "#2A3156", "accent" => "#C9C3D9"}},
    {"thornrose", "Thornrose", {"Lace Plunge", "Lace Bottoms"}, %{"main" => "#2B0E14", "trim" => "#4A0F1C"}},
    {"velvet", "Velvet Court", {"Bustier", "Bottoms"}, %{"main" => "#4B1030", "trim" => "#2A0A1C"}},
    {"nightweave", "Nightweave", {"Cage Top", "Strappy Bottoms"}, %{"main" => "#121214", "trim" => "#1B1B1F", "metal" => "#C9CED6"}},
    {"seafoam", "Seafoam", {"Zip Crop", "Shorts"}, %{"main" => "#1D6B6B", "trim" => "#123F3F", "accent" => "#E8F1EE"}},
    {"georgette", "Georgette", {"Ruffle Bralette", "Ruffle Shorts"}, %{"main" => "#F2C6CF", "trim" => "#E9AFBC", "accent" => "#E8E2D0"}},
    {"brocade", "Brocade", {"Bandeau", "Tie-Sides"}, %{"main" => "#0E4B3A", "trim" => "#C8A951"}},
    {"waffle", "Waffle", {"Camisole", "Lounge Shorts"}, %{"main" => "#D9C29A", "trim" => "#8C6F4A", "accent" => "#F4EFE6"}},
    {"linen", "Linen", {"Wrap Halter", "Wrap Bottoms"}, %{"main" => "#C9B79C", "trim" => "#B8A37F"}},
    {"chain_iron", "Rough Iron Chain", {"Bikini Top", "Bikini Bottoms"}, %{"main" => "#9AA0A6", "trim" => "#4A3524"}},
    {"chain_brass", "Ornamented Brass Chain", {"Bikini Top", "Bikini Bottoms"}, %{"main" => "#D4AF37", "trim" => "#C8A951"}},
    {"chain_steel", "Reinforced Steel", {"Bikini Top", "Bikini Bottoms"}, %{"main" => "#BAC2C7", "trim" => "#8A9298"}},
    {"chain_gold", "Gilded Paladin Chain", {"Bikini Top", "Bikini Bottoms"}, %{"main" => "#F3C13A", "trim" => "#E0A526"}},
    {"plate_steel", "Glorious Steel Plate", {"Bikini Top", "Bikini Bottoms"}, %{"main" => "#BAC2C7", "trim" => "#6A7278", "accent" => "#3B2A1C"}},
    {"plate_gold", "Champion Gold Plate", {"Bikini Top", "Bikini Bottoms"}, %{"main" => "#D4AF37", "trim" => "#C8A951", "accent" => "#3B2A1C"}},
    {"plate_dark", "Dread Iron Spiked", {"Bikini Top", "Bikini Bottoms"}, %{"main" => "#3A3E42", "trim" => "#1E2022", "accent" => "#161618"}},
    {"plate_draconic", "Draconic Scale Plate", {"Bikini Top", "Bikini Bottoms"}, %{"main" => "#8B1E1E", "trim" => "#3A1A1A", "accent" => "#2A1414"}},
    {"plate_mythril", "Mythril Runed Plate", {"Bikini Top", "Bikini Bottoms"}, %{"main" => "#7FB8D4", "trim" => "#C0E2F0", "accent" => "#2B3A55"}}
  ]

  @doc "The underwear set ids, starter first (for the merchant and the tests)."
  def underwear_sets, do: Enum.map(@under, &elem(&1, 0))

  @underwear Enum.flat_map(@under, fn {id, name, {tn, bn}, colors} ->
               [
                 %{id: "#{id}_top", name: "#{name} #{tn}", kind: "armor", slots: ["under_top"], value: Map.get(@under_value, id, 6),
                   ac: Map.get(@under_ac, id, 0), colors: colors,
                   wear: %{"female" => %{"part" => "Garments/Female/uw_#{id}_top.glb"}, "male" => nil}},
                 %{id: "#{id}_bottom", name: "#{name} #{bn}", kind: "armor", slots: ["under_bottom"], value: Map.get(@under_value, id, 6),
                   ac: Map.get(@under_ac, id, 0), colors: colors,
                   wear: %{"female" => %{"part" => "Garments/Female/uw_#{id}_bottom.glb"}, "male" => %{"part" => "Garments/Male/uw_#{id}_bottom.glb"}}}
               ]
             end)

  # The jeweller's sets (2026-11-01, owner: highly polished pink plate bikinis, "100 gems each",
  # "make them available to purchase from a merchant in-game for gems"): ten sets in polished
  # rose-pink metal (library/pipeline/scripts/b8_jewel_designs.py, Humans/Garments/<Body>/
  # uw_jw_<set>_top|bottom.glb). Rosalind the jeweller (BaconWorld.Merchants) sells a whole set,
  # both pieces, for `jewel_price_gems/0` Gems from the player's Bacon Store wallet. Each set has
  # a power of its own (BaconWorld.Powers), carried by the bottom piece. {set, name, {top, bottom},
  # power, colours}.
  @jewel_price_gems 100
  @jewel [
    {"jw_filament", "Gilded Filament", {"Jewelled Cups", "Jewelled Brief"}, "midas", %{"main" => "#F2A9C4", "trim" => "#E9B9A0", "accent" => "#C23B8E"}},
    {"jw_thorn", "Thorned Thread", {"Thorned Cups", "Thorned Brief"}, "thorns", %{"main" => "#EFA0BF", "trim" => "#D98FA8", "accent" => "#8E2050"}},
    {"jw_diamond", "Diamond Link", {"Sunburst Cups", "Sunburst Brief"}, "brilliance", %{"main" => "#F4B6CD", "trim" => "#F7DCE6", "accent" => "#FFFFFF"}},
    {"jw_filigree", "Filigree Web", {"Filigree Cups", "Filigree Brief"}, "snare", %{"main" => "#EBA3C0", "trim" => "#E9C2CF", "accent" => "#F3D7E2"}},
    {"jw_celestial", "Celestial Link", {"Crescent Cups", "Starfall Brief"}, "starlit", %{"main" => "#F0B0CA", "trim" => "#F6D2DF", "accent" => "#FFE7F0"}},
    {"jw_starfire", "Starfire Wire", {"Starfire Cups", "Starfire Brief"}, "starfire", %{"main" => "#E0258F", "trim" => "#F06AB4", "accent" => "#FFC2E2"}},
    {"jw_lasso", "Jeweled Lasso", {"Engraved Cups", "Tasselled Brief"}, "lasso", %{"main" => "#EDA6C2", "trim" => "#DDB4A6", "accent" => "#B8337A"}},
    {"jw_oceanic", "Oceanic Tendril", {"Seashell Cups", "Seashell Brief"}, "riptide", %{"main" => "#F3B5CB", "trim" => "#E6C4B6", "accent" => "#FFE9F1"}},
    {"jw_rose", "Rose Wire", {"Rose Cups", "Rose Brief"}, "bloom", %{"main" => "#EE9DBD", "trim" => "#D9A994", "accent" => "#7A9A5C"}},
    {"jw_phoenix", "Phoenix Strand", {"Winged Cups", "Winged Brief"}, "phoenix", %{"main" => "#F2ABC6", "trim" => "#F4C9A8", "accent" => "#FF8FB8"}}
  ]

  @doc "The jeweller's set ids (`jw_*`)."
  def jewel_sets, do: Enum.map(@jewel, &elem(&1, 0))

  @doc "What a jeweller's set costs (Gems)."
  def jewel_price_gems, do: @jewel_price_gems

  @doc "What buying `item` from the jeweller gives a body: the heels alone, or the set's pieces."
  def jewel_bundle(%{slots: ["feet"], id: id}, _body), do: [id]
  def jewel_bundle(%{jewel: set}, body) when is_binary(set), do: jewel_pieces(set, body)

  @doc "The pieces of a jeweller's set a body wears (the male wears the bottom only)."
  def jewel_pieces(set, body \\ "female")
  def jewel_pieces(set, "male"), do: ["#{set}_bottom"]
  def jewel_pieces(set, _), do: ["#{set}_top", "#{set}_bottom"]

  @jewelry Enum.flat_map(@jewel, fn {id, name, {tn, bn}, power, colors} ->
             [
               %{id: "#{id}_top", name: "#{name} #{tn}", kind: "armor", slots: ["under_top"], value: 0, ac: 2, gems: @jewel_price_gems,
                 jewel: id, colors: colors,
                 wear: %{"female" => %{"part" => "Garments/Female/uw_#{id}_top.glb"}, "male" => nil}},
               %{id: "#{id}_bottom", name: "#{name} #{bn}", kind: "armor", slots: ["under_bottom"], value: 0, ac: 2, gems: @jewel_price_gems,
                 jewel: id, power: power, colors: colors,
                 wear: %{"female" => %{"part" => "Garments/Female/uw_#{id}_bottom.glb"}, "male" => %{"part" => "Garments/Male/uw_#{id}_bottom.glb"}}},
               # the heels to go with the set (2026-11-01, owner: "also 100 gems and give 50% increased run speed"),
               # sold on their own (library/pipeline/scripts/b8_heels.py; the client points the feet)
               %{id: "#{id}_shoes", name: "#{name} Heels", kind: "armor", slots: ["feet"], value: 0, ac: 1, gems: @jewel_price_gems,
                 jewel: id, power: "swift", run_speed: 1.5, colors: colors,
                 wear: %{"female" => %{"part" => "Garments/Female/uw_#{id}_shoes.glb"}, "male" => %{"part" => "Garments/Male/uw_#{id}_shoes.glb"}}}
             ]
           end)

  # Cloth armour (2026-11-01, owner: "10 sets of cloth armor. FULL SETS"): ten sets of seven pieces
  # (head, hands, arms, wrist, chest, legs, feet), each piece its own garment GLB per body
  # (Humans/Garments/<Body>/ca_<set>_<slot>.glb, library/pipeline/scripts/b8_armor_designs.py). Value
  # and AC grow with the set's tier. {slot, piece name, value, ac, colors}.
  @armor_sets [
    {"wayfarer", "Wayfarer's", [
      {"head", "Hat", 20, 1, %{"main" => "#6B5A44", "trim" => "#2E2219"}},
      {"hands", "Mitts", 15, 1, %{"main" => "#8A7B66"}},
      {"arms", "Rolled Sleeves", 15, 1, %{"main" => "#E4D8BE"}},
      {"wrist", "Wrist Strap", 10, 1, %{}},
      {"chest", "Tunic", 40, 3, %{"main" => "#D9CCAE", "trim" => "#C4B591", "accent" => "#5C4027"}},
      {"legs", "Trousers", 30, 2, %{"main" => "#6F6A5C", "trim" => "#8C7A58"}},
      {"feet", "Shoes", 25, 1, %{"trim" => "#2A1D14"}}
    ]},
    {"hearth", "Hearthguard", [
      {"head", "Arming Cap", 40, 1, %{"main" => "#C8B898", "trim" => "#8C7A58"}},
      {"hands", "Gauntlets", 30, 1, %{"main" => "#BFAF8E", "trim" => "#4A3524"}},
      {"arms", "Spaulders", 30, 1, %{"main" => "#BFAF8E", "trim" => "#4A3524"}},
      {"wrist", "Quilted Cuffs", 20, 1, %{"main" => "#BFAF8E", "trim" => "#4A3524"}},
      {"chest", "Gambeson", 80, 3, %{"main" => "#BFAF8E", "trim" => "#4A3524"}},
      {"legs", "Padded Trousers", 60, 2, %{"main" => "#BFAF8E", "trim" => "#4A3524"}},
      {"feet", "Padded Boots", 50, 1, %{"main" => "#BFAF8E", "trim" => "#4A3524"}}
    ]},
    {"ranger", "Ranger's", [
      {"head", "Hood", 60, 1, %{"main" => "#3E5233", "trim" => "#5C4630"}},
      {"hands", "Gloves", 45, 1, %{"main" => "#7A5C3E", "trim" => "#3B2A1C"}},
      {"arms", "Shoulder Caps", 45, 1, %{"trim" => "#3B2A1C"}},
      {"wrist", "Laced Bracers", 30, 1, %{"trim" => "#3B2A1C"}},
      {"chest", "Jerkin", 120, 3, %{"main" => "#3E5233", "trim" => "#5C4630", "accent" => "#5C4027"}},
      {"legs", "Trousers", 90, 2, %{"main" => "#4B4A3A", "trim" => "#5C4630"}},
      {"feet", "Tall Boots", 75, 1, %{"main" => "#5C3F28", "trim" => "#7A5C3E"}}
    ]},
    {"scholar", "Scholar's", [
      {"head", "Beret", 100, 1, %{"main" => "#3B1F4A", "trim" => "#C9A227", "accent" => "#F2EBDD"}},
      {"hands", "Silk Gloves", 75, 1, %{"main" => "#F1EBDD", "accent" => "#F7F3EA"}},
      {"arms", "Slashed Sleeves", 75, 1, %{"main" => "#3B1F4A", "accent" => "#C9A227"}},
      {"wrist", "Lace Cuffs", 50, 1, %{"main" => "#F4EFE6"}},
      {"chest", "Doublet", 200, 4, %{"main" => "#3B1F4A", "trim" => "#C9A227", "accent" => "#F4EFE6"}},
      {"legs", "Breeches", 150, 3, %{"main" => "#3B1F4A", "accent" => "#EDE6D8", "trim" => "#C9A227"}},
      {"feet", "Buckled Shoes", 125, 1, %{"main" => "#1B1B1B", "accent" => "#3B1F4A"}}
    ]},
    {"nomad", "Nomad's", [
      {"head", "Turban", 60, 1, %{"main" => "#D8C7A3", "accent" => "#5B6F8C"}},
      {"hands", "Hand Wraps", 45, 1, %{"main" => "#E2D3B3"}},
      {"arms", "Arm Wraps", 45, 1, %{"main" => "#D8C7A3"}},
      {"wrist", "Bangles", 30, 1, %{}},
      {"chest", "Sash Vest", 120, 3, %{"main" => "#E2D3B3", "accent" => "#7A2E1E", "trim" => "#C8A951"}},
      {"legs", "Harem Trousers", 90, 2, %{"main" => "#5B6F8C", "trim" => "#C8A951"}},
      {"feet", "Sandals", 75, 1, %{"trim" => "#2E2016"}}
    ]},
    {"frost", "Frostwarden", [
      {"head", "Trapper Hat", 80, 1, %{"main" => "#5A4632", "accent" => "#E8E2D6", "trim" => "#E8E2D6"}},
      {"hands", "Mittens", 60, 1, %{"main" => "#6E4B3A", "trim" => "#EFE8DC"}},
      {"arms", "Fur-Cuffed Sleeves", 60, 1, %{"main" => "#5A4632", "trim" => "#EFE8DC"}},
      {"wrist", "Wrist Warmers", 40, 1, %{"main" => "#8B9A8F"}},
      {"chest", "Fur Coat", 160, 4, %{"main" => "#5A4632", "trim" => "#EFE8DC", "accent" => "#3B2A1C"}},
      {"legs", "Fleece Trousers", 120, 3, %{"main" => "#4C4A46", "trim" => "#EFE8DC"}},
      {"feet", "Fur Boots", 100, 1, %{"main" => "#6E4B3A", "trim" => "#EFE8DC", "accent" => "#2A1D14"}}
    ]},
    {"corsair", "Corsair's", [
      {"head", "Bandana", 80, 1, %{"main" => "#8E1B1B"}},
      {"hands", "Knuckle Gloves", 60, 1, %{"trim" => "#2A1B12"}},
      {"arms", "Billowing Sleeves", 60, 1, %{"main" => "#F1E9D8", "trim" => "#E5DAC2"}},
      {"wrist", "Studded Cuffs", 40, 1, %{"trim" => "#2A1B12"}},
      {"chest", "Vest and Shirt", 160, 4, %{"main" => "#F1E9D8", "accent" => "#3B2416", "trim" => "#8E1B1B"}},
      {"legs", "Striped Breeches", 120, 3, %{"main" => "#5A2420", "trim" => "#2A1B12"}},
      {"feet", "Bucket Boots", 100, 1, %{"trim" => "#2A1B12"}}
    ]},
    {"monastic", "Pilgrim's", [
      {"head", "Straw Hat", 20, 1, %{"main" => "#C9A86A", "trim" => "#7A5A3A"}},
      {"hands", "Hand Wraps", 15, 1, %{"main" => "#A88B5E"}},
      {"arms", "Bound Sleeves", 15, 1, %{"main" => "#A88B5E", "trim" => "#6E5434"}},
      {"wrist", "Prayer Beads", 10, 1, %{"main" => "#4A2E1A"}},
      {"chest", "Rope-Belted Tunic", 40, 3, %{"main" => "#A88B5E", "trim" => "#6E5434"}},
      {"legs", "Puttee Trousers", 30, 2, %{"main" => "#A88B5E", "trim" => "#D8CDB4"}},
      {"feet", "Straw Sandals", 25, 1, %{"main" => "#C9A86A", "trim" => "#7A5A3A"}}
    ]},
    {"duelist", "Duelist's", [
      {"head", "Cavalier Hat", 120, 1, %{"main" => "#141414", "trim" => "#7A1020", "accent" => "#B3122E"}},
      {"hands", "Gauntlet Gloves", 90, 1, %{"main" => "#141414", "trim" => "#1E1E1E", "accent" => "#7A1020"}},
      {"arms", "Buckled Half-Sleeves", 90, 1, %{"main" => "#141414", "trim" => "#1E1E1E", "accent" => "#7A1020"}},
      {"wrist", "Bracers", 60, 1, %{"main" => "#141414", "trim" => "#1E1E1E", "accent" => "#7A1020"}},
      {"chest", "Jacket", 240, 4, %{"main" => "#141414", "accent" => "#7A1020"}},
      {"legs", "Laced Trousers", 180, 3, %{"main" => "#141414", "accent" => "#7A1020"}},
      {"feet", "Thigh Boots", 150, 1, %{"main" => "#141414"}}
    ]},
    {"mystic", "Mystic's", [
      {"head", "Circlet", 140, 1, %{"main" => "#E8D9F2", "accent" => "#3FA7D6"}},
      {"hands", "Opera Gloves", 105, 1, %{"main" => "#2B1D4E", "accent" => "#3FA7D6"}},
      {"arms", "Draped Armlets", 105, 1, %{"main" => "#E8D9F2", "accent" => "#3FA7D6"}},
      {"wrist", "Gilded Cuffs", 70, 1, %{"accent" => "#3FA7D6"}},
      {"chest", "Wrap Top", 280, 4, %{"main" => "#2B1D4E", "accent" => "#C9B7E8"}},
      {"legs", "Palazzo Trousers", 210, 3, %{"main" => "#5E3A86"}},
      {"feet", "Slippers", 175, 1, %{"main" => "#2B1D4E", "trim" => "#1B1B1B"}}
    ]},
    {"chain_iron", "Iron Chainmail", [
      {"head", "Coif", 80, 2, %{"main" => "#9AA0A6", "trim" => "#4A3524"}},
      {"hands", "Mitts", 60, 2, %{"main" => "#9AA0A6", "trim" => "#4A3524"}},
      {"arms", "Sleeves", 60, 2, %{"main" => "#9AA0A6", "trim" => "#4A3524"}},
      {"wrist", "Bracers", 40, 2, %{"main" => "#9AA0A6", "trim" => "#4A3524"}},
      {"chest", "Hauberk", 240, 6, %{"main" => "#9AA0A6", "trim" => "#4A3524"}},
      {"legs", "Chausses", 180, 4, %{"main" => "#9AA0A6", "trim" => "#4A3524"}},
      {"feet", "Boots", 120, 2, %{"main" => "#9AA0A6", "trim" => "#4A3524"}}
    ]},
    {"chain_steel", "Knight's Steel", [
      {"head", "Aventail", 140, 3, %{"main" => "#BAC2C7", "trim" => "#6A7278"}},
      {"hands", "Gauntlets", 100, 2, %{"main" => "#BAC2C7", "trim" => "#6A7278"}},
      {"arms", "Voiders", 100, 2, %{"main" => "#BAC2C7", "trim" => "#6A7278"}},
      {"wrist", "Cuffs", 70, 2, %{"main" => "#BAC2C7", "trim" => "#6A7278"}},
      {"chest", "Heavy Hauberk", 380, 8, %{"main" => "#BAC2C7", "trim" => "#6A7278"}},
      {"legs", "Leggings", 280, 5, %{"main" => "#BAC2C7", "trim" => "#6A7278"}},
      {"feet", "Boots", 200, 2, %{"main" => "#BAC2C7", "trim" => "#6A7278"}}
    ]},
    {"chain_gold", "Paladin's Gilded", [
      {"head", "Champion's Hood", 220, 4, %{"main" => "#F3C13A", "trim" => "#E0A526"}},
      {"hands", "Sovereign Gauntlets", 160, 3, %{"main" => "#F3C13A", "trim" => "#E0A526"}},
      {"arms", "Extensions", 160, 3, %{"main" => "#F3C13A", "trim" => "#E0A526"}},
      {"wrist", "Ringmail Wraps", 110, 2, %{"main" => "#F3C13A", "trim" => "#E0A526"}},
      {"chest", "Gilded Hauberk", 550, 10, %{"main" => "#F3C13A", "trim" => "#E0A526"}},
      {"legs", "Splinted Chausses", 420, 6, %{"main" => "#F3C13A", "trim" => "#E0A526"}},
      {"feet", "Foot Guards", 300, 3, %{"main" => "#F3C13A", "trim" => "#E0A526"}}
    ]},
    {"chain_dark", "Dread Guard", [
      {"head", "Guarded Hood", 180, 3, %{"main" => "#4F555A", "trim" => "#25282A"}},
      {"hands", "Claw Gloves", 130, 2, %{"main" => "#4F555A", "trim" => "#25282A"}},
      {"arms", "Arm Wraps", 130, 3, %{"main" => "#4F555A", "trim" => "#25282A"}},
      {"wrist", "Spiked Wraps", 90, 2, %{"main" => "#4F555A", "trim" => "#25282A"}},
      {"chest", "Dark Chain Shirt", 480, 9, %{"main" => "#4F555A", "trim" => "#25282A"}},
      {"legs", "Splinted Pants", 360, 5, %{"main" => "#4F555A", "trim" => "#25282A"}},
      {"feet", "Viking Boots", 250, 3, %{"main" => "#4F555A", "trim" => "#25282A"}}
    ]},
    {"plate_steel", "Knight's Vanguard Steel", [
      {"head", "Sallet", 240, 4, %{"main" => "#BAC2C7", "trim" => "#6A7278", "accent" => "#3B2A1C"}},
      {"hands", "Gauntlets", 180, 3, %{"main" => "#BAC2C7", "trim" => "#6A7278", "accent" => "#3B2A1C"}},
      {"arms", "Spaulders", 180, 3, %{"main" => "#BAC2C7", "trim" => "#6A7278", "accent" => "#3B2A1C"}},
      {"wrist", "Vambraces", 120, 2, %{"main" => "#BAC2C7", "trim" => "#6A7278", "accent" => "#3B2A1C"}},
      {"chest", "Fluted Cuirass", 650, 12, %{"main" => "#BAC2C7", "trim" => "#6A7278", "accent" => "#3B2A1C"}},
      {"legs", "Greaves", 480, 7, %{"main" => "#BAC2C7", "trim" => "#6A7278", "accent" => "#3B2A1C"}},
      {"feet", "Sabatons", 280, 3, %{"main" => "#BAC2C7", "trim" => "#6A7278", "accent" => "#3B2A1C"}}
    ]},
    {"plate_gold", "Paladin's Sacred Gilded", [
      {"head", "Phoenix Greathelm", 360, 5, %{"main" => "#D4AF37", "trim" => "#C8A951", "accent" => "#3B2A1C"}},
      {"hands", "Sovereign Gauntlets", 260, 4, %{"main" => "#D4AF37", "trim" => "#C8A951", "accent" => "#3B2A1C"}},
      {"arms", "Royal Winged Spaulders", 260, 4, %{"main" => "#D4AF37", "trim" => "#C8A951", "accent" => "#3B2A1C"}},
      {"wrist", "Inlaid Vambraces", 180, 3, %{"main" => "#D4AF37", "trim" => "#C8A951", "accent" => "#3B2A1C"}},
      {"chest", "Sacred Winged Cuirass", 950, 14, %{"main" => "#D4AF37", "trim" => "#C8A951", "accent" => "#3B2A1C"}},
      {"legs", "Winged Greaves", 680, 8, %{"main" => "#D4AF37", "trim" => "#C8A951", "accent" => "#3B2A1C"}},
      {"feet", "Gilded Sabatons", 380, 4, %{"main" => "#D4AF37", "trim" => "#C8A951", "accent" => "#3B2A1C"}}
    ]},
    {"plate_dark", "Dreadlord Spiked Obsidian", [
      {"head", "Spiked Barbuta", 300, 4, %{"main" => "#3A3E42", "trim" => "#1E2022", "accent" => "#161618"}},
      {"hands", "Claw Gauntlets", 220, 3, %{"main" => "#3A3E42", "trim" => "#1E2022", "accent" => "#161618"}},
      {"arms", "Spiked Pauldrons", 240, 4, %{"main" => "#3A3E42", "trim" => "#1E2022", "accent" => "#161618"}},
      {"wrist", "Spiked Bracers", 160, 3, %{"main" => "#3A3E42", "trim" => "#1E2022", "accent" => "#161618"}},
      {"chest", "Demon Hunter Cuirass", 820, 13, %{"main" => "#3A3E42", "trim" => "#1E2022", "accent" => "#161618"}},
      {"legs", "Heavy Leg-guards", 580, 7, %{"main" => "#3A3E42", "trim" => "#1E2022", "accent" => "#161618"}},
      {"feet", "Spurred Sabatons", 320, 3, %{"main" => "#3A3E42", "trim" => "#1E2022", "accent" => "#161618"}}
    ]},
    {"plate_draconic", "Dragon Slayer Scale", [
      {"head", "Horned Visor", 380, 5, %{"main" => "#8B1E1E", "trim" => "#3A1A1A", "accent" => "#2A1414"}},
      {"hands", "Scale Mitts", 280, 4, %{"main" => "#8B1E1E", "trim" => "#3A1A1A", "accent" => "#2A1414"}},
      {"arms", "Scale Pauldrons", 280, 4, %{"main" => "#8B1E1E", "trim" => "#3A1A1A", "accent" => "#2A1414"}},
      {"wrist", "Scaled Vambraces", 200, 3, %{"main" => "#8B1E1E", "trim" => "#3A1A1A", "accent" => "#2A1414"}},
      {"chest", "Dragon Slayer Cuirass", 980, 14, %{"main" => "#8B1E1E", "trim" => "#3A1A1A", "accent" => "#2A1414"}},
      {"legs", "Dragon Scale Greaves", 720, 8, %{"main" => "#8B1E1E", "trim" => "#3A1A1A", "accent" => "#2A1414"}},
      {"feet", "Dragon Claw Sabatons", 400, 4, %{"main" => "#8B1E1E", "trim" => "#3A1A1A", "accent" => "#2A1414"}}
    ]},
    {"plate_mythril", "Celestial Mythril Runed", [
      {"head", "Runed Casque", 420, 5, %{"main" => "#7FB8D4", "trim" => "#C0E2F0", "accent" => "#2B3A55"}},
      {"hands", "Runed Gloves", 300, 4, %{"main" => "#7FB8D4", "trim" => "#C0E2F0", "accent" => "#2B3A55"}},
      {"arms", "Celestial Shoulderplates", 300, 4, %{"main" => "#7FB8D4", "trim" => "#C0E2F0", "accent" => "#2B3A55"}},
      {"wrist", "Ethereal Vambraces", 220, 3, %{"main" => "#7FB8D4", "trim" => "#C0E2F0", "accent" => "#2B3A55"}},
      {"chest", "Celestial Runed Cuirass", 1100, 15, %{"main" => "#7FB8D4", "trim" => "#C0E2F0", "accent" => "#2B3A55"}},
      {"legs", "Luminous Greaves", 780, 8, %{"main" => "#7FB8D4", "trim" => "#C0E2F0", "accent" => "#2B3A55"}},
      {"feet", "Mythril Sabatons", 440, 4, %{"main" => "#7FB8D4", "trim" => "#C0E2F0", "accent" => "#2B3A55"}}
    ]}
  ]


  # Robes (2026-11-01): ten, worn in the chest slot over everything else (layer 9: they hide what
  # they cover of the trousers and boots). Humans/Garments/<Body>/rb_<robe>.glb.
  @robes [
    {"novice", "Novice's Robe", 60, %{"main" => "#8C7A5A", "trim" => "#76664A", "accent" => "#C2A878"}},
    {"acolyte", "Acolyte's Robe", 120, %{"main" => "#F3EFE6", "trim" => "#C9A227", "accent" => "#B3122E"}},
    {"arcanist", "Arcanist's Robe", 320, %{"main" => "#1F2A5E", "trim" => "#C9A227"}},
    {"druid", "Druid's Robe", 220, %{"main" => "#3E5A34", "accent" => "#6B8E3A", "trim" => "#4A3524"}},
    {"shadow", "Shadowed Robe", 280, %{"main" => "#141418", "accent" => "#5D1A7A"}},
    {"pyre", "Pyre Robe", 300, %{"main" => "#9E1B0E", "trim" => "#E0A526", "accent" => "#2A0A06"}},
    {"frost", "Frostweave Robe", 260, %{"main" => "#E9EEF2", "trim" => "#F7F5F0", "accent" => "#5C6F80"}},
    {"sage", "Sage's Robe", 240, %{"main" => "#6E1E2C", "trim" => "#C9A227", "accent" => "#2A2F5E"}},
    {"wanderer", "Wanderer's Robe", 160, %{"main" => "#C9B48C", "accent" => "#5A3E2B", "trim" => "#8A6E4B"}},
    {"celestial", "Celestial Robe", 400, %{"main" => "#1A2B6B", "trim" => "#C9D3E6"}}
  ]

  @armor Enum.flat_map(@armor_sets, fn {set, prefix, pieces} ->
           for {slot, name, value, ac, colors} <- pieces do
             %{id: "#{set}_#{slot}", name: "#{prefix} #{name}", kind: "armor", slots: [slot], ac: ac, value: value, colors: colors,
               wear: %{"female" => %{"part" => "Garments/Female/ca_#{set}_#{slot}.glb"}, "male" => %{"part" => "Garments/Male/ca_#{set}_#{slot}.glb"}}}
           end
         end) ++
           Enum.map(@robes, fn {id, name, value, colors} ->
             %{id: "#{id}_robe", name: name, kind: "armor", slots: ["chest"], ac: 3, value: value, colors: colors,
               wear: %{"female" => %{"part" => "Garments/Female/rb_#{id}.glb", "layer" => 9}, "male" => %{"part" => "Garments/Male/rb_#{id}.glb", "layer" => 9}}}
           end)

  @doc "The cloth armour set ids and the robe item ids (for the merchant and the tests)."
  def armor_sets, do: Enum.map(@armor_sets, &elem(&1, 0))
  def robes, do: Enum.map(@robes, &"#{elem(&1, 0)}_robe")

  @wearables @underwear ++ @jewelry ++ @armor

  @wear_slots ~w(head under_top under_bottom chest legs feet wrist arms hands)

  @armor_defaults %{hands: 1, set: nil, skill: nil, dmg: 0, dly: 0, reach: 0, ac: 0, stack: 1, model: nil, icon: nil, icon_url: nil}

  @defaults %{ac: 0, stack: 1, icon: nil, icon_url: nil, wear: nil, colors: nil, ranged: false, gems: nil, jewel: nil, power: nil, run_speed: nil}
  @by_id Map.new(@items, fn i -> {i.id, Map.merge(@defaults, i)} end)
         |> Map.merge(Map.new(@wearables, fn i -> {i.id, @defaults |> Map.merge(@armor_defaults) |> Map.merge(i)} end))

  @starter_wear [{"homespun_top", "under_top"}, {"homespun_bottom", "under_bottom"}]

  @starter_kit [
    {"worn_short_sword", "main"},
    {"worn_round_shield", nil},
    {"grill_fork", nil},
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
         colors: i.colors,
         # a bow: shoots arrows (BaconWorld.Melee.ranged?/1)
         ranged: i.ranged == true,
         # the jeweller's sets: bought with Gems, a power of their own (BaconWorld.Powers)
         gems: i.gems,
         jewel: i.jewel,
         power: power_payload(i.power),
         run_speed: Map.get(i, :run_speed)
       }}
    end)
  end

  # Where the inventory icon is, under /models.
  defp power_payload(nil), do: nil
  defp power_payload(id), do: (p = BaconWorld.Powers.get(id)) && %{id: id, name: p.name, summary: p.summary}

  defp icon_path(%{kind: "armor", id: id}), do: "Humans/Wardrobe/icons/#{id}.png"
  defp icon_path(%{model: m}) when is_binary(m), do: "Weapons/icons/W_#{m}.png"
  defp icon_path(%{icon: i}) when is_binary(i), do: "Weapons/icons/W_#{i}.png"
  defp icon_path(_), do: nil
end

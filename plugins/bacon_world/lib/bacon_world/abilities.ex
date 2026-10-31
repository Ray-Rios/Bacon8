defmodule BaconWorld.Abilities.Builder do
  @moduledoc false
  @effect_defaults %{
    base: 0,
    per_level: 0,
    spread: 0.15,
    speed_m: 24,
    radius_m: 6.5,
    arc: 95,
    jumps: 3,
    mult: 1.0,
    execute_mult: 1.0,
    reach_m: 0.4,
    max: 1,
    ms: 0,
    duration_ms: 0,
    dot_ticks: 0,
    dot_ratio: 0.0,
    hot_ticks: 0,
    hot_ratio: 0.0,
    slow_ms: 0,
    root_ms: 0,
    stun_ms: 0,
    knockback_m: 0.0,
    pull_m: 0.0,
    dash_m: 0.0,
    shield_hp: 0,
    temp_ac: 0,
    temp_dmg_pct: 0,
    temp_crit: 0.0,
    drain_pct: 0,
    mp_restore: 0
  }

  def effect_defaults, do: @effect_defaults

  def spell(id, name, school, icon, type, target, mp, cd_s, cast_s, range_m, opts) do
    opts_map = Map.new(opts)
    summary = Map.get(opts_map, :description, "")
    eff = @effect_defaults |> Map.merge(Map.drop(opts_map, [:description])) |> Map.put(:type, type)
    eff = if eff.ms == 0 and (eff.root_ms > 0 or eff.stun_ms > 0), do: Map.put(eff, :ms, max(eff.root_ms, eff.stun_ms)), else: eff
    eff = if Map.has_key?(opts_map, :radius), do: Map.put(eff, :radius_m, opts_map.radius), else: eff

    %{
      id: id,
      name: name,
      kind: "spell",
      school: school,
      icon: icon,
      summary: summary,
      mp: mp,
      cast_ms: round(cast_s * 1000),
      cooldown_ms: round(cd_s * 1000),
      target: target,
      range_m: range_m,
      effect: eff
    }
  end

  def skill(id, name, school, icon, type, target, mp, cd_s, range_m, opts) do
    opts_map = Map.new(opts)
    summary = Map.get(opts_map, :description, "")
    eff = @effect_defaults |> Map.merge(Map.drop(opts_map, [:description])) |> Map.put(:type, type)
    eff = if Map.has_key?(opts_map, :extra_reach), do: Map.put(eff, :reach_m, opts_map.extra_reach), else: eff
    eff = if Map.has_key?(opts_map, :radius), do: Map.put(eff, :radius_m, opts_map.radius), else: eff
    eff = if type == "spin" and not Map.has_key?(opts_map, :max), do: Map.put(eff, :max, 8), else: eff
    eff = if type == "strike" and Map.get(opts_map, :arc, 0) > 100 and not Map.has_key?(opts_map, :max), do: Map.put(eff, :max, 4), else: eff
    eff = if eff.ms == 0 and (eff.root_ms > 0 or eff.stun_ms > 0), do: Map.put(eff, :ms, max(eff.root_ms, eff.stun_ms)), else: eff

    %{
      id: id,
      name: name,
      kind: "skill",
      school: school,
      icon: icon,
      summary: summary,
      mp: mp,
      cast_ms: 0,
      cooldown_ms: round(cd_s * 1000),
      target: if(type in ["spin", "strike", "cone", "dash", "taunt", "shield", "buff_temp"] and target == "self", do: "none", else: target),
      range_m: range_m,
      effect: eff
    }
  end

  def buff(id, name, icon, stat, amount, summary) do
    %{
      id: id,
      name: name,
      kind: "buff",
      school: "buff",
      icon: icon,
      summary: summary,
      mp: 0,
      cast_ms: 0,
      cooldown_ms: 0,
      target: "none",
      range_m: 0,
      effect: %{type: "stat", stat: stat, amount: amount}
    }
  end
end

defmodule BaconWorld.Abilities do
  @moduledoc """
  What the skill tree's nodes give (`BaconWorld.SkillTree`): spells, skills and buffs.
  Fixed data, like the item catalogue; the tree (which ability sits on which node) is
  the owner's to edit at `/admin/bacon_world/skills`.

    * **spell** (101) - cast with mana, from the spell bar (two rows of ten, 1-0 and
      Shift+1-0). Organised into ten schools of ten spells each (Fire, Frost, Storm,
      Arcane, Holy, Nature, Shadow, Blood, Earth and Water) plus Recall.
    * **skill** (100) - a fighting or survival move, on the special-attack keys
      (Q E F Z X V). Organised into ten archetypes of ten skills each (Blade, Berserker,
      Blunt, Polearm, Rogue, Ranger, Guardian, Monk, Warlord and Survival).
    * **buff** (6) - always on once learned: more hit points, mana, or damage.

  `effect` says what it does (`BaconWorldWeb.SkillEvents` carries it out):

    * `%{type: "recall"}` - back to your bind point
    * `%{type: "heal", base, per_level, hot_ticks?, hot_ratio?, temp_ac?, mp_restore?}`
    * `%{type: "damage", base, per_level, spread, speed_m, dot_ticks?, dot_ratio?, slow_ms?, root_ms?, stun_ms?, knockback_m?, pull_m?, drain_pct?, temp_crit?, temp_dmg_pct?}`
    * `%{type: "drain", base, per_level, drain_pct, hot_ticks?, stun_ms?}`
    * `%{type: "aoe", radius_m, base, per_level, dot_ticks?, dot_ratio?, slow_ms?, root_ms?, stun_ms?, knockback_m?, pull_m?, drain_pct?, temp_ac?, temp_dmg_pct?, shield_hp?}`
    * `%{type: "cone", arc, base, per_level, mult?, dot_ticks?, dot_ratio?, slow_ms?, root_ms?, stun_ms?, knockback_m?, drain_pct?}`
    * `%{type: "chain", jumps, radius_m, base, per_level}`
    * `%{type: "root", ms, base?, per_level?}`
    * `%{type: "stun", ms, base, per_level}`
    * `%{type: "shield", base, per_level, duration_ms, temp_ac, temp_dmg_pct?, temp_crit?, mp_restore?}`
    * `%{type: "buff_temp", base, per_level, duration_ms, temp_dmg_pct, temp_ac, temp_crit, mp_restore?, hot_ticks?, hot_ratio?}`
    * `%{type: "dash", dash_m, radius_m?, base?, per_level?, mult?, stun_ms?, slow_ms?, shield_hp?, temp_ac?, temp_dmg_pct?, temp_crit?, duration_ms?}`
    * `%{type: "spin", mult, reach_m, max, dot_ticks?, dot_ratio?, slow_ms?, temp_dmg_pct?, duration_ms?}`
    * `%{type: "strike", mult, execute_mult?, arc?, reach_m, max, stun_ms?, root_ms?, slow_ms?, knockback_m?, dot_ticks?, dot_ratio?, drain_pct?, temp_ac?, temp_dmg_pct?, temp_crit?, shield_hp?, duration_ms?}`
    * `%{type: "taunt", radius_m, temp_ac, shield_hp, duration_ms}`
    * `%{type: "stat", stat, amount}` - passive skill-tree buff

  Icons are drawn by the client (`skill-tree-canvas.ts` `iconHTML`), keyed by `school`, `kind` and `icon`.
  """

  import BaconWorld.Abilities.Builder
  @effect_defaults BaconWorld.Abilities.Builder.effect_defaults()

  @spells [
    # 0. Core / Starting Spell
    %{
      id: "recall",
      name: "Recall",
      kind: "spell",
      school: "arcane",
      icon: "portal",
      summary: "Return to your bind point. Interrupted if you move.",
      mp: 0,
      cast_ms: 4_000,
      cooldown_ms: 60_000,
      target: "self",
      range_m: 0,
      effect: %{type: "recall"}
    },

    # =========================================================================
    # 1. FIRE SCHOOL (10 spells)
    # =========================================================================
    %{
      id: "fireball",
      name: "Fireball",
      kind: "spell",
      school: "fire",
      icon: "flame",
      summary: "Hurls a ball of fire at your target.",
      mp: 10,
      cast_ms: 900,
      cooldown_ms: 3_000,
      target: "enemy",
      range_m: 30,
      effect: Map.merge(@effect_defaults, %{type: "damage", base: 10, per_level: 3, spread: 0.2, speed_m: 22})
    },
    spell("flame_lance", "Flame Lance", "fire", "lance", "damage", "enemy", 9, 4, 0, 32,
      base: 16, per_level: 3.8, speed_m: 32,
      description: "Pierces your target with a searing lance of concentrated flame."
    ),
    spell("immolate", "Immolate", "fire", "flame", "damage", "enemy", 8, 5, 0, 26,
      base: 8, per_level: 2.2, dot_ticks: 4, dot_ratio: 0.45,
      description: "Engulfs your target in flames, scorching them immediately and burning over 8 seconds."
    ),
    spell("fire_nova", "Fire Nova", "fire", "burst", "aoe", "self", 12, 8, 0, 0,
      radius: 7.0, base: 14, per_level: 3.2, knockback_m: 2.5,
      description: "Unleashes an expanding ring of fire around you, scorching and knocking back nearby foes."
    ),
    spell("meteor", "Meteor", "fire", "meteor", "aoe", "enemy", 18, 14, 1.2, 30,
      radius: 6.5, base: 26, per_level: 5.0, dot_ticks: 3, dot_ratio: 0.35, stun_ms: 1500,
      description: "Calls a blazing meteor down from the heavens onto your target and nearby foes."
    ),
    spell("dragons_breath", "Dragon's Breath", "fire", "flame", "cone", "none", 11, 9, 0, 10,
      arc: 100, base: 15, per_level: 3.4, slow_ms: 4000,
      description: "Breathes a roaring cone of dragonfire in front of you, burning and dazing all enemies caught in the blast."
    ),
    spell("pyroblast", "Pyroblast", "fire", "meteor", "damage", "enemy", 16, 10, 1.6, 34,
      base: 28, per_level: 5.5, dot_ticks: 3, dot_ratio: 0.3, speed_m: 18,
      description: "Shapes an immense boulder of molten fire that detonates on your target for massive damage."
    ),
    spell("inferno", "Inferno", "fire", "volcano", "aoe", "enemy", 15, 12, 0.8, 26,
      radius: 6.0, base: 18, per_level: 3.8, dot_ticks: 4, dot_ratio: 0.4,
      description: "Erupts a pillar of hellfire beneath your target, incinerating every creature in the area."
    ),
    spell("fire_shield", "Fire Shield", "fire", "shield_star", "shield", "self", 10, 18, 0, 0,
      base: 18, per_level: 4.0, duration_ms: 15000, temp_ac: 6, temp_dmg_pct: 10,
      description: "Wreathes you in a blazing ward that absorbs incoming damage and empowers your spells by 10%."
    ),
    spell("combustion", "Combustion", "fire", "flame", "damage", "enemy", 14, 15, 0, 26,
      base: 22, per_level: 4.6, temp_crit: 0.25, duration_ms: 10000,
      description: "Detonates living fire inside your target and surges your critical strike chance for 10 seconds."
    ),

    # =========================================================================
    # 2. FROST SCHOOL (10 spells)
    # =========================================================================
    spell("frost_bolt", "Frost Bolt", "frost", "diamond", "damage", "enemy", 6, 2.5, 0.4, 28,
      base: 9, per_level: 2.8, slow_ms: 5000,
      description: "Fires a bolt of rime that damages your target and chills their movement for 5 seconds."
    ),
    spell("ice_lance", "Ice Lance", "frost", "lance", "damage", "enemy", 7, 3, 0, 30,
      base: 13, per_level: 3.4, temp_crit: 0.20, speed_m: 32,
      description: "Flings a razor-sharp icicle that shatters against frozen or chilled targets."
    ),
    spell("frost_nova", "Frost Nova", "frost", "snowflake", "aoe", "self", 10, 10, 0, 0,
      radius: 6.5, base: 9, per_level: 2.2, root_ms: 5000,
      description: "Blasts freezing cold around you, rooting all nearby creatures in ice for 5 seconds."
    ),
    spell("cone_of_cold", "Cone of Cold", "frost", "wind", "cone", "none", 10, 8, 0, 10,
      arc: 95, base: 13, per_level: 3.0, slow_ms: 6000,
      description: "Sprays a cone of arctic wind in front of you, damaging and slowing every foe it touches."
    ),
    spell("blizzard", "Blizzard", "frost", "snowflake", "aoe", "enemy", 15, 12, 0.8, 28,
      radius: 7.0, base: 16, per_level: 3.6, dot_ticks: 3, dot_ratio: 0.4, slow_ms: 6000,
      description: "Summons a howling hailstorm of ice shards over your target's area."
    ),
    spell("glacial_spike", "Glacial Spike", "frost", "spikes", "damage", "enemy", 15, 11, 1.2, 32,
      base: 25, per_level: 5.0, stun_ms: 2000,
      description: "Impales your target with a towering spire of glacier ice, stunning them for 2 seconds."
    ),
    spell("ice_barrier", "Ice Barrier", "frost", "shield", "shield", "self", 12, 20, 0, 0,
      base: 26, per_level: 5.5, duration_ms: 20000, temp_ac: 12,
      description: "Encases you in glacial armour that absorbs heavy damage and raises your AC by 12."
    ),
    spell("deep_freeze", "Deep Freeze", "frost", "cube", "stun", "enemy", 11, 14, 0, 24,
      base: 12, per_level: 2.8, duration_ms: 4000, stun_ms: 4000,
      description: "Locks your target inside a block of solid ice, stunning them completely for 4 seconds."
    ),
    spell("frozen_orb", "Frozen Orb", "frost", "orb", "aoe", "enemy", 14, 13, 0, 26,
      radius: 6.0, base: 17, per_level: 3.8, slow_ms: 5000, dot_ticks: 3, dot_ratio: 0.35,
      description: "Launches a whirling orb of frost that pelts the target area with razor ice."
    ),
    spell("icy_veins", "Icy Veins", "frost", "droplet", "buff_temp", "self", 10, 25, 0, 0,
      base: 10, per_level: 2.0, duration_ms: 15000, temp_dmg_pct: 20, temp_crit: 0.12,
      description: "Ice courses through your veins, increasing spell and attack damage by 20% and crit chance by 12% for 15 seconds."
    ),

    # =========================================================================
    # 3. STORM SCHOOL (10 spells)
    # =========================================================================
    spell("spark", "Spark", "storm", "bolt", "damage", "enemy", 4, 1.5, 0, 26,
      base: 7, per_level: 2.2, speed_m: 36,
      description: "Snaps a quick, low-mana arc of electricity at your target."
    ),
    spell("lightning_bolt", "Lightning Bolt", "storm", "bolt", "damage", "enemy", 8, 3, 0.4, 30,
      base: 14, per_level: 3.5, speed_m: 38,
      description: "Strikes your target with a high-voltage bolt of lightning."
    ),
    spell("chain_lightning", "Chain Lightning", "storm", "chain", "chain", "enemy", 13, 7, 0, 28,
      jumps: 3, radius: 9.0, base: 15, per_level: 3.4,
      description: "Blasts your target with lightning that arcs to up to 3 additional nearby enemies."
    ),
    spell("thunderclap", "Thunderclap", "storm", "burst", "aoe", "self", 10, 8, 0, 0,
      radius: 6.5, base: 13, per_level: 3.0, slow_ms: 5000,
      description: "Claps the air with deafening thunder, shocking and slowing all nearby creatures."
    ),
    spell("static_field", "Static Field", "storm", "sparks", "aoe", "self", 12, 10, 0, 0,
      radius: 7.5, base: 11, per_level: 2.6, dot_ticks: 4, dot_ratio: 0.4,
      description: "Ionizes the air around you, continuously shocking nearby enemies."
    ),
    spell("call_lightning", "Call Lightning", "storm", "cloud_bolt", "damage", "enemy", 15, 10, 0.6, 32,
      base: 24, per_level: 4.8, stun_ms: 1500, speed_m: 40,
      description: "Calls a blinding sky-bolt down from the storm clouds onto your target."
    ),
    spell("gust", "Gust", "storm", "wind", "damage", "enemy", 8, 9, 0, 24,
      base: 8, per_level: 2.0, knockback_m: 6.0, slow_ms: 3500,
      description: "Buffets your target with a gale-force blast, hurling them backward."
    ),
    spell("tempest", "Tempest", "storm", "cloud_bolt", "aoe", "enemy", 17, 14, 0.8, 28,
      radius: 7.5, base: 20, per_level: 4.2, dot_ticks: 4, dot_ratio: 0.35, slow_ms: 4000,
      description: "Unleashes a raging electrical cyclone over your target's area."
    ),
    spell("ball_lightning", "Ball Lightning", "storm", "orb", "aoe", "enemy", 12, 8, 0, 26,
      radius: 5.0, base: 16, per_level: 3.6,
      description: "Hurls a crackling sphere of plasma that detonates on impact, shocking nearby foes."
    ),
    spell("storm_step", "Storm Step", "storm", "boot", "dash", "none", 10, 10, 0, 0,
      dash_m: 10.0, radius: 4.5, base: 12, per_level: 2.8,
      description: "Dissolves into a flash of lightning, blinking 10 metres forward and jolting foes where you arrive."
    ),

    # =========================================================================
    # 4. ARCANE SCHOOL (10 spells)
    # =========================================================================
    spell("arcane_missiles", "Arcane Missiles", "arcane", "star", "damage", "enemy", 7, 3, 0, 30,
      base: 13, per_level: 3.2, speed_m: 28,
      description: "Launches a salvo of homing arcane bolts that unerringly strike your target."
    ),
    spell("arcane_blast", "Arcane Blast", "arcane", "orb", "damage", "enemy", 11, 4.5, 0.5, 28,
      base: 19, per_level: 4.2,
      description: "Implodes pure aether on your target for heavy arcane damage."
    ),
    spell("blink", "Blink", "arcane", "portal", "dash", "none", 8, 9, 0, 0,
      dash_m: 12.0,
      description: "Steps through a fold in space, teleporting 12 metres forward and breaking free of roots."
    ),
    spell("arcane_explosion", "Arcane Explosion", "arcane", "burst", "aoe", "self", 10, 5, 0, 0,
      radius: 6.5, base: 13, per_level: 3.0,
      description: "Releases a sudden wave of arcane force that hits every creature around you."
    ),
    spell("hex_of_slumber", "Hex of Slumber", "arcane", "zzz", "stun", "enemy", 10, 14, 0, 24,
      base: 6, per_level: 1.5, duration_ms: 5000, stun_ms: 5000,
      description: "Weaves a hypnotic hex that lulls your target into a deep slumber for 5 seconds."
    ),
    spell("mana_shield", "Mana Shield", "arcane", "shield", "shield", "self", 8, 18, 0, 0,
      base: 22, per_level: 4.8, duration_ms: 18000, temp_ac: 8, mp_restore: 12,
      description: "Wraps you in a shimmering aether ward that absorbs damage and restores mana."
    ),
    spell("starfall", "Starfall", "arcane", "star", "aoe", "enemy", 16, 13, 0.6, 30,
      radius: 8.0, base: 21, per_level: 4.4, dot_ticks: 3, dot_ratio: 0.35,
      description: "Calls down a shower of falling stars upon your target and all nearby enemies."
    ),
    spell("time_warp", "Time Warp", "arcane", "hourglass", "buff_temp", "self", 12, 28, 0, 0,
      base: 14, per_level: 3.0, duration_ms: 16000, temp_dmg_pct: 25, temp_crit: 0.10, mp_restore: 15,
      description: "Bends time around you, restoring mana and boosting all damage by 25% for 16 seconds."
    ),
    spell("disintegrate", "Disintegrate", "arcane", "beam", "damage", "enemy", 14, 8, 0.4, 28,
      base: 23, per_level: 4.8, slow_ms: 4000, speed_m: 36,
      description: "Projects a beam of pure annihilation that sears your target and slows their movement."
    ),
    spell("nullify", "Nullify", "arcane", "spiral", "damage", "enemy", 9, 8, 0, 26,
      base: 12, per_level: 2.8, slow_ms: 6000, stun_ms: 1200,
      description: "Strips away your target's momentum with an arcane vortex, dazing and slowing them."
    ),

    # =========================================================================
    # 5. HOLY SCHOOL (10 spells)
    # =========================================================================
    %{
      id: "heal",
      name: "Minor Healing",
      kind: "spell",
      school: "holy",
      icon: "cross",
      summary: "Heals you, or the player you have targeted.",
      mp: 8,
      cast_ms: 1_200,
      cooldown_ms: 4_000,
      target: "friendly",
      range_m: 25,
      effect: Map.merge(@effect_defaults, %{type: "heal", base: 14, per_level: 4})
    },
    spell("smite", "Smite", "holy", "sun", "damage", "enemy", 7, 2.5, 0, 28,
      base: 12, per_level: 3.2, speed_m: 30,
      description: "Sears a wicked creature with a bolt of righteous golden light."
    ),
    spell("renew", "Renew", "holy", "sprout", "heal", "friendly", 9, 5, 0, 25,
      base: 10, per_level: 2.8, hot_ticks: 4, hot_ratio: 0.45,
      description: "Bathes the target in gentle light, healing immediately and over 8 seconds."
    ),
    spell("greater_heal", "Greater Heal", "holy", "cross", "heal", "friendly", 15, 6, 1.2, 25,
      base: 28, per_level: 6.5,
      description: "Calls down a radiant column of grace that restores a large pool of hit points."
    ),
    spell("holy_nova", "Holy Nova", "holy", "sun", "aoe", "self", 13, 8, 0, 0,
      radius: 7.0, base: 14, per_level: 3.2, drain_pct: 60,
      description: "Bursts with golden light that scorches nearby enemies and heals you."
    ),
    spell("divine_shield", "Divine Shield", "holy", "shield", "shield", "self", 14, 25, 0, 0,
      base: 35, per_level: 7.0, duration_ms: 15000, temp_ac: 18,
      description: "Surrounds you in an impenetrable halo of golden light that absorbs heavy damage."
    ),
    spell("consecration", "Consecration", "holy", "shield_star", "aoe", "self", 12, 10, 0, 0,
      radius: 6.5, base: 12, per_level: 2.8, dot_ticks: 4, dot_ratio: 0.4,
      description: "Sanctifies the ground beneath your feet, burning all nearby foes with holy fire."
    ),
    spell("blessing_of_might", "Blessing of Might", "holy", "crown", "buff_temp", "self", 10, 20, 0, 0,
      base: 15, per_level: 3.5, duration_ms: 20000, temp_dmg_pct: 18, temp_ac: 8,
      description: "Blesses you with righteous vigour, healing you and raising damage by 18% and AC by 8."
    ),
    spell("lay_on_hands", "Lay on Hands", "holy", "hand", "heal", "friendly", 20, 45, 0, 20,
      base: 50, per_level: 11.0, temp_ac: 10, duration_ms: 12000,
      description: "A miracle of restoration that pours massive hit points into your target or yourself."
    ),
    spell("judgement", "Judgement", "holy", "pillar", "damage", "enemy", 11, 7, 0, 26,
      base: 18, per_level: 4.0, stun_ms: 2000, speed_m: 34,
      description: "Brings down a pillar of golden judgement that smites and stuns your target."
    ),

    # =========================================================================
    # 6. NATURE SCHOOL (10 spells)
    # =========================================================================
    %{
      id: "root",
      name: "Entangling Roots",
      kind: "spell",
      school: "nature",
      icon: "sprout",
      summary: "Roots your target in place for 6 seconds. It can still fight back.",
      mp: 8,
      cast_ms: 600,
      cooldown_ms: 15_000,
      target: "enemy",
      range_m: 25,
      effect: Map.merge(@effect_defaults, %{type: "root", ms: 6_000, root_ms: 6_000})
    },
    spell("thorn_volley", "Thorn Volley", "nature", "burst", "cone", "none", 9, 6, 0, 12,
      arc: 90, base: 13, per_level: 3.0, dot_ticks: 3, dot_ratio: 0.3,
      description: "Looses a fan of razor-sharp bramble thorns across a frontal cone."
    ),
    spell("rejuvenation", "Rejuvenation", "nature", "leaf", "heal", "friendly", 8, 4, 0, 25,
      base: 11, per_level: 3.0, hot_ticks: 4, hot_ratio: 0.5,
      description: "Infuses the target with verdant life that heals immediately and over 8 seconds."
    ),
    spell("insect_swarm", "Insect Swarm", "nature", "sparks", "damage", "enemy", 9, 6, 0, 26,
      base: 9, per_level: 2.2, dot_ticks: 5, dot_ratio: 0.45, slow_ms: 5000,
      description: "Calls a cloud of stinging locusts that harasses your target over 10 seconds."
    ),
    spell("barkskin", "Barkskin", "nature", "shield", "shield", "self", 9, 18, 0, 0,
      base: 22, per_level: 4.5, duration_ms: 18000, temp_ac: 14,
      description: "Turns your skin as tough as ancient oak bark, absorbing damage and raising AC by 14."
    ),
    spell("wrath_of_the_grove", "Wrath of the Grove", "nature", "sprout", "damage", "enemy", 10, 4, 0, 28,
      base: 16, per_level: 3.7, root_ms: 2000,
      description: "Hurls a bolt of emerald sylvan wrath that strikes and briefly entangles your foe."
    ),
    spell("spore_cloud", "Spore Cloud", "nature", "cloud", "aoe", "enemy", 12, 10, 0, 24,
      radius: 6.5, base: 12, per_level: 2.8, dot_ticks: 4, dot_ratio: 0.4, slow_ms: 5000,
      description: "Blankets the target area in toxic fungal spores that poison and slow every creature."
    ),
    spell("tranquility", "Tranquility", "nature", "lotus", "heal", "self", 16, 20, 0.8, 0,
      base: 30, per_level: 6.5, hot_ticks: 4, hot_ratio: 0.4,
      description: "Calls down a soothing rain of emerald blossoms that deeply restores your health."
    ),
    spell("spirit_of_the_wolf", "Spirit of the Wolf", "nature", "paw", "dash", "none", 8, 10, 0, 0,
      dash_m: 9.0, temp_dmg_pct: 12, duration_ms: 12000,
      description: "Bounds forward with the swiftness of the pack and sharpens your attacks for 12 seconds."
    ),
    spell("wild_growth", "Wild Growth", "nature", "sprout", "heal", "friendly", 13, 10, 0, 25,
      base: 18, per_level: 4.2, hot_ticks: 3, hot_ratio: 0.4, temp_ac: 6, duration_ms: 10000,
      description: "Causes vibrant flora to bloom around the target, healing and shielding them."
    ),

    # =========================================================================
    # 7. SHADOW SCHOOL (10 spells)
    # =========================================================================
    spell("shadow_bolt", "Shadow Bolt", "shadow", "skull", "damage", "enemy", 7, 2.5, 0, 28,
      base: 12, per_level: 3.3,
      description: "Sends a bolt of condensed void shadow streaking into your target."
    ),
    spell("corruption", "Corruption", "shadow", "spiral", "damage", "enemy", 8, 5, 0, 26,
      base: 8, per_level: 2.0, dot_ticks: 5, dot_ratio: 0.48,
      description: "Corrupts your target's flesh with creeping shadow rot over 10 seconds."
    ),
    spell("curse_of_weakness", "Curse of Weakness", "shadow", "spiral", "damage", "enemy", 8, 7, 0, 26,
      base: 10, per_level: 2.4, slow_ms: 7000,
      description: "Lays a heavy shadow curse on your target, sapping their speed and strength."
    ),
    spell("drain_life", "Drain Life", "shadow", "heart", "drain", "enemy", 10, 6, 0, 24,
      base: 14, per_level: 3.2, drain_pct: 75,
      description: "Siphons vital essence from your target, healing you for 75% of the shadow damage dealt."
    ),
    spell("fear", "Fear", "shadow", "skull", "stun", "enemy", 10, 14, 0, 22,
      base: 8, per_level: 1.8, duration_ms: 4500, stun_ms: 4500,
      description: "Projects visions of terror into your target's mind, freezing them in dread for 4.5 seconds."
    ),
    spell("shadowfury", "Shadowfury", "shadow", "burst", "aoe", "enemy", 14, 12, 0, 26,
      radius: 6.5, base: 16, per_level: 3.6, stun_ms: 2500,
      description: "Detonates a sphere of dark energy at your target's feet, blasting and stunning nearby foes."
    ),
    spell("death_coil", "Death Coil", "shadow", "spiral", "drain", "enemy", 13, 10, 0, 26,
      base: 18, per_level: 4.0, drain_pct: 80, stun_ms: 2000,
      description: "Unleashes a mortal coil of undeath that horrifies your target and heals you."
    ),
    spell("plague", "Plague", "shadow", "sparks", "aoe", "enemy", 14, 11, 0, 25,
      radius: 6.5, base: 12, per_level: 2.8, dot_ticks: 5, dot_ratio: 0.42, slow_ms: 5000,
      description: "Infects your target and all nearby creatures with a virulent shadow plague."
    ),
    spell("dark_pact", "Dark Pact", "shadow", "gem", "buff_temp", "self", 4, 20, 0, 0,
      base: 12, per_level: 2.5, duration_ms: 15000, temp_dmg_pct: 22, mp_restore: 24,
      description: "Taps into forbidden void reserves, immediately restoring mana and boosting spell power by 22%."
    ),
    spell("doom", "Doom", "shadow", "clock", "damage", "enemy", 16, 15, 0.6, 28,
      base: 24, per_level: 5.2, dot_ticks: 4, dot_ratio: 0.45,
      description: "Pronounces inescapable doom upon your target, inflicting crushing shadow damage."
    ),

    # =========================================================================
    # 8. BLOOD SCHOOL (10 spells)
    # =========================================================================
    spell("blood_lance", "Blood Lance", "blood", "lance", "damage", "enemy", 7, 3, 0, 28,
      base: 14, per_level: 3.4, drain_pct: 25, speed_m: 30,
      description: "Impales your target with a hardened spear of crimson blood."
    ),
    spell("hemorrhage", "Hemorrhage", "blood", "droplet", "damage", "enemy", 8, 5, 0, 25,
      base: 10, per_level: 2.4, dot_ticks: 4, dot_ratio: 0.5,
      description: "Ruptures your target's vessels, causing a severe bleed over 8 seconds."
    ),
    spell("exsanguinate", "Exsanguinate", "blood", "fangs", "drain", "enemy", 13, 9, 0, 24,
      base: 21, per_level: 4.5, drain_pct: 60,
      description: "Rips the lifeblood from your foe, dealing heavy burst damage and healing you."
    ),
    spell("blood_frenzy", "Blood Frenzy", "blood", "flame", "buff_temp", "self", 8, 20, 0, 0,
      base: 12, per_level: 2.5, duration_ms: 14000, temp_dmg_pct: 24, temp_crit: 0.10,
      description: "Ignites your blood in a crimson frenzy, boosting all damage by 24% and crit chance by 10%."
    ),
    spell("blood_boil", "Blood Boil", "blood", "droplet", "aoe", "self", 12, 8, 0, 0,
      radius: 7.0, base: 15, per_level: 3.4, dot_ticks: 3, dot_ratio: 0.35,
      description: "Boils the blood of every creature around you in a crimson shockwave."
    ),
    spell("sanguine_ward", "Sanguine Ward", "blood", "shield_star", "shield", "self", 11, 18, 0, 0,
      base: 24, per_level: 5.0, duration_ms: 16000, temp_ac: 10,
      description: "Forms a barrier of living blood around you that absorbs damage and mends flesh."
    ),
    spell("transfusion", "Transfusion", "blood", "heart", "heal", "self", 6, 15, 0, 0,
      base: 20, per_level: 4.5, mp_restore: 18,
      description: "Cycles vital crimson energy to restore both your hit points and mana."
    ),
    spell("crimson_tide", "Crimson Tide", "blood", "waves", "cone", "none", 12, 9, 0, 10,
      arc: 100, base: 16, per_level: 3.6, drain_pct: 40,
      description: "Sends a crashing wave of blood across a frontal cone, draining life from all foes hit."
    ),
    spell("vampiric_embrace", "Vampiric Embrace", "blood", "vampire", "drain", "enemy", 11, 8, 0, 24,
      base: 15, per_level: 3.4, drain_pct: 85, hot_ticks: 3, hot_ratio: 0.35,
      description: "Fangs of shadow-blood latch onto your target, leeching their vitality into you."
    ),
    spell("heartstopper", "Heartstopper", "blood", "heart", "stun", "enemy", 14, 14, 0, 24,
      base: 19, per_level: 4.2, duration_ms: 3500, stun_ms: 3500,
      description: "Clenches your target's heart in an iron grip, stunning them and dealing heavy blood damage."
    ),

    # =========================================================================
    # 9. EARTH SCHOOL (10 spells)
    # =========================================================================
    spell("hurl_boulder", "Hurl Boulder", "earth", "mountain", "damage", "enemy", 9, 4, 0.3, 26,
      base: 16, per_level: 3.8, stun_ms: 1500, knockback_m: 2.5, speed_m: 20,
      description: "Heaves a massive slab of granite that crushes and staggers your target."
    ),
    spell("earthquake", "Earthquake", "earth", "quake", "aoe", "enemy", 15, 12, 0.5, 26,
      radius: 7.5, base: 18, per_level: 4.0, slow_ms: 5000, stun_ms: 1500,
      description: "Splits the ground beneath your target, shaking and stunning all nearby creatures."
    ),
    spell("stoneskin", "Stoneskin", "earth", "shield", "shield", "self", 11, 20, 0, 0,
      base: 28, per_level: 5.8, duration_ms: 20000, temp_ac: 16,
      description: "Turns your skin to living granite, granting a heavy absorb ward and +16 AC."
    ),
    spell("earthen_spikes", "Earthen Spikes", "earth", "spikes", "cone", "none", 10, 7, 0, 11,
      arc: 80, base: 15, per_level: 3.4, slow_ms: 4000,
      description: "Thrusts jagged stone stalagmites up through the ground in a cone ahead of you."
    ),
    spell("tremor", "Tremor", "earth", "quake", "aoe", "self", 10, 9, 0, 0,
      radius: 6.5, base: 13, per_level: 3.0, knockback_m: 3.5, slow_ms: 4000,
      description: "Stomps a violent tremor through the earth around you, knocking foes back."
    ),
    spell("quicksand", "Quicksand", "earth", "spiral", "aoe", "enemy", 11, 11, 0, 25,
      radius: 5.5, base: 11, per_level: 2.5, root_ms: 5000, slow_ms: 7000,
      description: "Turns the earth under your target into churning mire that roots and slows nearby foes."
    ),
    spell("stone_fist", "Stone Fist", "earth", "fist", "damage", "enemy", 8, 5, 0, 16,
      base: 17, per_level: 3.8, stun_ms: 2000,
      description: "Projects a colossal fist of bedrock that slams your target and stuns them."
    ),
    spell("magma_eruption", "Magma Eruption", "earth", "volcano", "aoe", "enemy", 14, 11, 0.4, 26,
      radius: 6.0, base: 19, per_level: 4.2, dot_ticks: 3, dot_ratio: 0.35,
      description: "Ruptures the earth beneath your target in a geyser of molten stone."
    ),
    spell("earthbind_totem", "Earthbind Totem", "earth", "totem", "aoe", "self", 9, 12, 0, 0,
      radius: 7.5, base: 9, per_level: 2.0, root_ms: 4500, slow_ms: 6000,
      description: "Raises an earthen totem at your feet that pulses roots and slows all nearby creatures."
    ),
    spell("landslide", "Landslide", "earth", "mountain", "cone", "none", 13, 10, 0, 12,
      arc: 95, base: 20, per_level: 4.3, stun_ms: 1800,
      description: "Unleashes a roaring avalanche of rock and debris across a frontal cone."
    ),

    # =========================================================================
    # 10. WATER SCHOOL (10 spells)
    # =========================================================================
    spell("water_jet", "Water Jet", "water", "droplet", "damage", "enemy", 6, 2.5, 0, 28,
      base: 11, per_level: 3.0, knockback_m: 3.0, speed_m: 30,
      description: "Blasts your target with a high-pressure torrent of water that pushes them back."
    ),
    spell("healing_wave", "Healing Wave", "water", "waves", "heal", "friendly", 11, 4, 0.5, 25,
      base: 20, per_level: 4.8,
      description: "Washes your target or yourself in restorative ocean waters."
    ),
    spell("chain_heal", "Chain Heal", "water", "chain", "heal", "friendly", 14, 7, 0.4, 25,
      base: 22, per_level: 5.0, hot_ticks: 3, hot_ratio: 0.35, mp_restore: 8,
      description: "A cascading surge of living water that mends wounds and refreshes spirit."
    ),
    spell("tidal_wave", "Tidal Wave", "water", "waves", "cone", "none", 11, 8, 0, 11,
      arc: 105, base: 15, per_level: 3.4, slow_ms: 5000, knockback_m: 3.0,
      description: "Sweeps a crashing wall of seawater across a wide frontal cone."
    ),
    spell("whirlpool", "Whirlpool", "water", "spiral", "aoe", "enemy", 13, 11, 0, 26,
      radius: 6.5, base: 15, per_level: 3.4, pull_m: 4.0, slow_ms: 5000,
      description: "Conjures a churning maelstrom that drags nearby enemies inward and batters them."
    ),
    spell("meditation", "Meditation", "water", "lotus", "buff_temp", "self", 0, 22, 0, 0,
      base: 16, per_level: 3.5, hot_ticks: 4, hot_ratio: 0.4, mp_restore: 28,
      description: "Enters a tranquil flow like still water, restoring mana and hit points."
    ),
    spell("water_shield", "Water Shield", "water", "shield", "shield", "self", 9, 18, 0, 0,
      base: 22, per_level: 4.6, duration_ms: 18000, temp_ac: 10, mp_restore: 14,
      description: "Orbiting globes of water absorb incoming blows and replenish your mana."
    ),
    spell("drown", "Drown", "water", "droplet", "damage", "enemy", 12, 10, 0, 25,
      base: 14, per_level: 3.2, dot_ticks: 4, dot_ratio: 0.45, stun_ms: 2000,
      description: "Engulfs your target in crushing abyssal water, choking and stunning them."
    ),
    spell("riptide", "Riptide", "water", "waves", "heal", "friendly", 9, 5, 0, 25,
      base: 14, per_level: 3.4, hot_ticks: 4, hot_ratio: 0.45,
      description: "Casts a spring tide of soothing water that heals immediately and over time."
    ),
    spell("undertow", "Undertow", "water", "spiral", "damage", "enemy", 10, 8, 0, 26,
      base: 13, per_level: 3.0, root_ms: 4000, slow_ms: 6000, pull_m: 3.0,
      description: "A dragging current pulls your target's feet out from under them, rooting and slowing."
    )
  ]

  @skills [
    # =========================================================================
    # 1. BLADE / ARMS ARCHETYPE (10 skills)
    # =========================================================================
    %{
      id: "spin_attack",
      name: "Spin Attack",
      kind: "skill",
      school: "blade",
      icon: "spin",
      summary: "A whirling swing at every enemy around you.",
      mp: 0,
      cast_ms: 0,
      cooldown_ms: 8_000,
      target: "none",
      range_m: 0,
      effect: Map.merge(@effect_defaults, %{type: "spin", mult: 0.9, reach_m: 0.6, max: 8})
    },
    skill("cleave", "Cleave", "blade", "cleave", "strike", "none", 4, 5, 0,
      mult: 1.25, arc: 140, extra_reach: 0.5,
      description: "Sweeps your blade in a wide frontal arc, cleaving up to 4 enemies for 125% weapon damage."
    ),
    skill("mortal_strike", "Mortal Strike", "blade", "sword", "strike", "none", 6, 6, 0,
      mult: 1.65, extra_reach: 0.4,
      description: "Delivers a vicious overhead slash for 165% weapon damage."
    ),
    skill("rend", "Rend", "blade", "slash", "strike", "none", 4, 5, 0,
      mult: 1.0, dot_ticks: 4, dot_ratio: 0.45, extra_reach: 0.3,
      description: "Tears open a jagged wound that bleeds your target over 8 seconds."
    ),
    skill("execute", "Execute", "blade", "cleave", "strike", "none", 8, 8, 0,
      mult: 1.4, execute_mult: 2.4, extra_reach: 0.5,
      description: "Attempts to finish off a wounded foe, dealing 240% weapon damage to targets below 35% health."
    ),
    skill("bladestorm", "Bladestorm", "blade", "spin", "spin", "self", 10, 12, 0,
      mult: 1.45, extra_reach: 1.1, dot_ticks: 3, dot_ratio: 0.35,
      description: "Becomes a relentless cyclone of steel, slashing all nearby enemies and leaving them bleeding."
    ),
    skill("riposte", "Riposte", "blade", "daggers", "strike", "none", 5, 7, 0,
      mult: 1.35, temp_ac: 10, shield_hp: 15, duration_ms: 8000,
      description: "Parries and counters with a swift thrust while raising your guard (+10 AC and absorb ward)."
    ),
    skill("lunge", "Lunge", "blade", "sword", "dash", "none", 5, 7, 0,
      dash_m: 7.0, mult: 1.35, extra_reach: 1.2,
      description: "Lunges 7 metres forward blade-first, impaling foes in your path."
    ),
    skill("sunder_armor", "Sunder Armor", "blade", "fracture", "strike", "none", 4, 5, 0,
      mult: 1.2, temp_dmg_pct: 12, duration_ms: 10000,
      description: "Hacks at your foe's armour, dealing 120% weapon damage and increasing your damage by 12%."
    ),
    skill("blade_wave", "Blade Wave", "blade", "slash", "cone", "none", 7, 8, 10,
      arc: 90, base: 14, per_level: 3.4, mult: 1.3,
      description: "Slashes the air to send a crescent wave of razor wind across a 10 m frontal cone."
    ),

    # =========================================================================
    # 2. BERSERKER / RAGE ARCHETYPE (10 skills)
    # =========================================================================
    skill("berserk", "Berserk", "berserk", "flame", "buff_temp", "self", 6, 20, 0,
      base: 10, per_level: 2.0, duration_ms: 14000, temp_dmg_pct: 30, temp_crit: 0.10,
      description: "Enters a blood rage for 14 seconds, increasing melee and spell damage by 30% and crit by 10%."
    ),
    skill("frenzied_blows", "Frenzied Blows", "berserk", "daggers", "strike", "none", 6, 6, 0,
      mult: 1.55, arc: 110, extra_reach: 0.4,
      description: "Unleashes a savage flurry of blows in front of you for 155% weapon damage."
    ),
    skill("bloodthirst", "Bloodthirst", "berserk", "fangs", "strike", "none", 6, 6, 0,
      mult: 1.4, drain_pct: 65, extra_reach: 0.4,
      description: "Strikes with primal hunger, healing you for 65% of the damage dealt."
    ),
    skill("rampage", "Rampage", "berserk", "burst", "spin", "self", 9, 9, 0,
      mult: 1.35, extra_reach: 0.9, temp_dmg_pct: 15, duration_ms: 8000,
      description: "Thrashes wildly at every enemy around you and builds +15% damage for 8 seconds."
    ),
    skill("battle_trance", "Battle Trance", "berserk", "eye", "buff_temp", "self", 4, 18, 0,
      base: 16, per_level: 3.5, duration_ms: 15000, temp_crit: 0.18, mp_restore: 12,
      description: "Sharpens your killer instinct, healing you, restoring mana, and adding +18% crit chance."
    ),
    skill("leap_slam", "Leap Slam", "berserk", "boot", "dash", "none", 8, 9, 0,
      dash_m: 9.0, radius: 5.0, base: 14, per_level: 3.2, mult: 1.4, stun_ms: 2000,
      description: "Leaps 9 metres forward and slams the ground, damaging and stunning nearby enemies."
    ),
    skill("enrage", "Enrage", "berserk", "flame", "buff_temp", "self", 4, 16, 0,
      base: 14, per_level: 3.0, duration_ms: 12000, temp_dmg_pct: 22, mp_restore: 10,
      description: "Channels raw fury into strength, restoring health and mana while boosting damage by 22%."
    ),
    skill("reckless_swing", "Reckless Swing", "berserk", "cleave", "strike", "none", 8, 8, 0,
      mult: 1.95, extra_reach: 0.6, temp_crit: 0.25,
      description: "Throws your whole weight into a devastating haymaker for 195% weapon damage."
    ),
    skill("skull_splitter", "Skull Splitter", "berserk", "skull", "strike", "none", 7, 8, 0,
      mult: 1.5, stun_ms: 2500, dot_ticks: 3, dot_ratio: 0.35, extra_reach: 0.4,
      description: "Brings your weapon down on the target's skull, stunning them for 2.5 seconds and causing bleeding."
    ),
    skill("unstoppable", "Unstoppable", "berserk", "boot", "dash", "none", 6, 14, 0,
      dash_m: 6.0, shield_hp: 24, temp_ac: 10, duration_ms: 10000,
      description: "Shrugs off roots and snares, surging forward with an unbreakable absorb barrier."
    ),

    # =========================================================================
    # 3. BLUNT / EARTHSHAKER ARCHETYPE (10 skills)
    # =========================================================================
    skill("concussive_blow", "Concussive Blow", "blunt", "hammer", "strike", "none", 5, 7, 0,
      mult: 1.3, stun_ms: 3000, extra_reach: 0.4,
      description: "Rings your target's bell with a heavy blunt strike, stunning them for 3 seconds."
    ),
    skill("ground_slam", "Ground Slam", "blunt", "quake", "cone", "none", 6, 7, 8,
      arc: 110, base: 13, per_level: 3.0, mult: 1.25, slow_ms: 5000,
      description: "Smashes the ground in front of you, sending a shockwave that damages and slows foes."
    ),
    skill("shatter", "Shatter", "blunt", "fracture", "strike", "none", 6, 6, 0,
      mult: 1.6, extra_reach: 0.5, temp_crit: 0.20,
      description: "Delivers a bone-shattering blow with high critical chance."
    ),
    skill("earthshaker", "Earthshaker", "blunt", "quake", "aoe", "self", 10, 11, 0,
      radius: 6.5, base: 16, per_level: 3.6, stun_ms: 2200, knockback_m: 2.5,
      description: "Slams the earth with titanic force, stunning and knocking back every creature around you."
    ),
    skill("crushing_blow", "Crushing Blow", "blunt", "hammer", "strike", "none", 7, 7, 0,
      mult: 1.8, extra_reach: 0.4,
      description: "A two-fisted overhead crush that deals 180% weapon damage."
    ),
    skill("seismic_wave", "Seismic Wave", "blunt", "spikes", "cone", "none", 8, 8, 12,
      arc: 75, base: 16, per_level: 3.6, stun_ms: 1500,
      description: "Rips a line of seismic fault-spikes 12 metres forward through the ground."
    ),
    skill("pulverize", "Pulverize", "blunt", "hammer", "strike", "none", 6, 6, 0,
      mult: 1.45, arc: 120, slow_ms: 4000, extra_reach: 0.4,
      description: "Pummels enemies in front of you, dealing 145% weapon damage and dazing them."
    ),
    skill("bonebreaker", "Bonebreaker", "blunt", "fracture", "strike", "none", 6, 7, 0,
      mult: 1.4, slow_ms: 7000, dot_ticks: 3, dot_ratio: 0.35, extra_reach: 0.4,
      description: "Cripples your target's limbs, slowing them for 7 seconds and causing internal trauma."
    ),
    skill("staff_sweep", "Staff Sweep", "blunt", "spin", "spin", "self", 5, 7, 0,
      mult: 1.1, extra_reach: 1.0, slow_ms: 4000,
      description: "Sweeps a wide circle around you, knocking nearby enemies off balance."
    ),
    skill("meteor_hammer", "Meteor Hammer", "blunt", "meteor", "aoe", "enemy", 9, 10, 14,
      radius: 5.0, base: 17, per_level: 3.8, stun_ms: 1800,
      description: "Whirls and slams a blazing impact onto your target, scorching nearby foes."
    ),

    # =========================================================================
    # 4. POLEARM / DRAGOON ARCHETYPE (10 skills)
    # =========================================================================
    skill("impale", "Impale", "polearm", "spear", "strike", "none", 5, 5, 0,
      mult: 1.4, extra_reach: 1.4, dot_ticks: 3, dot_ratio: 0.4,
      description: "A long-reach polearm thrust that skewers the target and leaves them bleeding."
    ),
    skill("wide_sweep", "Wide Sweep", "polearm", "spin", "strike", "none", 6, 6, 0,
      mult: 1.25, arc: 220, extra_reach: 1.2,
      description: "Sweeps your polearm across a huge 220° arc, striking all foes at extended reach."
    ),
    skill("pole_vault", "Pole Vault", "polearm", "boot", "dash", "none", 6, 8, 0,
      dash_m: 9.0, radius: 4.5, base: 13, per_level: 3.0, mult: 1.35,
      description: "Vaults 9 metres forward on your weapon and slams down on enemies at the landing spot."
    ),
    skill("skewer", "Skewer", "polearm", "spear", "cone", "none", 6, 6, 9,
      arc: 55, base: 15, per_level: 3.4, root_ms: 2500,
      description: "Drives a piercing thrust straight ahead, pinning enemies in a narrow line."
    ),
    skill("javelin_throw", "Javelin Throw", "polearm", "spear", "damage", "enemy", 5, 5, 26,
      base: 15, per_level: 3.5, slow_ms: 4000, speed_m: 32,
      description: "Hurls a spectral javelin up to 26 metres, impaling and slowing a distant target."
    ),
    skill("hook", "Hook", "polearm", "spear", "damage", "enemy", 6, 9, 18,
      base: 11, per_level: 2.5, pull_m: 6.0, root_ms: 2500, speed_m: 34,
      description: "Snags a distant target with a halberd hook, yanking them toward you and holding them."
    ),
    skill("cyclone_of_steel", "Cyclone of Steel", "polearm", "spiral", "spin", "self", 8, 9, 0,
      mult: 1.35, extra_reach: 1.4,
      description: "Whirls your polearm overhead in a wide 360° vortex of steel."
    ),
    skill("phalanx", "Phalanx", "polearm", "shield", "shield", "self", 7, 16, 0,
      base: 22, per_level: 4.5, duration_ms: 15000, temp_ac: 12, temp_dmg_pct: 10,
      description: "Sets a spear-wall stance, granting an absorb shield, +12 AC, and +10% damage."
    ),
    skill("piercing_thrust", "Piercing Thrust", "polearm", "spear", "strike", "none", 6, 5, 0,
      mult: 1.55, extra_reach: 1.5, temp_crit: 0.20,
      description: "A lightning-fast precision thrust at long reach with +20% critical chance."
    ),
    skill("dragoon_dive", "Dragoon Dive", "polearm", "wing", "dash", "none", 10, 12, 0,
      dash_m: 11.0, radius: 5.5, base: 20, per_level: 4.4, stun_ms: 2000,
      description: "Leaps high into the air and crashes down 11 metres ahead in a thunderous dragoon impact."
    ),

    # =========================================================================
    # 5. ROGUE / SHADOWBLADE ARCHETYPE (10 skills)
    # =========================================================================
    skill("backstab", "Backstab", "rogue", "dagger", "strike", "none", 5, 5, 0,
      mult: 1.65, temp_crit: 0.30, extra_reach: 0.4,
      description: "Lunges for a vital spot, dealing 165% weapon damage with +30% critical strike chance."
    ),
    skill("eviscerate", "Eviscerate", "rogue", "dagger", "strike", "none", 7, 7, 0,
      mult: 1.75, dot_ticks: 3, dot_ratio: 0.4, extra_reach: 0.4,
      description: "A ruthless finishing slash that deals heavy burst damage and deep bleeding."
    ),
    skill("poisoned_blade", "Poisoned Blade", "rogue", "droplet", "strike", "none", 5, 5, 0,
      mult: 1.15, dot_ticks: 5, dot_ratio: 0.48, slow_ms: 5000, extra_reach: 0.4,
      description: "Strikes with a venom-coated blade, poisoning and slowing the target over 10 seconds."
    ),
    skill("shadowstep", "Shadowstep", "rogue", "mask", "dash", "none", 6, 9, 0,
      dash_m: 10.0, radius: 4.0, base: 13, per_level: 3.0, temp_crit: 0.20, duration_ms: 6000,
      description: "Steps through the shadows 10 metres forward, striking foes on arrival and boosting crit."
    ),
    skill("fan_of_knives", "Fan of Knives", "rogue", "burst", "aoe", "self", 7, 7, 0,
      radius: 7.0, base: 13, per_level: 3.0, slow_ms: 4000,
      description: "Flings a 360° ring of throwing knives at every enemy around you."
    ),
    skill("smoke_bomb", "Smoke Bomb", "rogue", "smoke", "aoe", "self", 8, 14, 0,
      radius: 6.0, base: 8, per_level: 1.8, stun_ms: 2500, shield_hp: 20, temp_ac: 10, duration_ms: 10000,
      description: "Drops a choking smoke bomb that blinds nearby enemies and shrouds you in an evasive ward."
    ),
    skill("kidney_shot", "Kidney Shot", "rogue", "dagger", "strike", "none", 6, 10, 0,
      mult: 1.2, stun_ms: 3500, extra_reach: 0.4,
      description: "Delivers a precision blow to the kidneys that stuns your target for 3.5 seconds."
    ),
    skill("garrote", "Garrote", "rogue", "spiral", "strike", "none", 6, 8, 0,
      mult: 1.15, dot_ticks: 5, dot_ratio: 0.5, root_ms: 3000, extra_reach: 0.4,
      description: "Chokes and slices the target, rooting them briefly and inflicting a heavy bleed."
    ),
    skill("evasion", "Evasion", "rogue", "mask", "shield", "self", 6, 18, 0,
      base: 24, per_level: 5.0, duration_ms: 14000, temp_ac: 15, temp_crit: 0.12,
      description: "Melts into a shadow blur, granting a strong absorb ward, +15 AC, and +12% crit."
    ),
    skill("death_mark", "Death Mark", "rogue", "crosshair", "damage", "enemy", 7, 10, 20,
      base: 15, per_level: 3.5, dot_ticks: 4, dot_ratio: 0.4, temp_dmg_pct: 15, duration_ms: 12000,
      description: "Marks your quarry for death from afar, dealing shadow-blade damage and boosting your damage by 15%."
    ),

    # =========================================================================
    # 6. RANGER / ARCHERY ARCHETYPE (10 skills)
    # =========================================================================
    skill("aimed_shot", "Aimed Shot", "archery", "crosshair", "damage", "enemy", 6, 5, 34,
      base: 18, per_level: 4.2, temp_crit: 0.25, speed_m: 38,
      description: "Draws a carefully aimed long-range shot at your target with high critical chance."
    ),
    skill("multi_shot", "Multi-Shot", "archery", "arrow", "cone", "none", 7, 6, 18,
      arc: 85, base: 14, per_level: 3.3,
      description: "Looses a spread of arrows across a frontal cone, hitting every enemy in front of you."
    ),
    skill("rain_of_arrows", "Rain of Arrows", "archery", "arrow", "aoe", "enemy", 10, 9, 30,
      radius: 7.0, base: 16, per_level: 3.6, slow_ms: 4000,
      description: "Arcs a darkening volley skyward that rains arrows down over your target's area."
    ),
    skill("piercing_arrow", "Piercing Arrow", "archery", "arrow", "damage", "enemy", 6, 5, 34,
      base: 17, per_level: 3.9, speed_m: 40,
      description: "Fires a bodkin-tipped shaft that punches cleanly through heavy hides and armour."
    ),
    skill("explosive_arrow", "Explosive Arrow", "archery", "burst", "aoe", "enemy", 9, 8, 30,
      radius: 5.5, base: 16, per_level: 3.7, dot_ticks: 3, dot_ratio: 0.35,
      description: "Fires an alchemical arrow that detonates on impact, scorching nearby creatures."
    ),
    skill("frost_arrow", "Frost Arrow", "archery", "arrow", "damage", "enemy", 5, 5, 32,
      base: 13, per_level: 3.0, root_ms: 3000, slow_ms: 6000, speed_m: 36,
      description: "Fires an ice-crested arrow that freezes your target's footing and slows them."
    ),
    skill("volley", "Volley", "archery", "arrow", "aoe", "enemy", 11, 10, 28,
      radius: 6.5, base: 15, per_level: 3.4, dot_ticks: 3, dot_ratio: 0.4,
      description: "Unleashes a rapid barrage of arrows that blankets the target area."
    ),
    skill("disengage", "Disengage", "archery", "boot", "dash", "none", 4, 9, 0,
      dash_m: -8.0, radius: 4.5, base: 10, per_level: 2.2, slow_ms: 3500,
      description: "Vaults 8 metres backward away from danger while firing a parting snare shot."
    ),
    skill("hunters_mark", "Hunter's Mark", "archery", "crosshair", "damage", "enemy", 5, 8, 34,
      base: 12, per_level: 2.8, temp_dmg_pct: 16, temp_crit: 0.12, duration_ms: 15000, speed_m: 40,
      description: "Pins a hunter's sigil on your target, dealing ranged damage and boosting your attacks by 16%."
    ),
    skill("serpent_sting", "Serpent Sting", "archery", "droplet", "damage", "enemy", 5, 5, 32,
      base: 9, per_level: 2.2, dot_ticks: 5, dot_ratio: 0.48, speed_m: 36,
      description: "Looses a wyvern-venom arrow that poisons your target over 10 seconds."
    ),

    # =========================================================================
    # 7. GUARDIAN / SHIELD ARCHETYPE (10 skills)
    # =========================================================================
    skill("shield_bash", "Shield Bash", "shield", "shield", "strike", "none", 4, 6, 0,
      mult: 1.25, stun_ms: 3000, extra_reach: 0.4,
      description: "Slams your shield into the target's face, dealing damage and stunning them for 3 seconds."
    ),
    skill("shield_wall", "Shield Wall", "shield", "shield", "shield", "self", 8, 22, 0,
      base: 32, per_level: 6.5, duration_ms: 18000, temp_ac: 22,
      description: "Raises an unbreakable wall of steel, granting a massive absorb ward and +22 AC."
    ),
    skill("taunt", "Taunt", "shield", "speaker", "taunt", "self", 4, 7, 0,
      radius: 14.0, temp_ac: 10, shield_hp: 15, duration_ms: 10000,
      description: "Bellows a challenge that forces nearby creatures to attack you while raising +10 AC."
    ),
    skill("shield_charge", "Shield Charge", "shield", "boot", "dash", "none", 6, 9, 0,
      dash_m: 8.5, radius: 4.5, base: 14, per_level: 3.2, stun_ms: 2500,
      description: "Charges 8.5 metres forward behind your shield, bowling over and stunning foes."
    ),
    skill("revenge", "Revenge", "shield", "daggers", "strike", "none", 5, 6, 0,
      mult: 1.45, arc: 140, drain_pct: 40, temp_ac: 8, duration_ms: 8000,
      description: "Cleaves enemies in front of you in retaliation, healing you and raising your guard."
    ),
    skill("bulwark", "Bulwark", "shield", "shield", "shield", "self", 7, 16, 0,
      base: 24, per_level: 5.0, duration_ms: 15000, temp_ac: 15,
      description: "Plants your feet like a fortress bastion, restoring health and raising a strong shield."
    ),
    skill("spiked_shield", "Spiked Shield", "shield", "burst", "aoe", "self", 6, 8, 0,
      radius: 5.5, base: 13, per_level: 3.0, dot_ticks: 3, dot_ratio: 0.35, temp_ac: 10, duration_ms: 10000,
      description: "Drives iron shield spikes into nearby foes and fortifies your armour."
    ),
    skill("last_stand", "Last Stand", "shield", "heart", "heal", "self", 8, 30, 0,
      base: 34, per_level: 7.5, temp_ac: 16, duration_ms: 15000,
      description: "Refuses to fall, surging a huge wave of hit points and +16 AC."
    ),
    skill("shield_slam", "Shield Slam", "shield", "shield", "strike", "none", 6, 6, 0,
      mult: 1.6, knockback_m: 3.0, extra_reach: 0.4,
      description: "Drives your full weight and armour into a bone-jarring shield slam."
    ),
    skill("guardians_oath", "Guardian's Oath", "shield", "shield_star", "shield", "self", 9, 20, 0,
      base: 26, per_level: 5.5, duration_ms: 16000, temp_ac: 14, temp_dmg_pct: 12,
      description: "Swears an oath of iron, shielding yourself and boosting AC by 14 and damage by 12%."
    ),

    # =========================================================================
    # 8. MONK / MARTIAL ARTS ARCHETYPE (10 skills)
    # =========================================================================
    skill("palm_strike", "Palm Strike", "monk", "hand", "strike", "none", 4, 4.5, 0,
      mult: 1.4, knockback_m: 3.5, extra_reach: 0.5,
      description: "Strikes with an open palm of focused chi, blasting the target backward."
    ),
    skill("flying_kick", "Flying Kick", "monk", "boot", "dash", "none", 5, 7, 0,
      dash_m: 8.0, radius: 4.0, base: 15, per_level: 3.5, mult: 1.4,
      description: "Launches into a flying kick 8 metres forward, crashing into enemies ahead."
    ),
    skill("hundred_fists", "Hundred Fists", "monk", "fist", "cone", "none", 7, 6, 6,
      arc: 100, base: 16, per_level: 3.7,
      description: "Unleashes a blinding gatling flurry of chi-charged punches in front of you."
    ),
    skill("leg_sweep", "Leg Sweep", "monk", "spin", "aoe", "self", 5, 8, 0,
      radius: 5.0, base: 11, per_level: 2.5, stun_ms: 2800,
      description: "Drops into a 360° spinning leg sweep that knocks all nearby enemies off their feet."
    ),
    skill("inner_peace", "Inner Peace", "monk", "lotus", "heal", "self", 4, 16, 0,
      base: 22, per_level: 5.0, mp_restore: 18,
      description: "Centers your breathing and chi, restoring hit points and mana."
    ),
    skill("chi_burst", "Chi Burst", "monk", "sun", "cone", "none", 7, 8, 12,
      arc: 80, base: 16, per_level: 3.6, drain_pct: 45,
      description: "Projects a sphere of golden chi forward that blasts enemies and mends your wounds."
    ),
    skill("iron_body", "Iron Body", "monk", "shield", "shield", "self", 6, 18, 0,
      base: 24, per_level: 5.0, duration_ms: 16000, temp_ac: 16,
      description: "Tempers your body like forged iron, absorbing damage and raising AC by 16."
    ),
    skill("nerve_strike", "Nerve Strike", "monk", "hand", "strike", "none", 6, 9, 0,
      mult: 1.25, stun_ms: 3800, extra_reach: 0.4,
      description: "Strikes a vital meridian point, paralyzing your target for 3.8 seconds."
    ),
    skill("combat_roll", "Combat Roll", "monk", "spiral", "dash", "none", 4, 6, 0,
      dash_m: 7.5, shield_hp: 14, temp_ac: 6, duration_ms: 6000,
      description: "Tumbles 7.5 metres forward, breaking roots and gaining an evasive ward."
    ),
    skill("dragon_punch", "Dragon Punch", "monk", "fist", "strike", "none", 8, 8, 0,
      mult: 1.85, stun_ms: 2200, extra_reach: 0.6,
      description: "A rising uppercut wreathed in fiery dragon chi for 185% damage and a stun."
    ),

    # =========================================================================
    # 9. WARLORD / SHOUTS & BANNERS ARCHETYPE (10 skills)
    # =========================================================================
    skill("battle_shout", "Battle Shout", "warlord", "speaker", "buff_temp", "self", 6, 18, 0,
      base: 12, per_level: 2.5, duration_ms: 18000, temp_dmg_pct: 22, temp_ac: 6,
      description: "Thunders a war cry that bolsters your health and increases all damage by 22% for 18 seconds."
    ),
    skill("intimidating_shout", "Intimidating Shout", "warlord", "skull", "aoe", "self", 7, 14, 0,
      radius: 7.0, base: 10, per_level: 2.2, stun_ms: 3500,
      description: "Unleashes a terrifying roar that freezes all nearby enemies in fear for 3.5 seconds."
    ),
    skill("rallying_cry", "Rallying Cry", "warlord", "flag", "heal", "self", 7, 18, 0,
      base: 24, per_level: 5.2, temp_ac: 10, duration_ms: 12000,
      description: "Sounds a rallying cry that restores hit points and fortifies your armour."
    ),
    skill("war_banner", "War Banner", "warlord", "flag", "aoe", "self", 9, 16, 0,
      radius: 7.5, base: 15, per_level: 3.4, temp_dmg_pct: 20, temp_crit: 0.12, duration_ms: 15000,
      description: "Plants a crimson war standard that blasts nearby foes and empowers your attacks by 20%."
    ),
    skill("demoralizing_roar", "Demoralizing Roar", "warlord", "speaker", "aoe", "self", 6, 10, 0,
      radius: 7.5, base: 12, per_level: 2.8, slow_ms: 6000,
      description: "Bellows a deafening roar that batters and slows every creature around you."
    ),
    skill("charge", "Charge", "warlord", "boot", "dash", "none", 5, 8, 0,
      dash_m: 9.5, radius: 4.5, base: 13, per_level: 3.0, stun_ms: 2000,
      description: "Rushes 9.5 metres forward at breakneck speed, slamming and stunning foes in your path."
    ),
    skill("commanding_presence", "Commanding Presence", "warlord", "crown", "shield", "self", 8, 20, 0,
      base: 26, per_level: 5.5, duration_ms: 18000, temp_ac: 12, temp_dmg_pct: 15,
      description: "Commands the battlefield, granting a strong absorb shield, +12 AC, and +15% damage."
    ),
    skill("piercing_howl", "Piercing Howl", "warlord", "speaker", "aoe", "self", 5, 9, 0,
      radius: 8.0, base: 10, per_level: 2.4, root_ms: 3000, slow_ms: 6000,
      description: "Lets loose an ear-splitting howl that dazes, roots, and slows all nearby creatures."
    ),
    skill("second_wind", "Second Wind", "warlord", "wind", "heal", "self", 4, 15, 0,
      base: 18, per_level: 4.0, hot_ticks: 4, hot_ratio: 0.45,
      description: "Catches a second wind in the thick of battle, healing immediately and over 8 seconds."
    ),
    skill("avatar_of_war", "Avatar of War", "warlord", "crown", "buff_temp", "self", 10, 28, 0,
      base: 22, per_level: 5.0, duration_ms: 16000, temp_dmg_pct: 30, temp_ac: 16, temp_crit: 0.12,
      description: "Ascends as an Avatar of War for 16 seconds: +30% damage, +16 AC, +12% crit, and a surge of health."
    ),

    # =========================================================================
    # 10. SURVIVAL / TRAPS & GADGETS ARCHETYPE (10 skills)
    # =========================================================================
    skill("bear_trap", "Bear Trap", "survival", "trap", "aoe", "self", 5, 9, 0,
      radius: 5.5, base: 14, per_level: 3.2, root_ms: 5500, dot_ticks: 3, dot_ratio: 0.4,
      description: "Snaps serrated steel jaws shut on nearby foes, bleeding and holding them fast for 5.5 seconds."
    ),
    skill("explosive_trap", "Explosive Trap", "survival", "trap", "aoe", "self", 7, 10, 0,
      radius: 6.5, base: 16, per_level: 3.6, dot_ticks: 3, dot_ratio: 0.35,
      description: "Triggers a black-powder shrapnel trap that blasts and burns all nearby creatures."
    ),
    skill("frost_trap", "Frost Trap", "survival", "trap", "aoe", "self", 6, 10, 0,
      radius: 6.5, base: 11, per_level: 2.5, root_ms: 4000, slow_ms: 7000,
      description: "Triggers an alchemical frost trap that freezes and chills all nearby enemies."
    ),
    skill("caltrops", "Caltrops", "survival", "spikes", "aoe", "self", 4, 8, 0,
      radius: 6.0, base: 10, per_level: 2.3, slow_ms: 7000, dot_ticks: 3, dot_ratio: 0.35,
      description: "Scatters spiked iron caltrops around you that pierce and slow pursuing enemies."
    ),
    skill("throw_net", "Throw Net", "survival", "net", "root", "enemy", 5, 8, 22,
      duration_ms: 5500, root_ms: 5500, base: 8, per_level: 1.8,
      description: "Hurls a weighted hunting net up to 22 metres, holding your target fast for 5.5 seconds."
    ),
    skill("feign_death", "Feign Death", "survival", "skull", "shield", "self", 4, 18, 0,
      base: 20, per_level: 4.2, duration_ms: 12000, temp_ac: 14,
      description: "Drops low in a survival ruse, shielding you from harm and raising AC by 14."
    ),
    skill("camouflage", "Camouflage", "survival", "mask", "heal", "self", 5, 15, 0,
      base: 18, per_level: 4.0, hot_ticks: 3, hot_ratio: 0.4, temp_ac: 8, duration_ms: 12000,
      description: "Blends into the brush, tending wounds over time and raising your defence."
    ),
    skill("aspect_of_the_cheetah", "Aspect of the Cheetah", "survival", "paw", "dash", "none", 4, 9, 0,
      dash_m: 9.5, temp_crit: 0.12, duration_ms: 10000,
      description: "Bounds 9.5 metres forward with feline grace and heightens your reflexes."
    ),
    skill("bandage", "Bandage", "survival", "bandage", "heal", "friendly", 3, 8, 10,
      base: 18, per_level: 4.2,
      description: "Binds wounds with clean linen, restoring hit points to yourself or a nearby ally."
    ),
    skill("volatile_flask", "Volatile Flask", "survival", "flask", "aoe", "enemy", 8, 9, 24,
      radius: 6.0, base: 17, per_level: 3.8, dot_ticks: 3, dot_ratio: 0.4,
      description: "Hurls a volatile alchemist's flask that shatters in a fiery acid burst."
    )
  ]

  @buffs [
    buff("hp_10", "Vigor", "heart", "max_hp", 10, "+10 maximum hit points."),
    buff("mp_10", "Insight", "droplet", "max_mp", 10, "+10 maximum mana."),
    buff("hp_25", "Greater Vigor", "heart", "max_hp", 25, "+25 maximum hit points."),
    buff("mp_25", "Greater Insight", "droplet", "max_mp", 25, "+25 maximum mana."),
    buff("might_5", "Might", "fist", "melee_pct", 5, "+5% melee damage."),
    buff("arcana_5", "Arcana", "star", "spell_pct", 5, "+5% spell damage and healing.")
  ]

  @abilities @spells ++ @skills ++ @buffs
  @by_id Map.new(@abilities, &{&1.id, &1})

  @doc "Every ability."
  def all, do: @abilities

  @doc "An ability by id, or nil."
  def get(id) when is_binary(id), do: Map.get(@by_id, id)
  def get(_), do: nil

  def spell?(%{kind: "spell"}), do: true
  def spell?(_), do: false

  def skill?(%{kind: "skill"}), do: true
  def skill?(_), do: false

  @doc "Castable (a spell or a skill), as opposed to a buff."
  def active?(%{kind: k}) when k in ["spell", "skill"], do: true
  def active?(_), do: false

  @doc "What the client needs about every ability (keyed by id)."
  def payload do
    @abilities
    |> Enum.with_index(1)
    |> Map.new(fn {a, idx} ->
      {a.id,
       a
       |> Map.take([:id, :name, :kind, :school, :icon, :summary, :mp, :cast_ms, :cooldown_ms, :target, :range_m])
       |> Map.put(:order, idx)
       |> Map.put(:effect, Map.take(a.effect, [:type, :stat, :amount, :ms, :duration_ms, :radius_m, :arc, :dash_m, :jumps]))}
    end)
  end

  @doc "Heal or damage numbers of an ability at a level, before bonuses."
  def amount(%{effect: %{base: base, per_level: per}}, level) when is_number(base) and is_number(per),
    do: round(base + per * max(level - 1, 0))

  def amount(_, _), do: 0
end

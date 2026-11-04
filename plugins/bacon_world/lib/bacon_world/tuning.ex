defmodule BaconWorld.Tuning do
  @moduledoc """
  World and combat tuning (`BaconWorldWeb.Admin.TuningLive`, `/admin/bacon_world/tuning`).

  Holds the constants that govern melee damage, critical hits, heavy swings, spell criticals,
  armour class (AC) mitigation, creature scaling, experience and regeneration. Stored in
  `bacon_world_skill_trees` under slug `"tuning"` and cached in `:persistent_term` so every
  swing and spell reads it without a database query.

  ## Damage & Mitigation Formulas

  ### 1. Melee & Ranged Weapon Damage (`BaconWorld.Melee`)
  Each equipped weapon has a base `dmg` (maximum base roll) and `dly` (tenths of a second
  between swings; an empty hand is Fist: DMG 3, DLY 9).

    * **Hit Chance**: `clamp(0.85 + (attacker_level - defender_level) * 0.03, 0.35, 0.96)`
    * **Base Roll**: uniform integer in `max(1, round(dmg * 0.45)) .. (dmg + floor(level / melee_level_div))`
    * **Heavy Swing** (two-handed right-click): multiplies damage by `heavy_swing_mult` (default `1.5×`)
      and swing delay by `heavy_swing_delay` (default `1.4×`).
    * **Skill / Ability Multiplier**: weapon skills apply their own `mult` (e.g. `0.9×` on Spin Attack,
      `1.8×` on Crushing Blow, `2.2×` on Execute below 35% target HP).
    * **Might & Stance Buffs**: passive skill-tree Might nodes (`+5%` each) and active combat shouts/stances
      add `melee_pct`, multiplying damage by `1.0 + melee_pct / 100`.
    * **Critical Hit**: `melee_crit_chance` (default `6%`, plus any skill/buff crit bonus) to multiply
      damage by `melee_crit_mult` (default `1.75×`).

  ### 2. Spell & Ability Damage / Healing (`BaconWorld.Abilities`, `BaconWorldWeb.SkillEvents`)
    * **Level Scaling**: `round(base + (level - 1) * per_level)`
    * **Arcana & Spell Buffs**: passive skill-tree Arcana nodes (`+5%` each) and active spell wards/trances
      add `spell_pct`, multiplying spell damage and healing by `1.0 + spell_pct / 100`.
    * **Spell Critical**: damaging spells have a `spell_crit_chance` (default `5%`, plus crit bonuses)
      to multiply damage by `spell_crit_mult` (default `1.5×`).

  ### 3. Armour Class (AC) & Absorb Shields
  Every worn garment, hat and shield contributes its `ac` (`BaconWorld.Items`), and defensive
  spells/skills can grant temporary bonus AC and an absorb barrier.

    * **AC Mitigation Curve** (hyperbolic, diminishing returns):
      `reduction = min(ac_max_mitigation, ac / (ac + ac_soft_cap))`
      With default `ac_soft_cap = 50` and `ac_max_mitigation = 0.75` (75% cap):
      - `0 AC`  → `0%` reduction
      - `10 AC` → `16.7%` reduction
      - `25 AC` → `33.3%` reduction
      - `50 AC` → `50.0%` reduction
    * **Mitigated Damage**: `max(1, round(raw_damage * (1.0 - reduction)))`
    * **Absorb Shields**: any remaining damage is subtracted from active absorb shields (`Fire Shield`,
      `Ice Barrier`, `Mana Shield`, `Divine Shield`, `Shield Wall`, etc.) before reducing HP.
  """

  alias Bacon8.GamesRepo
  alias BaconWorld.SkillTreeRecord

  @slug "tuning"
  @cache_key {__MODULE__, :current}

  @defaults %{
    "melee_level_div" => 3.0,
    "melee_crit_chance" => 0.06,
    "melee_crit_mult" => 1.75,
    "heavy_swing_mult" => 1.5,
    "heavy_swing_delay" => 1.4,
    "spell_crit_chance" => 0.05,
    "spell_crit_mult" => 1.5,
    "ac_soft_cap" => 50.0,
    "ac_max_mitigation" => 0.75,
    "mob_damage_mult" => 1.0,
    "mob_hp_mult" => 1.0,
    "xp_mult" => 1.0,
    "regen_interval_ms" => 4000.0,
    "regen_pool_div" => 12.0,
    "pvp_damage_mult" => 1.0,
    # 2026-11-03, the Bestiary (BaconWorld.Mobs.Camps, BaconWorld.Loot, BaconWorld.LiveEvents)
    "xp_curve_mult" => 1.0,
    "rank_elite_xp_mult" => 1.5,
    "rank_rare_xp_mult" => 2.0,
    "rank_boss_xp_mult" => 1.0,
    "elite_hp_mult" => 1.8,
    "elite_dmg_mult" => 1.35,
    "elite_xp_mult" => 2.0,
    "loot_chance_mult" => 1.0,
    "coin_mult" => 1.0
  }

  @specs [
    %{key: "melee_level_div", label: "Levels per +1 weapon damage", group: "Melee & Ranged", min: 1.0, max: 10.0, step: 0.5, unit: "lvls", desc: "Divisor in floor(level / N) added to weapon maximum damage."},
    %{key: "melee_crit_chance", label: "Base melee crit chance", group: "Melee & Ranged", min: 0.0, max: 0.5, step: 0.01, unit: "ratio", desc: "Base probability (0.06 = 6%) of a critical melee or bow hit."},
    %{key: "melee_crit_mult", label: "Melee crit multiplier", group: "Melee & Ranged", min: 1.1, max: 4.0, step: 0.05, unit: "×", desc: "Damage multiplier on a critical melee or bow hit."},
    %{key: "heavy_swing_mult", label: "Two-hand heavy swing damage", group: "Melee & Ranged", min: 1.0, max: 3.0, step: 0.05, unit: "×", desc: "Damage multiplier on a two-handed right-click heavy swing."},
    %{key: "heavy_swing_delay", label: "Two-hand heavy swing delay", group: "Melee & Ranged", min: 1.0, max: 2.5, step: 0.05, unit: "×", desc: "Swing time multiplier on a two-handed right-click heavy swing."},
    %{key: "spell_crit_chance", label: "Base spell crit chance", group: "Spells & Abilities", min: 0.0, max: 0.5, step: 0.01, unit: "ratio", desc: "Base probability (0.05 = 5%) of a critical spell hit."},
    %{key: "spell_crit_mult", label: "Spell crit multiplier", group: "Spells & Abilities", min: 1.1, max: 3.5, step: 0.05, unit: "×", desc: "Damage multiplier on a critical spell hit."},
    %{key: "ac_soft_cap", label: "Armour Class 50% midpoint (K)", group: "Armour & Mitigation", min: 10.0, max: 200.0, step: 5.0, unit: "AC", desc: "AC required for 50% damage reduction in AC / (AC + K)."},
    %{key: "ac_max_mitigation", label: "Maximum AC mitigation cap", group: "Armour & Mitigation", min: 0.1, max: 0.9, step: 0.05, unit: "ratio", desc: "Highest fraction of damage that armour AC can absorb (0.75 = 75%)."},
    %{key: "mob_damage_mult", label: "Creature damage multiplier", group: "World & Progression", min: 0.25, max: 3.0, step: 0.05, unit: "×", desc: "Scales all incoming creature melee and special damage."},
    %{key: "mob_hp_mult", label: "Creature health multiplier", group: "World & Progression", min: 0.25, max: 4.0, step: 0.05, unit: "×", desc: "Scales creature hit points when spawned."},
    %{key: "xp_mult", label: "Experience multiplier", group: "World & Progression", min: 0.25, max: 5.0, step: 0.1, unit: "×", desc: "Scales experience awarded for slaying creatures."},
    %{key: "regen_interval_ms", label: "Regeneration tick interval", group: "World & Progression", min: 1000.0, max: 15000.0, step: 500.0, unit: "ms", desc: "Milliseconds between natural HP/MP regeneration ticks."},
    %{key: "regen_pool_div", label: "Regeneration pool divisor", group: "World & Progression", min: 4.0, max: 40.0, step: 1.0, unit: "div", desc: "Each tick restores 1/N of max HP and max MP."},
    %{key: "pvp_damage_mult", label: "PvP damage multiplier", group: "World & Progression", min: 0.25, max: 2.0, step: 0.05, unit: "×", desc: "Scales damage dealt between PvP-flagged players."},
    %{key: "xp_curve_mult", label: "Experience to level", group: "Creatures, Loot & Experience", min: 0.25, max: 4.0, step: 0.05, unit: "×", desc: "Scales the experience every level needs (below 1 levels come faster)."},
    %{key: "rank_elite_xp_mult", label: "Elite-rank monster experience", group: "Creatures, Loot & Experience", min: 0.5, max: 10.0, step: 0.1, unit: "×", desc: "Experience for monster types ranked Elite on the Bestiary page."},
    %{key: "rank_rare_xp_mult", label: "Rare-rank monster experience", group: "Creatures, Loot & Experience", min: 0.5, max: 10.0, step: 0.1, unit: "×", desc: "Experience for monster types ranked Rare (named spawns)."},
    %{key: "rank_boss_xp_mult", label: "Boss experience", group: "Creatures, Loot & Experience", min: 0.5, max: 20.0, step: 0.1, unit: "×", desc: "Experience for bosses. At 1 a boss is worth what any creature of its level is."},
    %{key: "elite_hp_mult", label: "Camp elite health", group: "Creatures, Loot & Experience", min: 1.0, max: 5.0, step: 0.05, unit: "×", desc: "Hit points of an elite rolled by a camp's elite chance."},
    %{key: "elite_dmg_mult", label: "Camp elite damage", group: "Creatures, Loot & Experience", min: 1.0, max: 3.0, step: 0.05, unit: "×", desc: "Damage of a camp elite's attacks."},
    %{key: "elite_xp_mult", label: "Camp elite experience", group: "Creatures, Loot & Experience", min: 1.0, max: 10.0, step: 0.1, unit: "×", desc: "Experience for killing a camp elite (on top of its rank)."},
    %{key: "loot_chance_mult", label: "Loot chance multiplier", group: "Creatures, Loot & Experience", min: 0.1, max: 5.0, step: 0.05, unit: "×", desc: "Scales every drop chance (capped at 100%) and thins out the loot tables' empty rolls."},
    %{key: "coin_mult", label: "Coin multiplier", group: "Creatures, Loot & Experience", min: 0.1, max: 10.0, step: 0.05, unit: "×", desc: "Scales the coins creatures and cleared camps carry."}
  ]

  def defaults, do: @defaults
  def specs, do: @specs

  @doc "The active tuning map."
  def current do
    case :persistent_term.get(@cache_key, nil) do
      nil ->
        loaded = load_from_db()
        :persistent_term.put(@cache_key, loaded)
        loaded

      map ->
        map
    end
  end

  @doc "Reads a single tuning parameter by key."
  def get(key) when is_binary(key) do
    Map.get(current(), key, Map.get(@defaults, key))
  end

  @doc "Clears the cached tuning so the next read fetches from the database."
  def bust do
    :persistent_term.erase(@cache_key)
    :ok
  end

  @doc "Armour mitigation fraction (0.0..ac_max_mitigation) for a given total AC."
  def ac_reduction(ac) when is_number(ac) and ac > 0 do
    t = current()
    k = max(1.0, Map.get(t, "ac_soft_cap", 50.0))
    cap = Map.get(t, "ac_max_mitigation", 0.75)
    min(cap, ac / (ac + k))
  end

  def ac_reduction(_), do: 0.0

  @doc "Applies AC mitigation to raw incoming damage (always at least 1 when raw > 0)."
  def mitigate_ac(raw_damage, ac) when is_number(raw_damage) and raw_damage > 0 do
    red = ac_reduction(ac)
    max(1, round(raw_damage * (1.0 - red)))
  end

  def mitigate_ac(raw_damage, _ac), do: max(0, round(raw_damage || 0))

  @doc "Validates and saves tuning parameters."
  def save(params, user_id \\ nil) when is_map(params) do
    cleaned = sanitize(params)

    res =
      case GamesRepo.get_by(SkillTreeRecord, slug: @slug) do
        nil -> %SkillTreeRecord{slug: @slug}
        row -> row
      end
      |> Ecto.Changeset.change(data: cleaned, updated_by: user_id)
      |> GamesRepo.insert_or_update()

    case res do
      {:ok, _} ->
        :persistent_term.put(@cache_key, cleaned)
        {:ok, cleaned}

      {:error, _} = err ->
        err
    end
  end

  @doc "Resets all tuning parameters back to the shipped defaults."
  def reset(user_id \\ nil), do: save(@defaults, user_id)

  def sanitize(params) when is_map(params) do
    Map.new(@specs, fn spec ->
      raw = Map.get(params, spec.key, Map.get(@defaults, spec.key))
      val = parse_num(raw, Map.get(@defaults, spec.key))
      clamped = val |> max(spec.min) |> min(spec.max)
      {spec.key, clamped}
    end)
  end

  defp parse_num(v, _fallback) when is_float(v), do: v
  defp parse_num(v, _fallback) when is_integer(v), do: v * 1.0

  defp parse_num(v, fallback) when is_binary(v) do
    case Float.parse(String.trim(v)) do
      {f, _} -> f
      :error -> fallback
    end
  end

  defp parse_num(_, fallback), do: fallback

  defp load_from_db do
    try do
      case GamesRepo.get_by(SkillTreeRecord, slug: @slug) do
        %SkillTreeRecord{data: data} when is_map(data) -> sanitize(data)
        _ -> @defaults
      end
    rescue
      _ -> @defaults
    end
  end
end

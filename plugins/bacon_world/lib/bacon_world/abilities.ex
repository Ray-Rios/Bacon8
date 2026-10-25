defmodule BaconWorld.Abilities do
  @moduledoc """
  What the skill tree's nodes give (`BaconWorld.SkillTree`): spells, skills and buffs.
  Fixed data, like the item catalogue; the tree (which ability sits on which node) is
  the owner's to edit at /admin/bacon_world/skills.

    * **spell** - cast with mana, from the spell bar (two rows of ten, 1-0 and
      Shift+1-0). A spell with a cast time is interrupted by moving.
    * **skill** - a fighting move, on the special-attack keys (Q E F Z X).
    * **buff** - always on once learned: more hit points, mana, damage.

  `effect` says what it does (`BaconWorldWeb.SkillEvents` carries it out):

    * `%{type: "recall"}` - back to your bind point
    * `%{type: "heal", base, per_level}` - heals you or another player
    * `%{type: "damage", base, per_level, spread, speed_m}` - a projectile at a creature
    * `%{type: "root", ms}` - a creature can't move (it can still swing)
    * `%{type: "spin", mult, reach_m, max}` - a swing at everything around you
    * `%{type: "stat", stat, amount}` - a buff: `"max_hp"`, `"max_mp"` (points),
      `"melee_pct"`, `"spell_pct"` (percent more damage)

  Icons are drawn by the client (`skills-ui.ts` `ICONS`), keyed by `icon`.
  """

  @abilities [
    %{
      id: "recall",
      name: "Recall",
      kind: "spell",
      icon: "recall",
      summary: "Return to your bind point. Interrupted if you move.",
      mp: 0,
      cast_ms: 4_000,
      cooldown_ms: 60_000,
      target: "self",
      range_m: 0,
      effect: %{type: "recall"}
    },
    %{
      id: "heal",
      name: "Minor Healing",
      kind: "spell",
      icon: "heal",
      summary: "Heals you, or the player you have targeted.",
      mp: 8,
      cast_ms: 1_200,
      cooldown_ms: 4_000,
      target: "friendly",
      range_m: 25,
      effect: %{type: "heal", base: 14, per_level: 4}
    },
    %{
      id: "fireball",
      name: "Fireball",
      kind: "spell",
      icon: "fireball",
      summary: "Hurls a ball of fire at your target.",
      mp: 10,
      cast_ms: 900,
      cooldown_ms: 3_000,
      target: "enemy",
      range_m: 30,
      effect: %{type: "damage", base: 10, per_level: 3, spread: 0.2, speed_m: 22}
    },
    %{
      id: "root",
      name: "Entangling Roots",
      kind: "spell",
      icon: "root",
      summary: "Roots your target in place for 6 seconds. It can still fight back.",
      mp: 8,
      cast_ms: 600,
      cooldown_ms: 15_000,
      target: "enemy",
      range_m: 25,
      effect: %{type: "root", ms: 6_000}
    },
    %{
      id: "spin_attack",
      name: "Spin Attack",
      kind: "skill",
      icon: "spin",
      summary: "A whirling swing at every enemy around you.",
      mp: 0,
      cast_ms: 0,
      cooldown_ms: 8_000,
      target: "none",
      range_m: 0,
      effect: %{type: "spin", mult: 0.9, reach_m: 0.6, max: 8}
    },
    %{id: "hp_10", name: "Vigor", kind: "buff", icon: "hp", summary: "+10 maximum hit points.", effect: %{type: "stat", stat: "max_hp", amount: 10}},
    %{id: "mp_10", name: "Insight", kind: "buff", icon: "mp", summary: "+10 maximum mana.", effect: %{type: "stat", stat: "max_mp", amount: 10}},
    %{id: "hp_25", name: "Greater Vigor", kind: "buff", icon: "hp", summary: "+25 maximum hit points.", effect: %{type: "stat", stat: "max_hp", amount: 25}},
    %{id: "mp_25", name: "Greater Insight", kind: "buff", icon: "mp", summary: "+25 maximum mana.", effect: %{type: "stat", stat: "max_mp", amount: 25}},
    %{id: "might_5", name: "Might", kind: "buff", icon: "might", summary: "+5% melee damage.", effect: %{type: "stat", stat: "melee_pct", amount: 5}},
    %{id: "arcana_5", name: "Arcana", kind: "buff", icon: "arcana", summary: "+5% spell damage and healing.", effect: %{type: "stat", stat: "spell_pct", amount: 5}}
  ]

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
    Map.new(@abilities, fn a ->
      {a.id,
       a
       |> Map.take([:id, :name, :kind, :icon, :summary, :mp, :cast_ms, :cooldown_ms, :target, :range_m])
       |> Map.put(:effect, Map.take(a.effect, [:type, :stat, :amount, :ms]))}
    end)
  end

  @doc "Heal or damage numbers of an ability at a level, before bonuses."
  def amount(%{effect: %{base: base, per_level: per}}, level), do: base + per * max(level - 1, 0)
  def amount(_, _), do: 0
end

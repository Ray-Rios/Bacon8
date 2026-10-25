defmodule BaconWorld.Progression do
  @moduledoc """
  Levels and experience. There are no classes: every character starts the same
  and grows through one shared skill tree (Path of Exile style, but with a single
  central starting point for everyone). It is `BaconWorld.SkillTree`; each level
  banks a skill point for it (`stats["skill_points"]`, the total ever earned;
  `BaconWorld.Skills` works out what is left).

  Experience follows EverQuest's idea of "con": a creature far below you is worth
  nothing (grey), one at your level the full amount, tougher ones a little more.
  """

  alias BaconWorld.World

  @max_level 50

  def max_level, do: @max_level

  @doc "Experience needed to go from `level` to the next."
  def xp_to_next(level) when level >= @max_level, do: 0
  def xp_to_next(level) when level >= 1, do: round(60 * :math.pow(level, 1.6)) + 40

  @doc "Hit points at a level (before gear)."
  def max_hp(level), do: 40 + (level - 1) * 14

  @doc "Mana at a level."
  def max_mp(level), do: 20 + (level - 1) * 6

  @doc "Skill points earned by reaching `level` (one per level after the first)."
  def skill_points_for(level), do: max(0, level - 1)

  @doc """
  The colour a creature cons to you, EverQuest style, by its level minus yours:
  `:red`, `:yellow`, `:white` (even), `:blue`, `:light_blue`, `:green` or `:grey`.
  """
  def con(mob_level, player_level) do
    diff = mob_level - player_level
    # One or two below is still blue at low levels.
    green_at = max(2, ceil(player_level * 0.25) + 1)

    cond do
      diff >= 3 -> :red
      diff >= 1 -> :yellow
      diff == 0 -> :white
      -diff >= green_at + 2 -> :grey
      -diff >= green_at -> :green
      -diff >= max(1, green_at - 1) and player_level > 8 -> :light_blue
      true -> :blue
    end
  end

  @doc "Experience for killing a creature of `mob_level` at `player_level`."
  def kill_xp(mob_level, player_level) do
    base = 18 + mob_level * mob_level * 6

    scale =
      case con(mob_level, player_level) do
        :grey -> 0.0
        :green -> 0.35
        :light_blue -> 0.6
        :blue -> 0.8
        :white -> 1.0
        :yellow -> 1.15
        :red -> 1.3
      end

    round(base * scale)
  end

  @doc """
  Adds experience, levelling up as often as it covers (full HP/MP on a level,
  like EverQuest's ding). Returns `{:ok, progress}` (see `progress/1`) with
  `:levels_gained`.
  """
  def award_xp(character_id, amount) when is_integer(amount) and amount >= 0 do
    with {:ok, c} <- World.fetch_character(character_id) do
      level = World.stat(c, "level")
      {level2, xp2} = apply_xp(level, World.stat(c, "xp") + amount)
      gained = level2 - level
      # the skill tree's buffs ride on top of the level's pools (BaconWorld.Skills)
      bonus = if gained > 0, do: BaconWorld.Skills.bonuses_for_stats(c.stats), else: %{}

      patch =
        if gained > 0 do
          %{
            "level" => level2,
            "xp" => xp2,
            "max_hp" => max_hp(level2) + Map.get(bonus, "max_hp", 0),
            "hp" => max_hp(level2) + Map.get(bonus, "max_hp", 0),
            "max_mp" => max_mp(level2) + Map.get(bonus, "max_mp", 0),
            "mp" => max_mp(level2) + Map.get(bonus, "max_mp", 0),
            "skill_points" => World.stat(c, "skill_points") + gained
          }
        else
          %{"xp" => xp2}
        end

      World.merge_stats(World.by_id_query(c.id), patch)
      {:ok, c.stats |> Kernel.||(%{}) |> Map.merge(patch) |> progress() |> Map.put(:levels_gained, gained)}
    end
  end

  # Level and leftover experience after adding some.
  @doc false
  def apply_xp(level, xp) do
    need = xp_to_next(level)

    if level < @max_level and need > 0 and xp >= need,
      do: apply_xp(level + 1, xp - need),
      else: {level, if(level >= @max_level, do: 0, else: xp)}
  end

  @doc """
  Older characters were made with 10 HP and no level: brings their stats up to
  their level's numbers (never lowers anything). Returns the patch applied (empty
  when nothing changed).
  """
  def normalize_stats(character_id) do
    with {:ok, c} <- World.fetch_character(character_id) do
      level = World.stat(c, "level")
      bonus = BaconWorld.Skills.bonuses_for_stats(c.stats)
      want_hp = max_hp(level) + Map.get(bonus, "max_hp", 0)
      want_mp = max_mp(level) + Map.get(bonus, "max_mp", 0)

      patch =
        %{}
        |> then(&if(World.stat(c, "max_hp") < want_hp, do: Map.merge(&1, %{"max_hp" => want_hp, "hp" => want_hp}), else: &1))
        |> then(&if(World.stat(c, "max_mp") < want_mp, do: Map.merge(&1, %{"max_mp" => want_mp, "mp" => want_mp}), else: &1))

      if patch != %{}, do: World.merge_stats(World.by_id_query(c.id), patch)
      {:ok, patch}
    end
  end

  @doc "What the HUD shows about progress, from a stats map."
  def progress(stats) do
    stats = stats || %{}
    level = Map.get(stats, "level", 1)

    %{
      level: level,
      xp: Map.get(stats, "xp", 0),
      xp_next: xp_to_next(level),
      skill_points: Map.get(stats, "skill_points", 0),
      max_hp: Map.get(stats, "max_hp", max_hp(level)),
      max_mp: Map.get(stats, "max_mp", max_mp(level))
    }
  end
end

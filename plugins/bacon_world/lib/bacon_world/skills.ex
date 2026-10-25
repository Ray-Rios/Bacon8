defmodule BaconWorld.Skills do
  @moduledoc """
  A character's place in the skill tree (`BaconWorld.SkillTree`): the nodes it has,
  the points it has left, the abilities and buffs they give, and its hotbars.

    * Nodes: `stats["skill_nodes"]` (ids). The start (Recall) is everyone's.
    * Points: every level banks one (`stats["skill_points"]`, the total ever earned);
      what is left is that less the nodes held, so a node the owner removes from the
      tree hands its point back.
    * Buffs: `"max_hp"` and `"max_mp"` are added to the level's pool
      (`sync_stats/1`, also on a level up), `"melee_pct"` and `"spell_pct"` to damage.
    * Hotbars: `settings["hotbars"]` = `%{"skills" => %{"Q" => id, ...}, "spells" =>
      [20 ids or nil]}`: skills on Q E F Z X, spells on two rows of ten. A newly
      learned spell or skill goes in the first free place.
  """

  alias Bacon8.Games.GameCharacter
  alias BaconWorld.{Abilities, Progression, SkillTree, World}

  @skill_keys ~w(Q E F Z X)
  @spell_slots 20

  def skill_keys, do: @skill_keys
  def spell_slots, do: @spell_slots

  @doc "Nodes, points left, abilities and buff totals for a character."
  def state(%GameCharacter{} = c, tree \\ SkillTree.current()) do
    stats = c.stats || %{}
    learned = SkillTree.learned(tree, stats["skill_nodes"])
    total = Map.get(stats, "skill_points", 0)

    %{
      learned: learned,
      points: max(0, total - (length(learned) - 1)),
      abilities: SkillTree.abilities(tree, learned),
      bonuses: SkillTree.bonuses(tree, learned)
    }
  end

  @doc "Everything the skill window and the hotbars need."
  def payload(%GameCharacter{} = c) do
    tree = SkillTree.current()
    st = state(c, tree)

    %{
      catalog: Abilities.payload(),
      tree: tree,
      learned: st.learned,
      points: st.points,
      abilities: st.abilities,
      bonuses: st.bonuses,
      hotbars: hotbars(c, st.abilities)
    }
  end

  @doc "A buff total for a character (0 if none)."
  def bonus(%GameCharacter{} = c, stat), do: Map.get(state(c).bonuses, stat, 0)

  @doc "The buff totals (`%{\"max_hp\" => n, ...}`) for stats loaded elsewhere."
  def bonuses_for_stats(stats) do
    tree = SkillTree.current()
    SkillTree.bonuses(tree, SkillTree.learned(tree, (stats || %{})["skill_nodes"]))
  end

  @doc """
  Learns a node: it must be joined to one the character has, and a point must be
  left. `{:ok, payload}` or `{:error, message}`.
  """
  def learn(character_id, node_id) do
    with {:ok, c} <- World.fetch_character(character_id),
         tree = SkillTree.current(),
         st = state(c, tree),
         true <- is_binary(node_id) || {:error, "Pick a node."},
         true <- node_id not in st.learned || {:error, "You already have that."},
         true <- st.points > 0 || {:error, "You have no skill points to spend. You earn one each level."},
         true <- SkillTree.reachable?(tree, st.learned, node_id) || {:error, "That isn't joined to anything you have yet."} do
      World.merge_stats(World.by_id_query(c.id), %{"skill_nodes" => st.learned ++ [node_id]})
      {:ok, _} = sync_stats(c.id)
      {:ok, c} = World.fetch_character(c.id)
      new = SkillTree.node(tree, node_id)["ability"]
      if new, do: auto_place(c, new)
      {:ok, c} = World.fetch_character(c.id)
      {:ok, payload(c)}
    end
  end

  @doc """
  Sets max HP and mana to the level's plus the buffs (a bigger pool fills by the
  difference, a smaller one clamps). Returns `{:ok, patch}`.
  """
  def sync_stats(character_id) do
    with {:ok, c} <- World.fetch_character(character_id) do
      level = World.stat(c, "level")
      b = state(c).bonuses
      want_hp = Progression.max_hp(level) + Map.get(b, "max_hp", 0)
      want_mp = Progression.max_mp(level) + Map.get(b, "max_mp", 0)
      have_hp = World.stat(c, "max_hp")
      have_mp = World.stat(c, "max_mp")

      patch =
        if want_hp == have_hp and want_mp == have_mp do
          %{}
        else
          %{
            "max_hp" => want_hp,
            "hp" => World.stat(c, "hp") |> Kernel.+(max(want_hp - have_hp, 0)) |> min(want_hp) |> max(0),
            "max_mp" => want_mp,
            "mp" => World.stat(c, "mp") |> Kernel.+(max(want_mp - have_mp, 0)) |> min(want_mp) |> max(0)
          }
        end

      if patch != %{}, do: World.merge_stats(World.by_id_query(c.id), patch)
      {:ok, patch}
    end
  end

  # ---------------------------------------------------------------------------
  # Hotbars
  # ---------------------------------------------------------------------------

  @doc "The character's hotbars, with abilities it no longer has taken off."
  def hotbars(%GameCharacter{} = c, abilities \\ nil) do
    have = MapSet.new(abilities || state(c).abilities)
    raw = (c.settings || %{})["hotbars"]

    case raw do
      %{} ->
        skills = for {k, id} <- raw["skills"] || %{}, k in @skill_keys, MapSet.member?(have, id), into: %{}, do: {k, id}
        spells = pad(raw["spells"]) |> Enum.map(&if(&1 && MapSet.member?(have, &1), do: &1, else: nil))
        %{"skills" => skills, "spells" => spells}

      _ ->
        # never set: everything the character has, in order
        Enum.reduce(MapSet.to_list(have) |> Enum.sort_by(&order/1), empty(), &place/2)
    end
  end

  @doc "Stores hotbars sent by the client (only abilities the character has, in the right kind of slot)."
  def set_hotbars(character_id, %{} = bars) do
    with {:ok, c} <- World.fetch_character(character_id) do
      have = MapSet.new(state(c).abilities)

      skills =
        for {k, id} <- bars["skills"] || %{}, k in @skill_keys, is_binary(id), MapSet.member?(have, id), Abilities.skill?(Abilities.get(id)), into: %{}, do: {k, id}

      spells =
        bars["spells"]
        |> pad()
        |> Enum.map(fn id -> if is_binary(id) and MapSet.member?(have, id) and Abilities.spell?(Abilities.get(id)), do: id, else: nil end)

      clean = %{"skills" => skills, "spells" => spells}
      World.merge_settings(World.by_id_query(c.id), %{"hotbars" => clean})
      {:ok, clean}
    end
  end

  def set_hotbars(_, _), do: {:error, :bad_hotbars}

  defp auto_place(c, ability_id) do
    bars = hotbars(c)
    placed = place(ability_id, bars)
    if placed != bars, do: World.merge_settings(World.by_id_query(c.id), %{"hotbars" => placed})
  end

  defp place(id, bars) do
    a = Abilities.get(id)

    cond do
      Abilities.skill?(a) and id not in Map.values(bars["skills"]) ->
        case Enum.find(@skill_keys, &(not Map.has_key?(bars["skills"], &1))) do
          nil -> bars
          k -> put_in(bars, ["skills", k], id)
        end

      Abilities.spell?(a) and id not in bars["spells"] ->
        case Enum.find_index(bars["spells"], &is_nil/1) do
          nil -> bars
          i -> %{bars | "spells" => List.replace_at(bars["spells"], i, id)}
        end

      true ->
        bars
    end
  end

  defp empty, do: %{"skills" => %{}, "spells" => List.duplicate(nil, @spell_slots)}

  defp pad(list) when is_list(list), do: (list ++ List.duplicate(nil, @spell_slots)) |> Enum.take(@spell_slots)
  defp pad(_), do: List.duplicate(nil, @spell_slots)

  # Recall first, then the catalogue's order.
  defp order(id), do: Enum.find_index(Abilities.all(), &(&1.id == id)) || 999
end

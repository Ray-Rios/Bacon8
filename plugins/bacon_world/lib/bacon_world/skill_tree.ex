defmodule BaconWorld.SkillTree do
  @moduledoc """
  The one skill tree everyone shares, Path of Exile style: it starts in the middle
  (Recall, which every character has from level 1) and radiates out. Each level banks
  a skill point (`BaconWorld.Progression`); a point buys a node joined to one you
  already have. A node holds an ability (`BaconWorld.Abilities`) or nothing (a path).

  The tree is data the owner edits at /admin/bacon_world/skills (drag abilities onto
  nodes, add and join nodes) and is stored as one row (`bacon_world_skill_trees`,
  slug "main"); until it is first saved, `default/0` is the tree. Shape:

      %{"start" => "n0",
        "nodes" => [%{"id" => "n0", "x" => 0.0, "y" => 0.0, "ability" => "recall"}, ...],
        "edges" => [["n0", "n1"], ...]}

  `x`, `y` are in rings (the first six sit one ring out; up is +y). Edges are
  two-way. A character's nodes are in its stats (`"skill_nodes"`); nodes the owner
  later removes stop counting, and their points come back (`BaconWorld.Skills`).
  """

  import Ecto.Query, only: [from: 2]

  alias Bacon8.GamesRepo
  alias BaconWorld.{Abilities, SkillTreeRecord}

  @slug "main"
  @cache {__MODULE__, :tree}
  @cache_ms 5_000
  @max_nodes 400
  @max_coord 30.0

  @first_ring ~w(heal fireball hp_10 mp_10 root spin_attack)

  @doc "The tree the game ships with: Recall in the middle, six nodes around it."
  def default do
    ring =
      @first_ring
      |> Enum.with_index()
      |> Enum.map(fn {ability, i} ->
        a = :math.pi() / 2 - i * :math.pi() / 3
        %{"id" => "n#{i + 1}", "x" => Float.round(:math.cos(a), 3), "y" => Float.round(:math.sin(a), 3), "ability" => ability}
      end)

    %{
      "start" => "n0",
      "nodes" => [%{"id" => "n0", "x" => 0.0, "y" => 0.0, "ability" => "recall"} | ring],
      "edges" => Enum.map(ring, &["n0", &1["id"]])
    }
  end

  @doc "The tree in force (cached for a few seconds; the default until one is saved)."
  def current do
    now = System.monotonic_time(:millisecond)

    case :persistent_term.get(@cache, nil) do
      {at, tree} when now - at < @cache_ms ->
        tree

      _ ->
        tree = load() || default()
        :persistent_term.put(@cache, {now, tree})
        tree
    end
  end

  @doc "Forgets the cached tree (after a save; other nodes catch up within seconds)."
  def bust, do: :persistent_term.erase(@cache)

  defp load do
    case GamesRepo.one(from(r in SkillTreeRecord, where: r.slug == @slug)) do
      %{data: data} when is_map(data) -> data
      _ -> nil
    end
  rescue
    _ -> nil
  end

  @doc "Validates and stores a tree. `{:ok, tree}` or `{:error, message}`."
  def save(tree, updated_by \\ nil) do
    with {:ok, tree} <- validate(tree) do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      GamesRepo.insert_all(
        SkillTreeRecord,
        [%{id: Ecto.UUID.generate(), slug: @slug, data: tree, updated_by: updated_by, inserted_at: now, updated_at: now}],
        on_conflict: [set: [data: tree, updated_by: updated_by, updated_at: now]],
        conflict_target: :slug
      )

      bust()
      {:ok, tree}
    end
  end

  @doc "Puts the shipped tree back (deletes the stored one)."
  def reset do
    GamesRepo.delete_all(from(r in SkillTreeRecord, where: r.slug == @slug))
    bust()
    {:ok, default()}
  end

  @doc """
  Checks a tree (as the editor sends it) and returns it cleaned: string keys, rounded
  coordinates, known abilities, edges between existing nodes (each once).
  """
  def validate(%{} = tree) do
    nodes = List.wrap(tree["nodes"])
    start = tree["start"]

    with true <- (nodes != [] and length(nodes) <= @max_nodes) || {:error, "A tree needs 1 to #{@max_nodes} nodes."},
         {:ok, nodes} <- clean_nodes(nodes),
         ids = MapSet.new(nodes, & &1["id"]),
         true <- MapSet.size(ids) == length(nodes) || {:error, "Two nodes share an id."},
         true <- MapSet.member?(ids, start) || {:error, "The start node is missing."},
         {:ok, edges} <- clean_edges(List.wrap(tree["edges"]), ids) do
      {:ok, %{"start" => start, "nodes" => nodes, "edges" => edges}}
    end
  end

  def validate(_), do: {:error, "That isn't a tree."}

  defp clean_nodes(nodes) do
    Enum.reduce_while(nodes, {:ok, []}, fn n, {:ok, acc} ->
      id = n["id"]
      ability = n["ability"]
      x = n["x"]
      y = n["y"]

      cond do
        not (is_binary(id) and Regex.match?(~r/^[a-z0-9_-]{1,24}$/, id)) ->
          {:halt, {:error, "A node has a bad id."}}

        not (is_number(x) and is_number(y) and abs(x) <= @max_coord and abs(y) <= @max_coord) ->
          {:halt, {:error, "Node #{id} is off the map."}}

        not (is_nil(ability) or (is_binary(ability) and Abilities.get(ability) != nil)) ->
          {:halt, {:error, "Node #{id} has an unknown ability (#{inspect(ability)})."}}

        true ->
          {:cont, {:ok, acc ++ [%{"id" => id, "x" => Float.round(x * 1.0, 3), "y" => Float.round(y * 1.0, 3), "ability" => ability}]}}
      end
    end)
  end

  defp clean_edges(edges, ids) do
    Enum.reduce_while(edges, {:ok, [], MapSet.new()}, fn
      [a, b], {:ok, acc, seen} when is_binary(a) and is_binary(b) and a != b ->
        key = Enum.sort([a, b])

        cond do
          not (MapSet.member?(ids, a) and MapSet.member?(ids, b)) -> {:halt, {:error, "An edge joins a missing node."}}
          MapSet.member?(seen, key) -> {:cont, {:ok, acc, seen}}
          true -> {:cont, {:ok, acc ++ [key], MapSet.put(seen, key)}}
        end

      _, _ ->
        {:halt, {:error, "An edge is malformed."}}
    end)
    |> case do
      {:ok, edges, _} -> {:ok, edges}
      err -> err
    end
  end

  # ---------------------------------------------------------------------------
  # Reading a tree
  # ---------------------------------------------------------------------------

  @doc "Node by id."
  def node(tree, id), do: Enum.find(tree["nodes"], &(&1["id"] == id))

  @doc "The ids joined to `id`."
  def neighbours(tree, id) do
    for [a, b] <- tree["edges"], a == id or b == id, do: if(a == id, do: b, else: a)
  end

  @doc "Node ids in the tree."
  def ids(tree), do: MapSet.new(tree["nodes"], & &1["id"])

  @doc "The nodes a character has that are still in the tree, the start always first."
  def learned(tree, nodes) do
    ids = ids(tree)
    start = tree["start"]
    [start | Enum.filter(List.wrap(nodes), &(&1 != start and MapSet.member?(ids, &1)))] |> Enum.uniq()
  end

  @doc "True when `id` can be learned next: in the tree, not yet had, joined to one that is."
  def reachable?(tree, learned, id) do
    node(tree, id) != nil and id not in learned and Enum.any?(neighbours(tree, id), &(&1 in learned))
  end

  @doc "The abilities on these nodes (ids, unique, tree order)."
  def abilities(tree, learned) do
    tree["nodes"] |> Enum.filter(&(&1["id"] in learned and &1["ability"])) |> Enum.map(& &1["ability"]) |> Enum.uniq()
  end

  @doc "What the learned buffs add up to: `%{\"max_hp\" => 10, ...}`."
  def bonuses(tree, learned) do
    tree["nodes"]
    |> Enum.filter(&(&1["id"] in learned))
    |> Enum.reduce(%{}, fn n, acc ->
      case Abilities.get(n["ability"]) do
        %{kind: "buff", effect: %{stat: stat, amount: amount}} -> Map.update(acc, stat, amount, &(&1 + amount))
        _ -> acc
      end
    end)
  end
end

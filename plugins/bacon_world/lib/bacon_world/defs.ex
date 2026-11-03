defmodule BaconWorld.Defs do
  @moduledoc """
  The game's definitions in the database (2026-11-02, owner: "move everything into the DB"):
  `bacon_world_defs` rows of a `kind` (`"monster"`: creature types, `BaconWorld.Mobs.Spawns`;
  `"merchant"`: the merchants and NPCs, `BaconWorld.Merchants`), each `id` with its `data`.
  Items have their own table (`BaconWorld.Items`).

  A kind is filled once from `priv/seed/<kind>s.json` (exported from the code it replaced) the first
  time it is read, and cached in `:persistent_term`; `put/3` and `delete/2` (the database editor)
  reload it on every node.

  `data` is JSON: maps with atom keys, ranges (`1..3`) and tuples (`{"goblin", 3}`) are encoded as
  `{"$range": [1, 3]}` and `{"$tuple": [...]}`, string-keyed maps as `{"$s": {...}}`, and decoded back (`encode/1`, `decode/1`), so the game
  code reads the same terms it always did.
  """

  import Ecto.Query
  alias Bacon8.GamesRepo

  defmodule Row do
    @moduledoc false
    use Ecto.Schema
    @primary_key false
    schema "bacon_world_defs" do
      field :kind, :string, primary_key: true
      field :id, :string, primary_key: true
      field :data, :map, default: %{}
      field :position, :integer, default: 0
      timestamps(type: :utc_datetime)
    end
  end

  @doc "Every definition of a kind, `[{id, term}]` in order."
  def list(kind), do: cached(kind).list

  @doc "A kind as a map id => term (cached: the creatures read it every tick)."
  def map(kind), do: cached(kind).map

  defp cached(kind) do
    key = {__MODULE__, kind}

    case :persistent_term.get(key, nil) do
      nil ->
        rows = (Application.get_env(:bacon8, __MODULE__, [])[:source] != :seed && from_db(kind)) || seed(kind)
        list = rows |> Enum.sort_by(& &1["position"]) |> Enum.map(&{&1["id"], decode(&1["data"])})
        c = %{list: list, map: Map.new(list)}
        :persistent_term.put(key, c)
        c

      c ->
        c
    end
  end

  @doc "Saves a definition (a term with atom keys) and reloads the kind everywhere."
  def put(kind, id, term) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    pos = GamesRepo.one(from r in Row, where: r.kind == ^kind and r.id == ^id, select: r.position) ||
            (GamesRepo.one(from r in Row, where: r.kind == ^kind, select: max(r.position)) || 0) + 1

    GamesRepo.insert_all(Row, [%{kind: kind, id: id, data: encode(term), position: pos, inserted_at: now, updated_at: now}],
      on_conflict: {:replace, [:data, :updated_at]}, conflict_target: [:kind, :id])

    reload(kind)
    :ok
  end

  @doc "Deletes a definition and reloads the kind everywhere."
  def delete(kind, id) do
    GamesRepo.delete_all(from r in Row, where: r.kind == ^kind and r.id == ^id)
    reload(kind)
    :ok
  end

  @doc "Forgets a kind's cache on every node."
  def reload(kind) do
    :persistent_term.erase({__MODULE__, kind})
    for n <- Node.list(), do: :erpc.cast(n, :persistent_term, :erase, [{__MODULE__, kind}])
    :ok
  end

  defp from_db(kind) do
    rows = GamesRepo.all(from r in Row, where: r.kind == ^kind, select: %{"id" => r.id, "data" => r.data, "position" => r.position})

    if rows == [] do
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      entries = for r <- seed(kind), do: %{kind: kind, id: r["id"], data: r["data"], position: r["position"], inserted_at: now, updated_at: now}
      entries |> Enum.chunk_every(100) |> Enum.each(&GamesRepo.insert_all(Row, &1, on_conflict: :nothing, conflict_target: [:kind, :id]))
      GamesRepo.all(from r in Row, where: r.kind == ^kind, select: %{"id" => r.id, "data" => r.data, "position" => r.position})
    else
      rows
    end
  rescue
    _ -> nil
  end

  @doc "The seed rows of a kind (`priv/seed/<kind>s.json`): id, data and position (string keys)."
  def seed(kind) do
    [Bacon8.Plugins.priv_dir("bacon_world"), "seed", "#{kind}s.json"]
    |> Path.join()
    |> File.read!()
    |> Jason.decode!()
  end

  # ---------------------------------------------------------------- the codec

  @doc "A term as JSON-safe data (atom-keyed maps become string-keyed; ranges and tuples tagged)."
  def encode(%Range{first: a, last: b}), do: %{"$range" => [a, b]}
  def encode(t) when is_tuple(t), do: %{"$tuple" => t |> Tuple.to_list() |> Enum.map(&encode/1)}
  # string-keyed maps (an NPC's look, its gear) stay string-keyed: `{"$s": {...}}`
  def encode(m) when is_map(m) do
    obj = for({k, v} <- m, into: %{}, do: {to_string(k), encode(v)})
    if Enum.any?(Map.keys(m), &is_binary/1), do: %{"$s" => obj}, else: obj
  end
  def encode(l) when is_list(l), do: Enum.map(l, &encode/1)
  def encode(a) when is_atom(a) and a not in [nil, true, false], do: %{"$atom" => Atom.to_string(a)}
  def encode(v), do: v

  @doc "The term back from `encode/1`'s data (map keys become atoms)."
  def decode(%{"$range" => [a, b]}), do: a..b//(if b >= a, do: 1, else: -1)
  def decode(%{"$tuple" => l}), do: l |> Enum.map(&decode/1) |> List.to_tuple()
  def decode(%{"$atom" => a}), do: String.to_atom(a)
  def decode(%{"$s" => m}) when is_map(m), do: for({k, v} <- m, into: %{}, do: {k, decode(v)})
  def decode(m) when is_map(m), do: for({k, v} <- m, into: %{}, do: {key(k), decode(v)})
  def decode(l) when is_list(l), do: Enum.map(l, &decode/1)
  def decode(v), do: v

  # keys are the game's own field names (atoms); a key the editor adds becomes one too (admins only)
  defp key(k) when is_binary(k), do: String.to_atom(k)
  defp key(k), do: k
end

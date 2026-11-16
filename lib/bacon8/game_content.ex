defmodule Bacon8.GameContent do
  @moduledoc """
  Every game's definitions on the hub (2026-11-15; owner: "Move camps, loot and item definitions
  to the hub, as you did with building"): what lives in a game's world, kept as data and edited
  without a deploy. Build mode's placements are `Bacon8.Building`; this is everything else.

  A definition is a row of `game_defs`: a game (its slug), a `kind`, an `id` and its `data` (a JSON
  object the game gives meaning to). The kinds the games use so far:

      "zone"           a zone: its name, level band, map, the zone it leads to
      "camp"           a camp of creatures in a zone: where, how big, its slots, respawn, boss
      "camp_template"  a hand-built camp to stamp elsewhere (Bacon World)
      "monster"        a creature type: its model, level band, hit points, damage, loot tables
      "loot_table"     what something drops (`Bacon8.GameContent.Loot` rolls it)
      "item"           an item
      "merchant"       a merchant or NPC and its stock
      "event"          a timed XP, loot or coin event (Bacon World)

  Any other kind works the same: the hub stores, lists, versions and serves them and never reads
  inside `data`, except a loot table when it is asked to roll one.

  **Bacon World** keeps its own readers and its Studio (`BaconWorld.Defs` and the modules on it:
  the same rows, `game_slug` "bacon_world", decoded into the terms its code has always read). Its
  items are still its own table (`bacon_world_item_defs`); they come here when the Studio's pages do.
  The hub won't write Bacon World's rows (`put/5` refuses): one editor at a time.

  **Reading** is cached per game and kind (`:persistent_term`; a change clears it on every node),
  and each kind has a `revision/2`, a number that changes whenever any of its definitions does, so
  a game client asks "still revision n?" and is told `unchanged` (`Bacon8Web.Api.ContentController`).

  **Changing** (`put/5`, `delete/4`) is for staff (`staff?/1`: admins and GMs, as Bacon World's
  Studio), through the API or `/admin/content`. Every change is kept (`history/2`) and can be undone
  (`undo/3`), a deletion too, and is in the audit log.
  """

  import Ecto.Query
  alias Bacon8.GamesRepo
  alias Bacon8.GameContent.{Def, History}

  @kind_re ~r/^[a-z][a-z0-9_]{0,39}$/
  @id_re ~r/^[A-Za-z0-9][A-Za-z0-9_.:\-]{0,119}$/
  @max_bytes 262_144
  @read_only ["bacon_world"]

  @doc "Admins and GMs change a game's definitions (the Studio's rule, the hub's roles)."
  def staff?(%{role: role, status: status}) when role in ["admin", "gm"], do: status in [nil, "active"]
  def staff?(_), do: false

  @doc "Games whose rows the hub serves but does not write (they have an editor of their own)."
  def read_only?(game_slug), do: game_slug in @read_only

  # ---------------------------------------------------------------- reading

  @doc "The kinds a game has definitions of, with how many: `[%{kind, count}]`, by name."
  def kinds(game_slug) do
    GamesRepo.all(from d in Def, where: d.game_slug == ^game_slug, group_by: d.kind, order_by: d.kind, select: %{kind: d.kind, count: count(d.id)})
  end

  @doc """
  A kind's definitions, in order: `[%{id, kind, data, position, updated_at}]`.

  `where: %{"zone" => "outskirts_01"}` keeps those whose `data` has those values at its top level.
  """
  def list(game_slug, kind, opts \\ []) do
    rows = cached(game_slug, kind).list

    case Keyword.get(opts, :where) do
      %{} = want when map_size(want) > 0 -> Enum.filter(rows, fn r -> Enum.all?(want, fn {k, v} -> to_string(Map.get(r.data, to_string(k))) == to_string(v) end) end)
      _ -> rows
    end
  end

  @doc "A kind as a map id => data."
  def map(game_slug, kind), do: cached(game_slug, kind).map

  @doc "One definition's data, or nil."
  def get(game_slug, kind, id), do: Map.get(map(game_slug, kind), id)

  @doc "A number that changes whenever any definition of the kind does (0 for a kind with none)."
  def revision(game_slug, kind), do: cached(game_slug, kind).revision

  defp cached(game_slug, kind) do
    key = {__MODULE__, game_slug, kind}

    case :persistent_term.get(key, nil) do
      nil ->
        list =
          GamesRepo.all(
            from d in Def,
              where: d.game_slug == ^game_slug and d.kind == ^kind,
              order_by: [d.position, d.id],
              select: %{id: d.id, kind: d.kind, data: d.data, position: d.position, updated_at: d.updated_at}
          )

        c = %{list: list, map: Map.new(list, &{&1.id, &1.data}), revision: if(list == [], do: 0, else: :erlang.phash2(list, 4_294_967_296))}
        :persistent_term.put(key, c)
        c

      c ->
        c
    end
  end

  @doc "Forgets a kind's cache on every node (after any write to its rows, the hub's or a plugin's own)."
  def reload(game_slug, kind) do
    :persistent_term.erase({__MODULE__, game_slug, kind})
    for n <- Node.list(), do: :erpc.cast(n, :persistent_term, :erase, [{__MODULE__, game_slug, kind}])
    :ok
  end

  @doc "Forgets every cache on this node (tests: the sandbox rolls the rows back, not the cache)."
  def reset do
    for {{__MODULE__, _, _} = key, _} <- :persistent_term.get(), do: :persistent_term.erase(key)
    :ok
  end

  # ---------------------------------------------------------------- changing

  @doc """
  Saves a definition (new or changed) as `actor` (a user, or nil for the system) and returns
  `{:ok, %{id, kind, data, position}}`. Refused with `{:error, message}`: a kind or id that isn't
  one, `data` that isn't an object or is over 256 KB, and a read-only game.
  """
  def put(game_slug, kind, id, data, actor \\ nil) do
    with :ok <- writable(game_slug), :ok <- valid(kind, id, data) do
      before = get(game_slug, kind, id)
      row = write(game_slug, kind, id, data)

      if before != data do
        record(game_slug, kind, id, if(before, do: "update", else: "create"), before, data, actor)
        reload(game_slug, kind)
      end

      {:ok, row}
    end
  end

  @doc "Deletes a definition; `{:error, message}` when there is none."
  def delete(game_slug, kind, id, actor \\ nil) do
    with :ok <- writable(game_slug) do
      case get(game_slug, kind, id) do
        nil ->
          {:error, "There is no #{kind} #{id}."}

        before ->
          GamesRepo.delete_all(from d in Def, where: d.game_slug == ^game_slug and d.kind == ^kind and d.id == ^id)
          record(game_slug, kind, id, "delete", before, nil, actor)
          reload(game_slug, kind)
          :ok
      end
    end
  end

  @doc """
  Fills a kind from a plugin's seed file: `rows` are `[%{"id" => id, "data" => map}]`, in order.
  By default only a kind that has nothing yet is filled, so a plugin may call this at every start:
  what an admin changed or deleted since stays that way. `missing: true` adds the rows that
  aren't there (a new release's additions, or an admin asking for the seed again) and still never
  touches one that is. Nothing is recorded in the history. Returns how many were added.
  """
  def seed(game_slug, kind, rows, opts \\ []) when is_list(rows) do
    top = GamesRepo.one(from d in Def, where: d.game_slug == ^game_slug and d.kind == ^kind, select: max(d.position))

    if top != nil and not Keyword.get(opts, :missing, false) do
      0
    else
      do_seed(game_slug, kind, rows, top || 0)
    end
  end

  defp do_seed(game_slug, kind, rows, top) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    entries =
      for {r, n} <- Enum.with_index(rows, top + 1), is_binary(r["id"]), is_map(r["data"]), valid(kind, r["id"], r["data"]) == :ok do
        %{game_slug: game_slug, kind: kind, id: r["id"], data: r["data"], position: n, inserted_at: now, updated_at: now}
      end

    added =
      entries
      |> Enum.chunk_every(200)
      |> Enum.map(fn chunk -> GamesRepo.insert_all(Def, chunk, on_conflict: :nothing, conflict_target: [:game_slug, :kind, :id]) |> elem(0) end)
      |> Enum.sum()

    if added > 0, do: reload(game_slug, kind)
    added
  end

  defp write(game_slug, kind, id, data) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    pos =
      GamesRepo.one(from d in Def, where: d.game_slug == ^game_slug and d.kind == ^kind and d.id == ^id, select: d.position) ||
        (GamesRepo.one(from d in Def, where: d.game_slug == ^game_slug and d.kind == ^kind, select: max(d.position)) || 0) + 1

    GamesRepo.insert_all(Def, [%{game_slug: game_slug, kind: kind, id: id, data: data, position: pos, inserted_at: now, updated_at: now}],
      on_conflict: {:replace, [:data, :updated_at]},
      conflict_target: [:game_slug, :kind, :id]
    )

    %{id: id, kind: kind, data: data, position: pos}
  end

  defp writable(game_slug) do
    if read_only?(game_slug), do: {:error, "#{game_slug}'s definitions are edited in its own Studio."}, else: :ok
  end

  defp valid(kind, id, data) do
    cond do
      not (is_binary(kind) and Regex.match?(@kind_re, kind)) -> {:error, "A kind is lower-case letters, digits and underscores (40 at most)."}
      # (the API's /content/history is the list of changes)
      kind == "history" -> {:error, "\"history\" is the list of changes; call the kind something else."}
      not (is_binary(id) and Regex.match?(@id_re, id)) -> {:error, "An id is letters, digits and _ . : - (120 at most), starting with a letter or digit."}
      not is_map(data) -> {:error, "A definition's data is an object."}
      byte_size(Jason.encode!(data)) > @max_bytes -> {:error, "A definition is 256 KB at most."}
      true -> :ok
    end
  rescue
    _ -> {:error, "That data can't be stored as JSON."}
  end

  # ---------------------------------------------------------------- history

  defp record(game_slug, kind, id, action, before, after_, actor) do
    GamesRepo.insert!(%History{
      game_slug: game_slug,
      kind: kind,
      ref_id: id,
      action: action,
      before: before,
      after: after_,
      user_id: actor && to_string(actor.id),
      user_name: actor && (Map.get(actor, :name) || Map.get(actor, :email))
    })

    Bacon8.Audit.log(actor && actor.id, "game_content.#{action}", kind, nil, %{game: game_slug, kind: kind, id: id})
    :ok
  end

  @doc """
  A game's changes, newest first: `[%History{}]`. Options: `:kind`, `:id` (one definition's),
  `:limit` (50; 200 at most).
  """
  def history(game_slug, opts \\ []) do
    limit = opts |> Keyword.get(:limit, 50) |> max(1) |> min(200)
    q = from h in History, where: h.game_slug == ^game_slug, order_by: [desc: h.id], limit: ^limit
    q = if kind = opts[:kind], do: where(q, [h], h.kind == ^kind), else: q
    q = if id = opts[:id], do: where(q, [h], h.ref_id == ^id), else: q
    GamesRepo.all(q)
  end

  @doc """
  Puts a definition back as it was before change `history_id` (a deletion brings it back; a
  creation deletes it). The undo is itself a change, so it can be undone.
  """
  def undo(game_slug, history_id, actor \\ nil) do
    case GamesRepo.get_by(History, id: history_id, game_slug: game_slug) do
      nil -> {:error, "There is no such change."}
      %History{before: nil} = h -> with :ok <- delete(game_slug, h.kind, h.ref_id, actor), do: {:ok, nil}
      %History{} = h -> put(game_slug, h.kind, h.ref_id, h.before, actor)
    end
  end
end

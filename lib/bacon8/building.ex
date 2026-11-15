defmodule Bacon8.Building do
  @moduledoc """
  Build mode for every game (2026-11-14, the owner: RaysSpaceSim and Tears of Babylon get Bacon
  World's build system, "` button and all", on one hub service). What is placed, where, by whom,
  who may place what and how much a piece can take, for any game, by game slug and zone.

    * **The catalogue** is shared (`Bacon8.Building.Catalogue`: Bacon World's props and building
      kit). Bacon World adds its creature spawns and NPCs in its own `BaconWorld.Building`.
    * **Who may place what**: a role per asset, the lowest that may place it, and so move, delete
      and smash any copy of it, whoever placed it. Admins set it (`set_rule/3`); one set of rules
      for every game (`game_asset_rules`). Roles rank `admin > gm > moderator > editor > member >
      guest > banned`; an `is_admin` account is an admin. Guests and the banned place nothing.
    * **Placements** (`game_placements`): metres, `y` up, `rot` radians about up, in the zone's
      `frame` (nil: the zone's own; RaysSpaceSim: the planet's, so a base rides its orbit).
      `data` keeps only `"q"` (a full turn, `[x, y, z, w]`, for games that build on curved ground)
      and `"s"` (a stretch, `[x, y, z]`).
    * **Hit points** (`damage/5`): each piece starts at its asset's HP (default 10); at 0 it is
      deleted and broadcast as smashed, so every client shatters it. Live HP is in memory.
    * **Changes** are broadcast on `topic/2` (`{:build_placed, view}`, `{:build_removed, id,
      asset}` or `{..., :smashed}`, `{:build_damaged, id, asset, hp, max_hp, amount}`), and each
      zone has a `revision/2` that goes up with every change, so a game server can poll cheaply.

  Bacon World keeps its own module for its zones (live events, creature spawns, NPCs, seeding),
  on the same tables: its `bacon_world_placements` and `bacon_world_asset_rules` are views of these
  (the 2026-11-15 games_repo migration). The HTTP API for the game servers and clients is
  `Bacon8Web.Api.BuildingController` (`/api/games/:game_slug/build/...`).
  """

  import Ecto.Query
  alias Bacon8.GamesRepo
  alias Bacon8.Building.{AssetRule, Catalogue, Placement}

  @rank %{"banned" => 0, "guest" => 1, "member" => 2, "editor" => 3, "moderator" => 4, "gm" => 5, "admin" => 6}
  @roles ~w(member editor moderator gm admin)
  @default_hp 10
  @max_extent 1.0e7
  @hp_table :bacon8_building_hp
  @rev_table :bacon8_building_rev

  # ---------------------------------------------------------------------------
  # Roles
  # ---------------------------------------------------------------------------

  @doc "The roles a rule may name, lowest first."
  def roles, do: @roles

  @doc "An account's role for building (an `is_admin` account is an admin)."
  def role_of(%{is_admin: true}), do: "admin"
  def role_of(%{role: role}) when is_binary(role), do: role
  def role_of(_), do: "guest"

  @doc "True when `role` is at least `min_role`. Guests and the banned never are."
  def at_least?(role, min_role) do
    r = Map.get(@rank, role, 0)
    r >= @rank["member"] and r >= Map.get(@rank, min_role, @rank["admin"])
  end

  @doc "True for an admin (who may change the rules)."
  def admin?(user), do: role_of(user) == "admin"

  # ---------------------------------------------------------------------------
  # The catalogue and its rules
  # ---------------------------------------------------------------------------

  @doc "What `game_slug` may place (the shared models)."
  def catalogue(_game_slug), do: Catalogue.models()

  @doc "A catalogue entry of `game_slug` by id, or nil."
  def asset(game_slug, id), do: Enum.find(catalogue(game_slug), &(&1.id == id))

  @doc "`%{asset => %{min_role, hp}}`: the admins' rules (read fresh: a small table)."
  def saved_rules do
    GamesRepo.all(from(r in AssetRule, select: {r.asset, %{min_role: r.min_role, hp: r.hp}})) |> Map.new()
  end

  @doc "The catalogue as the build window shows it to `user`: each entry with its rule, HP and whether they may use it."
  def catalogue_for(game_slug, user) do
    saved = saved_rules()
    role = role_of(user)

    for a <- catalogue(game_slug) do
      rule = Map.get(saved, a.id, %{})
      min = rule[:min_role] || a.default_role
      a |> Map.put(:min_role, min) |> Map.put(:hp, rule[:hp] || @default_hp) |> Map.put(:allowed, at_least?(role, min))
    end
  end

  @doc "The lowest role that may place `asset` in `game_slug`, or nil for something not in its catalogue."
  def min_role(game_slug, asset_id, saved \\ nil) do
    case asset(game_slug, asset_id) do
      nil -> nil
      a -> get_in(saved || saved_rules(), [asset_id, :min_role]) || a.default_role
    end
  end

  @doc "An asset's hit points (default 10)."
  def max_hp(asset_id, saved \\ nil), do: get_in(saved || saved_rules(), [asset_id, :hp]) || @default_hp

  @doc "True when `user` may place (and move, delete and smash) `asset_id` in `game_slug`."
  def can_place?(game_slug, user, asset_id) do
    case min_role(game_slug, asset_id) do
      nil -> false
      min -> at_least?(role_of(user), min)
    end
  end

  @doc "Sets the lowest role for an asset, in every game (admins only). `{:ok, role}` or `{:error, message}`."
  def set_rule(user, asset_id, role) do
    cond do
      not admin?(user) -> {:error, "Only admins can change who may build what."}
      is_nil(Enum.find(Catalogue.models(), &(&1.id == asset_id))) -> {:error, "There is no such thing to place."}
      role not in @roles -> {:error, "That isn't a role."}
      true ->
        upsert_rule(user, asset_id, %{min_role: role, hp: max_hp(asset_id)}, [:min_role])
        {:ok, role}
    end
  end

  @doc "Sets an asset's hit points, in every game (admins only). `{:ok, hp}` or `{:error, message}`."
  def set_hp(user, asset_id, hp) do
    a = Enum.find(Catalogue.models(), &(&1.id == asset_id))

    cond do
      not admin?(user) -> {:error, "Only admins can change object health."}
      is_nil(a) -> {:error, "There is no such thing to configure."}
      not is_integer(hp) or hp <= 0 -> {:error, "HP must be a positive integer."}
      true ->
        upsert_rule(user, asset_id, %{min_role: min_role("any", asset_id) || a.default_role, hp: min(hp, 1_000_000)}, [:hp])
        {:ok, hp}
    end
  end

  defp upsert_rule(user, asset_id, fields, replace) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    GamesRepo.insert_all(AssetRule, [Map.merge(fields, %{asset: asset_id, updated_by: user_id(user), inserted_at: now, updated_at: now})],
      on_conflict: {:replace, replace ++ [:updated_by, :updated_at]},
      conflict_target: [:asset]
    )
  end

  # ---------------------------------------------------------------------------
  # Placements
  # ---------------------------------------------------------------------------

  @doc "The PubSub topic a zone's building is broadcast on."
  def topic(game_slug, zone), do: "build:#{game_slug}:#{zone}"

  @doc "A number that goes up with every change in the zone (0 before the first since the node started)."
  def revision(game_slug, zone) do
    ensure_tables()

    case :ets.lookup(@rev_table, {game_slug, zone}) do
      [{_, n}] -> n
      [] -> 0
    end
  end

  @doc "Every placement in a zone (`frame`: only that frame's, when given), as `view/2` maps, oldest first."
  def list(game_slug, zone, opts \\ []) do
    saved = saved_rules()
    q = from(p in Placement, where: p.game_slug == ^game_slug and p.zone == ^zone, order_by: p.inserted_at)
    q = if f = opts[:frame], do: where(q, [p], p.frame == ^f), else: q
    q |> GamesRepo.all() |> Enum.map(&view(&1, saved))
  end

  @doc "One placement, or nil."
  def get(game_slug, zone, id) do
    with {:ok, uuid} <- Ecto.UUID.cast(id) do
      GamesRepo.one(from(p in Placement, where: p.game_slug == ^game_slug and p.zone == ^zone and p.id == ^uuid))
    else
      _ -> nil
    end
  end

  @doc """
  Puts `attrs` (`"asset"`, `"frame"`, `"x"`, `"y"`, `"z"`, `"rot"`, `"scale"`, `"data"`) in a zone
  for `user`. `{:ok, view}` or `{:error, message}`.
  """
  def place(game_slug, zone, user, attrs, character_id \\ nil) when is_map(attrs) do
    asset_id = attrs["asset"]

    with %{} = a <- asset(game_slug, asset_id) || {:error, "There is no such thing to place."},
         true <- can_place?(game_slug, user, asset_id) || {:error, "You aren't allowed to place #{a.name}."},
         :ok <- zone_ok(zone),
         {:ok, fields} <- fields(attrs, %{}) do
      row = struct(Placement, Map.merge(fields, %{game_slug: game_slug, zone: zone, asset: asset_id, placed_by: user_id(user), character_id: character_id}))

      case GamesRepo.insert(row) do
        {:ok, p} ->
          changed(p, {:build_placed, view(p)})
          {:ok, view(p)}

        {:error, _} ->
          {:error, "That couldn't be placed."}
      end
    end
  end

  @doc "Moves (or turns, resizes) a placement. `{:ok, view}` or `{:error, message}`."
  def move(game_slug, zone, user, id, attrs) when is_map(attrs) do
    with %Placement{} = p <- get(game_slug, zone, id) || {:error, "That isn't there any more."},
         true <- can_place?(game_slug, user, p.asset) || {:error, "You aren't allowed to move that."},
         {:ok, fields} <- fields(attrs, p),
         {:ok, p2} <- p |> Ecto.Changeset.change(fields) |> GamesRepo.update() do
      changed(p2, {:build_placed, view(p2)})
      {:ok, view(p2)}
    else
      {:error, %Ecto.Changeset{}} -> {:error, "That couldn't be moved."}
      other -> other
    end
  end

  @doc """
  Deletes a placement. `smash: true` broadcasts it as smashed, so every client shatters it.
  `{:ok, view}` (what was deleted, for an undo) or `{:error, message}`.
  """
  def delete(game_slug, zone, user, id, opts \\ []) do
    with %Placement{} = p <- get(game_slug, zone, id) || {:error, "That isn't there any more."},
         true <- can_place?(game_slug, user, p.asset) || {:error, "You aren't allowed to remove that."},
         {:ok, _} <- GamesRepo.delete(p) do
      ensure_tables()
      :ets.delete(@hp_table, {game_slug, zone, p.id})
      changed(p, if(opts[:smash], do: {:build_removed, p.id, p.asset, :smashed}, else: {:build_removed, p.id, p.asset}))
      {:ok, view(p)}
    else
      {:error, %Ecto.Changeset{}} -> {:error, "That couldn't be removed."}
      other -> other
    end
  end

  @doc """
  `amount` damage to a placement by `user` (who must be allowed to delete it). `{:ok, :damaged,
  view}` (its `hp` lowered) or `{:ok, :destroyed, view}` (deleted, broadcast as smashed), or
  `{:error, message}`.
  """
  def damage(game_slug, zone, user, id, amount) when is_number(amount) and amount > 0 do
    ensure_tables()
    amount = max(1, round(amount))

    with %Placement{} = p <- get(game_slug, zone, id) || {:error, "That isn't there any more."},
         true <- can_place?(game_slug, user, p.asset) || {:error, "You can't break that."} do
      m = max_hp(p.asset)
      key = {game_slug, zone, p.id}
      cur = case :ets.lookup(@hp_table, key) do [{_, h}] -> h; [] -> m end
      left = max(0, cur - amount)

      if left == 0 do
        case GamesRepo.delete(p, stale_error_field: :id) do
          {:ok, _} ->
            :ets.delete(@hp_table, key)
            changed(p, {:build_removed, p.id, p.asset, :smashed})
            {:ok, :destroyed, view(p) |> Map.put(:hp, 0)}

          {:error, _} ->
            {:error, "That couldn't be destroyed."}
        end
      else
        :ets.insert(@hp_table, {key, left})
        changed(p, {:build_damaged, p.id, p.asset, left, m, amount})
        {:ok, :damaged, view(p)}
      end
    end
  end

  def damage(_game_slug, _zone, _user, _id, _amount), do: {:error, "Invalid damage amount."}

  @doc "A placement as games get it (metres, radians; `hp` its health now)."
  def view(%Placement{} = p, saved \\ nil) do
    m = max_hp(p.asset, saved)

    hp =
      if :ets.whereis(@hp_table) != :undefined do
        case :ets.lookup(@hp_table, {p.game_slug, p.zone, p.id}) do [{_, h}] -> h; [] -> m end
      else
        m
      end

    %{id: p.id, asset: p.asset, frame: p.frame, x: p.x, y: p.y, z: p.z, rot: p.rot, scale: p.scale, data: p.data || %{},
      hp: hp, max_hp: m, placed_by: p.placed_by, character_id: p.character_id}
  end

  @doc false
  def ensure_tables do
    for t <- [@hp_table, @rev_table], :ets.whereis(t) == :undefined do
      try do
        :ets.new(t, [:named_table, :public, :set, read_concurrency: true, write_concurrency: true])
      rescue
        ArgumentError -> :ok
      end
    end

    :ok
  end

  @doc "Forgets the live HP and revisions (tests)."
  def reset do
    ensure_tables()
    :ets.delete_all_objects(@hp_table)
    :ets.delete_all_objects(@rev_table)
    :ok
  end

  # ---------------------------------------------------------------------------

  defp changed(%Placement{game_slug: g, zone: z}, msg) do
    ensure_tables()
    :ets.update_counter(@rev_table, {g, z}, 1, {{g, z}, 0})
    Phoenix.PubSub.broadcast(Bacon8.PubSub, topic(g, z), msg)
  end

  defp zone_ok(zone) when is_binary(zone) and byte_size(zone) in 1..80, do: :ok
  defp zone_ok(_), do: {:error, "That isn't a zone."}

  defp fields(attrs, current) do
    with {:ok, x} <- num(attrs["x"], Map.get(current, :x)),
         {:ok, y} <- num(attrs["y"], Map.get(current, :y) || 0.0),
         {:ok, z} <- num(attrs["z"], Map.get(current, :z)),
         {:ok, rot} <- num(attrs["rot"], Map.get(current, :rot) || 0.0),
         {:ok, scale} <- num(attrs["scale"], Map.get(current, :scale) || 1.0),
         true <- (abs(x) <= @max_extent and abs(y) <= @max_extent and abs(z) <= @max_extent) || {:error, "That's too far out of the world."},
         {:ok, frame} <- frame(Map.get(attrs, "frame", Map.get(current, :frame))) do
      {:ok, %{x: x, y: y, z: z, rot: wrap(rot), scale: scale |> max(0.5) |> min(2.0), frame: frame,
              data: data(attrs["data"], Map.get(current, :data) || %{})}}
    end
  end

  defp frame(nil), do: {:ok, nil}
  defp frame(f) when is_binary(f) and byte_size(f) <= 64, do: {:ok, f}
  defp frame(_), do: {:error, "That isn't a frame."}

  # what the hub keeps of a game's data: a full turn ("q") and a stretch ("s"); the old ones when not given
  defp data(raw, old) do
    raw = if is_map(raw), do: raw, else: %{}

    for k <- ["q", "s"], v = vec(Map.get(raw, k, old[k]), if(k == "q", do: 4, else: 3)), v != nil, into: %{}, do: {k, v}
  end

  defp vec(list, n) when is_list(list) and length(list) == n do
    if Enum.all?(list, &(is_number(&1) and finite?(&1))), do: Enum.map(list, &(&1 * 1.0)), else: nil
  end

  defp vec(_, _), do: nil

  defp num(v, _default) when is_number(v), do: if(finite?(v), do: {:ok, v * 1.0}, else: {:error, "That isn't a place."})
  defp num(nil, default) when is_number(default), do: {:ok, default * 1.0}
  defp num(_, _), do: {:error, "That isn't a place."}

  defp finite?(v), do: v == v and abs(v) < 1.0e12

  defp wrap(r), do: :math.atan2(:math.sin(r), :math.cos(r))

  defp user_id(%{id: id}), do: id
  defp user_id(_), do: nil
end

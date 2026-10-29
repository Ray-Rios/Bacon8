defmodule BaconWorld.Building do
  @moduledoc """
  World building in game (2026-10-28; the owner's plan in BACON_WORLD.md, "World building in
  game"). Press ` in the world for build mode: a searchable window lists what this account may
  place; pick one and click the ground to put it there; click a placed object to pick it up and
  move it (right button held turns it), right-click one to delete it. The client is
  `build-world.ts`; the events are `BaconWorldWeb.BuildEvents`.

  **The catalogue** (`catalogue/0`) is every placeable asset:

    * the village props (`P_<Id>`, `/models/World/B8_Props.glb`), sorted into trees and plants,
      rocks and the rest;
    * the building kit's pieces (`K_<Id>`, `B8_BuildKit.glb`, a 3 m grid);
    * creature spawns (`"mob:<kind>"`, every kind in `BaconWorld.Mobs.Spawns`): the zone spawns
      `count` of them within `radius` metres of the spot, and respawns them there;
    * NPCs (`"npc:<template>"`, `BaconWorld.Merchants.templates/0`): a villager, a clothier, an
      angler, a stablemaster. A placed merchant trades like the village's own.

  **Who may place what** is a role per asset: the lowest role that may place it, and so move it
  and delete any copy of it, whoever placed it (the owner, 2026-10-26). Admins change it in game
  (`set_rule/3`, stored in `bacon_world_asset_rules`); without a row the catalogue's default
  holds: props and building pieces for members, creatures and NPCs for GMs, bosses and the
  waystone for admins. Guests and the banned place nothing, whatever a rule says. Every check is
  made here, on the server.

  Roles rank `admin > gm > moderator > editor > member > guest > banned` (the hub's roles;
  an account with `is_admin` counts as admin).

  Positions are metres (the client's world group is scaled), `y` the height of the object's
  base. Every change is broadcast on `topic/1` (`{:build_placed, view}`,
  `{:build_removed, id, asset}`), so every client in the zone sees it at once.
  """

  import Ecto.Query
  require Logger

  alias Bacon8.GamesRepo
  alias BaconWorld.{AssetRule, Merchants, Mobs, Placement}
  alias BaconWorld.Mobs.Spawns

  @rank %{"banned" => 0, "guest" => 1, "member" => 2, "editor" => 3, "moderator" => 4, "gm" => 5, "admin" => 6}
  @roles ~w(member editor moderator gm admin)

  @props ~w(Amphora Anvil ArcheryTarget Banner Barrel BarrelSide BarrelWater Basket Bed Bedroll Bench Book
            Bookshelf Bottle Boulder Bowl Brazier Bucket Bush BushFlowers Cabinet Campfire Candelabra Candle
            Cart Cauldron Chair Chest ClayPot CoinPile Crate CrateSmall CrateStack Desk FishingFish FoodBread
            FoodCheese FoodMeat FoodPumpkin Forge GemPile Goblet GrassTuft Haystack Jug Key LampPost
            LanternProp Lever Log LootBag MarketStall Mug Mushrooms PlateFood PotionBlue PotionGreen PotionRed
            PressurePlate Rock1 Rock2 Rock3 RopeCoil Rug Sack SackPile Scarecrow Scroll SignHanging Signpost
            Skull Statue Stool Stump Table TableRound Tent Throne Tombstone TorchSconce TrainingDummy TreeDead
            TreeOak TreePine Waystone WeaponRack Well Wheelbarrow Woodpile Workbench)
  @kit ~w(Arch_Stone Beam_Wood Chimney_Stone Door_Wood Fence_Gate Fence_Stone Fence_Wood Floor_Stone
          Floor_Wood Foundation_Stone Foundation_Wood Gate_Wood Ladder_Wood Pillar_Stone Pillar_Wood
          Railing_Wood Roof_Flat Roof_Ridge Roof_Shingle Roof_Thatch Roof_Tile Shutters_Wood Stairs_Stone
          Stairs_Wood Wall_Stone Wall_Stone_Door Wall_Stone_Gable Wall_Stone_Gateway Wall_Stone_Half
          Wall_Stone_Window Wall_Wood Wall_Wood_Door Wall_Wood_Gable Wall_Wood_Half Wall_Wood_Window
          Window_Glass)
  @plants ~w(Bush BushFlowers GrassTuft Mushrooms Stump Log TreeDead TreeOak TreePine Haystack)
  @rocks ~w(Boulder Rock1 Rock2 Rock3)
  # the waystone will be the binding stone (BACON_WORLD.md): admins only, like the bosses
  @admin_props ~w(Waystone)

  # around a binding stone (a placed waystone) only GMs and admins may build: the town's and
  # anywhere else an admin puts one (the owner, 2026-10-28: 100 m)
  @binding_asset "P_Waystone"
  @binding_radius 100.0
  @binding_role "gm"

  @max_count 12
  @max_radius 40.0
  @max_extent 6000.0

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
  # The catalogue
  # ---------------------------------------------------------------------------

  @doc """
  Every placeable asset: `%{id, name, category, kind ("model" | "mob" | "npc"), default_role,
  model, file}` (`model` the node in `file`, `"props"` or `"kit"`, for the models).
  """
  def catalogue do
    props =
      for p <- @props do
        category = cond do
          p in @plants -> "Trees & plants"
          p in @rocks -> "Rocks"
          true -> "Props"
        end

        %{id: "P_" <> p, name: words(p), category: category, kind: "model", default_role: if(p in @admin_props, do: "admin", else: "member"), model: "P_" <> p, file: "props"}
      end

    kit = for k <- @kit, do: %{id: "K_" <> k, name: k |> String.replace("_", " ") |> words(), category: "Building", kind: "model", default_role: "member", model: "K_" <> k, file: "kit"}
    # the stone plinth the village's houses stand on (world-dressing.ts makes it; no file of its own)
    kit = kit ++ [%{id: "X_Plinth", name: "Stone plinth", category: "Building", kind: "model", default_role: "member", model: "X_Plinth", file: nil}]
    # the Robin Hood hat (2026-10-29), made in code (crafted.ts) like the plinth
    kit = kit ++ [%{id: "X_RobinHat", name: "Robin Hood hat", category: "Props", kind: "model", default_role: "member", model: "X_RobinHat", file: nil}]

    mobs =
      for {kind, def} <- Enum.sort_by(Spawns.kinds(), fn {_k, d} -> {Map.get(d, :boss, false), Enum.min(d.levels)} end) do
        boss = Map.get(def, :boss, false)
        %{id: "mob:" <> kind, name: def.name |> String.replace(~r/^(a|an|the) /, "") |> cap(), category: "Creatures", kind: "mob", default_role: if(boss, do: "admin", else: "gm"), model: nil, file: nil,
          levels: [Enum.min(def.levels), Enum.max(def.levels)], boss: boss}
      end

    npcs = for t <- Merchants.templates(), do: %{id: "npc:" <> t.id, name: cap(t.label), category: "NPCs", kind: "npc", default_role: "gm", model: nil, file: nil}

    props ++ kit ++ mobs ++ npcs
  end

  @doc "A catalogue entry by id, or nil."
  def asset(id), do: Map.get(catalogue_map(), id)

  defp catalogue_map do
    case :persistent_term.get({__MODULE__, :catalogue}, nil) do
      nil ->
        m = Map.new(catalogue(), &{&1.id, &1})
        :persistent_term.put({__MODULE__, :catalogue}, m)
        m

      m ->
        m
    end
  end

  @doc "`%{asset => min_role}`: the admins' rules over the defaults."
  def rules do
    saved = GamesRepo.all(from(r in AssetRule, select: {r.asset, r.min_role})) |> Map.new()
    Map.new(catalogue(), fn a -> {a.id, Map.get(saved, a.id, a.default_role)} end)
  rescue
    e ->
      Logger.warning("bacon_world:building rules unavailable #{inspect(e)}")
      Map.new(catalogue(), &{&1.id, &1.default_role})
  end

  @doc "The lowest role that may place `asset_id` (nil for an unknown asset)."
  def min_role(asset_id, rules \\ nil) do
    if asset(asset_id), do: Map.get(rules || rules(), asset_id), else: nil
  end

  @doc "True when `user` may place (and move and delete) `asset_id`."
  def can_place?(user, asset_id, rules \\ nil) do
    case min_role(asset_id, rules) do
      nil -> false
      min -> at_least?(role_of(user), min)
    end
  end

  @doc "The catalogue as the build window shows it to `user`: each entry with its rule and whether they may use it."
  def catalogue_for(user) do
    rules = rules()
    role = role_of(user)

    for a <- catalogue() do
      min = Map.fetch!(rules, a.id)
      a |> Map.put(:min_role, min) |> Map.put(:allowed, at_least?(role, min))
    end
  end

  @doc "Sets the lowest role for an asset (admins only). `{:ok, role}` or `{:error, message}`."
  def set_rule(user, asset_id, role) do
    cond do
      not admin?(user) -> {:error, "Only admins can change who may build what."}
      is_nil(asset(asset_id)) -> {:error, "There is no such thing to place."}
      role not in @roles -> {:error, "That isn't a role."}
      true ->
        now = DateTime.utc_now() |> DateTime.truncate(:second)

        GamesRepo.insert_all(AssetRule, [%{asset: asset_id, min_role: role, updated_by: user_id(user), inserted_at: now, updated_at: now}],
          on_conflict: {:replace, [:min_role, :updated_by, :updated_at]},
          conflict_target: [:asset]
        )

        {:ok, role}
    end
  end

  # ---------------------------------------------------------------------------
  # Placements
  # ---------------------------------------------------------------------------

  @doc "The PubSub topic a zone's building is broadcast on."
  def topic(zone), do: "bacon_world:build:#{zone}"

  @doc "Every placement in a zone, as `view/1` maps."
  def list(zone) do
    GamesRepo.all(from(p in Placement, where: p.zone == ^zone, order_by: p.inserted_at)) |> Enum.map(&view/1)
  rescue
    _ -> []
  end

  @doc """
  Puts `attrs` (`"asset"`, `"x"`, `"y"`, `"z"`, `"rot"`, `"scale"`, `"data"`) in `zone` for
  `user`'s `character_id`. `{:ok, view}` or `{:error, message}`.
  """
  def place(user, character_id, zone, attrs) when is_map(attrs) do
    asset_id = attrs["asset"]

    with %{} = a <- asset(asset_id) || {:error, "There is no such thing to place."},
         true <- can_place?(user, asset_id) || {:error, "You aren't allowed to place #{a.name}."},
         {:ok, fields} <- fields(a, attrs, %{}),
         :ok <- town_ok(user, zone, [{fields.x, fields.z}]) do
      row = struct(Placement, Map.merge(fields, %{zone: zone, asset: asset_id, placed_by: user_id(user), character_id: character_id}))

      case GamesRepo.insert(row) do
        {:ok, p} ->
          after_change(p)
          {:ok, view(p)}

        {:error, _} ->
          {:error, "That couldn't be placed."}
      end
    end
  end

  @doc "Moves (or turns, resizes, retunes) a placement. `{:ok, view}` or `{:error, message}`."
  def move(user, zone, id, attrs) when is_map(attrs) do
    with %Placement{} = p <- get(zone, id) || {:error, "That isn't there any more."},
         %{} = a <- asset(p.asset) || {:error, "That can't be moved."},
         true <- can_place?(user, p.asset) || {:error, "You aren't allowed to move #{a.name}."},
         {:ok, fields} <- fields(a, attrs, p),
         :ok <- town_ok(user, zone, [{p.x, p.z}, {fields.x, fields.z}], p.id) do
      case p |> Ecto.Changeset.change(fields) |> GamesRepo.update() do
        {:ok, p2} ->
          after_change(p2)
          {:ok, view(p2)}

        {:error, _} ->
          {:error, "That couldn't be moved."}
      end
    end
  end

  @doc "Deletes a placement. `{:ok, view}` (what was deleted, for an undo) or `{:error, message}`."
  def delete(user, zone, id) do
    with %Placement{} = p <- get(zone, id) || {:error, "That isn't there any more."},
         true <- can_place?(user, p.asset) || {:error, "You aren't allowed to remove #{(asset(p.asset) || %{name: "that"}).name}."},
         :ok <- town_ok(user, zone, [{p.x, p.z}], p.id),
         {:ok, _} <- GamesRepo.delete(p) do
      if String.starts_with?(p.asset, "mob:"), do: Mobs.put_points(zone, p.id, [])
      Phoenix.PubSub.broadcast(Bacon8.PubSub, topic(zone), {:build_removed, p.id, p.asset})
      {:ok, view(p)}
    else
      {:error, %Ecto.Changeset{}} -> {:error, "That couldn't be removed."}
      other -> other
    end
  end

  defp get(zone, id) when is_binary(id) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} -> GamesRepo.one(from(p in Placement, where: p.zone == ^zone and p.id == ^uuid))
      :error -> nil
    end
  end

  defp get(_zone, _id), do: nil

  # After an insert or update: the creatures move with their spawn, everyone is told.
  defp after_change(p) do
    if String.starts_with?(p.asset, "mob:"), do: Mobs.put_points(p.zone, p.id, points_for(p))
    Phoenix.PubSub.broadcast(Bacon8.PubSub, topic(p.zone), {:build_placed, view(p)})
  end

  # The fields from a client's attrs, checked; `current` fills what's missing (a move).
  defp fields(a, attrs, current) do
    with {:ok, x} <- num(attrs["x"], Map.get(current, :x)),
         {:ok, z} <- num(attrs["z"], Map.get(current, :z)),
         {:ok, y} <- num(attrs["y"], Map.get(current, :y) || 0.0),
         {:ok, rot} <- num(attrs["rot"], Map.get(current, :rot) || 0.0),
         {:ok, scale} <- num(attrs["scale"], Map.get(current, :scale) || 1.0),
         true <- (abs(x) <= @max_extent and abs(z) <= @max_extent and y >= -600.0 and y <= 2500.0) || {:error, "That's too far out of the world."},
         true <- inside_terrain?(x, z) || {:error, "That's off the edge of the map."} do
      {:ok,
       %{x: x, y: y, z: z, rot: wrap(rot), scale: scale |> max(0.5) |> min(2.0),
         data: data(a, attrs["data"], Map.get(current, :data) || %{})}}
    end
  end

  defp inside_terrain?(x, z) do
    case BaconWorld.Terrain.loaded() do
      nil -> true
      t -> BaconWorld.Terrain.inside?(t, x, z)
    end
  end

  # Per-kind data: a creature spawn's count and radius, an NPC's name. Anything else is dropped.
  defp data(%{kind: "mob"}, raw, old) do
    raw = if is_map(raw), do: raw, else: %{}
    count = int(raw["count"], old["count"] || 1) |> max(1) |> min(@max_count)
    radius = float(raw["radius"], old["radius"] || (if count > 1, do: 4.0, else: 0.0)) |> max(0.0) |> min(@max_radius)
    Map.merge(keep(old), %{"count" => count, "radius" => Float.round(radius, 1)})
  end

  defp data(%{kind: "npc"}, raw, old) do
    raw = if is_map(raw), do: raw, else: %{}

    name =
      case raw["name"] do
        n when is_binary(n) -> n |> String.trim() |> String.slice(0, 40)
        _ -> old["name"] || ""
      end

    if name == "", do: keep(old), else: Map.put(keep(old), "name", name)
  end

  defp data(_a, _raw, old), do: keep(old)

  # What only the seeding writes, kept through moves: where a piece came from and its stretch
  # (non-uniform size: [x, y, z], the village's gables and crags).
  defp keep(old), do: Map.take(old || %{}, ["origin", "s"])

  @doc "A placement as clients get it (metres, radians)."
  def view(%Placement{} = p) do
    base = %{id: p.id, asset: p.asset, x: r(p.x), y: r(p.y), z: r(p.z), rot: Float.round(p.rot * 1.0, 4), scale: Float.round(p.scale * 1.0, 3), data: p.data || %{}}

    case p.asset do
      "npc:" <> _ -> Map.put(base, :npc, Merchants.npc_payload(npc(p)))
      _ -> base
    end
  end

  # ---------------------------------------------------------------------------
  # Binding stones
  # ---------------------------------------------------------------------------

  @doc "Metres round a binding stone where only GMs and admins may build."
  def binding_radius, do: @binding_radius

  @doc "The binding stones (placed waystones) of a zone: `[%{id, x, y, z}]`, metres."
  def binding_stones(zone) do
    GamesRepo.all(from(p in Placement, where: p.zone == ^zone and p.asset == @binding_asset, select: %{id: p.id, x: p.x, y: p.y, z: p.z}))
  rescue
    _ -> []
  end

  @doc "The binding stone within `reach` metres of a point (metres), or nil."
  def binding_stone_near(zone, x, z, reach \\ 5.0) do
    Enum.find(binding_stones(zone), fn s -> :math.sqrt((s.x - x) ** 2 + (s.z - z) ** 2) <= reach end)
  end

  @doc """
  Binds a character at the binding stone it stands by (`pos`: its position in scene units, as the
  runtime keeps it). Saves `settings["bind"]` (scene units, a step off the stone so it doesn't
  land inside it), which Recall and respawning read. `{:ok, bind}` or `{:error, msg}`.
  """
  def bind(%{id: user_id}, character_id, zone, %{x: x, z: z} = pos) do
    u = BaconWorld.Mobs.Brain.u()

    case binding_stone_near(zone, x / u, z / u) do
      nil ->
        {:error, "There is no binding stone here."}

      stone ->
        {dx, dz} = {x / u - stone.x, z / u - stone.z}
        d = max(:math.sqrt(dx * dx + dz * dz), 0.01)
        {bx, bz} = {stone.x + dx / d * 1.6, stone.z + dz / d * 1.6}
        by = BaconWorld.Terrain.height(bx, bz) * u
        bind = %{"x" => bx * u, "y" => max(by, (pos[:y] || 0.0) * 1.0) * 1.0, "z" => bz * u, "heading" => (pos[:heading] || 0.0) * 1.0, "zone" => zone}

        case BaconWorld.World.merge_settings(BaconWorld.World.owned_query(user_id, character_id), %{"bind" => bind}) do
          1 -> {:ok, bind}
          _ -> {:error, "That can't be done right now."}
        end
    end
  end

  def bind(_user, _character_id, _zone, _pos), do: {:error, "That can't be done right now."}

  @doc "True when (x, z) (metres) lies within a binding stone's radius (`except`: a stone being moved itself)."
  def protected?(zone, x, z, except \\ nil) do
    Enum.any?(binding_stones(zone), fn s -> s.id != except and :math.sqrt((s.x - x) ** 2 + (s.z - z) ** 2) <= @binding_radius end)
  end

  # Building at any of these spots (metres) inside a town needs a GM or better.
  defp town_ok(user, zone, spots, except \\ nil) do
    if at_least?(role_of(user), @binding_role) or not Enum.any?(spots, fn {x, z} -> protected?(zone, x, z, except) end),
      do: :ok,
      else: {:error, "Only GMs and admins may build within #{round(@binding_radius)} m of a binding stone."}
  end

  # ---------------------------------------------------------------------------
  # Seeding: the code's village and camps become placements
  # ---------------------------------------------------------------------------

  @doc """
  Turns the village and the creature camps the code lays out (world-dressing.ts, `Spawns`) into
  placements, once per zone: the files in `priv/seed/` (`village.json`, `camps_<world>.json`, written
  from the client's own layout by the 2026-10-28 harness) are inserted with each piece stood on the
  ground (`BaconWorld.Terrain`) and `data["origin"]` saying where it came from. A row in
  `bacon_world_seeds` (written in the same transaction) makes sure it happens only once, even with
  several nodes, so whatever builders change or delete later stays that way.

  Returns `%{village: bool, camps: [camp id]}`: what is placements now (the client stops drawing
  those pieces itself; the zone stops spawning those camps' creatures from code).
  """
  def ensure_seeded(zone) do
    world = camps_world()
    keys = [{"village", "village.json", "village"}, {"camps:" <> world, "camps_#{world}.json", nil}]
    for {key, file, origin} <- keys, do: seed_once(zone, key, file, origin)
    seeded(zone)
  rescue
    e ->
      Logger.warning("bacon_world:building seed failed zone=#{zone} #{inspect(e)}")
      %{village: false, camps: []}
  end

  @doc "What of a zone's code layout is placements already: `%{village: bool, camps: [camp id]}`."
  def seeded(zone) do
    keys = GamesRepo.all(from(s in "bacon_world_seeds", where: s.zone == ^zone, select: s.key))
    world = camps_world()

    camps =
      if ("camps:" <> world) in keys,
        do: seed_rows("camps_#{world}.json") |> Enum.map(& &1["camp"]) |> Enum.reject(&is_nil/1) |> Enum.uniq(),
        else: []

    %{village: "village" in keys, camps: camps}
  rescue
    _ -> %{village: false, camps: []}
  end

  # The world whose camps the zone has: Crater Lake's with its terrain, the round island's without.
  defp camps_world do
    case BaconWorld.Terrain.loaded() do
      %{id: id} -> id
      _ -> "island"
    end
  end

  defp seed_once(zone, key, file, origin) do
    cache = {__MODULE__, :seeded, zone, key}

    if :persistent_term.get(cache, false) do
      :ok
    else
      rows = seed_rows(file)
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      GamesRepo.transaction(fn ->
        {n, _} = GamesRepo.insert_all("bacon_world_seeds", [%{zone: zone, key: key, count: length(rows), inserted_at: now}], on_conflict: :nothing, conflict_target: [:zone, :key])

        if n == 1 and rows != [] do
          placements =
            for r <- rows do
              x = r["x"] * 1.0
              z = r["z"] * 1.0
              data = Map.merge(r["data"] || %{}, %{"origin" => origin || "camp:" <> r["camp"]})
              %{id: Ecto.UUID.generate(), zone: zone, asset: r["asset"], x: x, y: (r["y"] || 0.0) + BaconWorld.Terrain.height(x, z), z: z, rot: (r["rot"] || 0.0) * 1.0,
                scale: (r["scale"] || 1.0) * 1.0, data: data, inserted_at: now, updated_at: now}
            end

          placements |> Enum.chunk_every(500) |> Enum.each(&GamesRepo.insert_all(Placement, &1))
          Logger.info("bacon_world:building seeded zone=#{zone} key=#{key} placements=#{length(placements)}")
        end
      end)

      :persistent_term.put(cache, true)
    end
  end

  @doc false
  def seed_rows(file) do
    path = Path.join([Bacon8.Plugins.priv_dir("bacon_world"), "seed", file])

    case File.read(path) do
      {:ok, body} -> Jason.decode!(body)
      _ -> []
    end
  end

  # ---------------------------------------------------------------------------
  # Creatures and NPCs
  # ---------------------------------------------------------------------------

  @doc """
  The creature spawn points of a placement (`BaconWorld.Mobs.Spawns.points/0`'s shape: metres):
  `count` of them on a sunflower within `radius`, ids `"p:<placement id>:<n>"`.
  """
  def points_for(%Placement{asset: "mob:" <> kind} = p) do
    if Map.has_key?(Spawns.kinds(), kind) do
      count = (p.data || %{})["count"] || 1
      radius = ((p.data || %{})["radius"] || 0.0) * 1.0
      golden = :math.pi() * (3 - :math.sqrt(5))

      for n <- 0..(count - 1) do
        rr = if count == 1, do: 0.0, else: radius * :math.sqrt((n + 0.5) / count)
        a = n * golden + p.rot
        %{id: "p:#{p.id}:#{n}", camp: "p:#{p.id}", kind: kind, x: p.x + rr * :math.cos(a), z: p.z + rr * :math.sin(a)}
      end
    else
      []
    end
  end

  def points_for(_), do: []

  @doc "Every placed creature spawn point in a zone (the zone process reads them as it starts)."
  def mob_points(zone) do
    GamesRepo.all(from(p in Placement, where: p.zone == ^zone and like(p.asset, "mob:%")))
    |> Enum.flat_map(&points_for/1)
  rescue
    _ -> []
  catch
    :exit, _ -> []
  end

  @doc "The placed NPCs of a zone, as merchants (`BaconWorld.Merchants` shape)."
  def npcs(zone) do
    GamesRepo.all(from(p in Placement, where: p.zone == ^zone and like(p.asset, "npc:%")))
    |> Enum.map(&npc/1)
    |> Enum.reject(&is_nil/1)
  rescue
    _ -> []
  end

  @doc "A placed NPC by its merchant id (`\"p:<placement id>\"`), or nil."
  def npc_by_id("p:" <> id) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} -> (p = GamesRepo.get(Placement, uuid)) && npc(p)
      :error -> nil
    end
  rescue
    _ -> nil
  end

  def npc_by_id(_), do: nil

  defp npc(%Placement{asset: "npc:" <> template} = p), do: Merchants.placed(template, p)
  defp npc(_), do: nil

  # ---------------------------------------------------------------------------

  defp user_id(%{id: id}), do: id
  defp user_id(_), do: nil

  defp num(v, _default) when is_number(v), do: if(finite?(v), do: {:ok, v * 1.0}, else: {:error, "That isn't a place."})
  defp num(nil, default) when is_number(default), do: {:ok, default * 1.0}
  defp num(_, _), do: {:error, "That isn't a place."}

  defp finite?(v), do: v == v and abs(v) < 1.0e9

  defp int(v, _d) when is_integer(v), do: v
  defp int(v, _d) when is_float(v), do: round(v)
  defp int(_, d), do: d

  defp float(v, _d) when is_number(v), do: v * 1.0
  defp float(_, d), do: d * 1.0

  defp wrap(a) do
    tau = 2 * :math.pi()
    a = :math.fmod(a, tau)
    if a < 0, do: a + tau, else: a
  end

  defp r(v), do: Float.round(v * 1.0, 3)

  # "BushFlowers" -> "Bush flowers", "Wall Stone Door" -> "Wall stone door"
  defp words(s) do
    s
    |> String.replace(~r/([a-z])([A-Z0-9])/, "\\1 \\2")
    |> String.downcase()
    |> cap()
  end

  defp cap(<<c::utf8, rest::binary>>), do: String.upcase(<<c::utf8>>) <> rest
  defp cap(s), do: s
end

defmodule BaconWorld.Mobs.Camps do
  @moduledoc """
  Managed camps (2026-11-03): a camp you design on `/admin/bacon_world/bestiary?tab=camps`
  instead of a pile of `mob:` spawns.

  A camp is a row of `bacon_world_defs` kind `"camp"` (`BaconWorld.Defs`) and lives in one zone:

      %{
        name: "Grubnak's Raiders", zone: "lobby", x: 104.0, z: -272.0, rot: 0.0,   # metres
        size: "medium", radius: 10.0,        # small 7 m, medium 10, large 14, huge 20, or custom
        theme: "goblin", features: ["campfire", "tents", "palisade"],   # decor, BaconWorld.Mobs.CampLayout
        levels: nil | 3..6,                  # a level band for everything here (nil: each kind's own)
        elite_chance: 0.05,                  # an elite: tougher, bigger, worth more (World tuning)
        assist_radius: 12.0,                 # social aggro: campmates this close join a fight (0: off)
        respawn_ms: nil | 60_000..90_000,    # instead of each kind's own
        dynamic_respawn: true,               # faster the more players are near (down to half)
        enabled: true,
        slots: [
          %{count: 3, table: [{"goblin", 70}, {"goblin_archer", 30}], mode: "random"},
          %{count: 1, table: [{"goblin", 1}], mode: "placeholder",
            rare: %{kind: "grubnak", chance: 0.08, cooldown_ms: 1_800_000}},
          %{count: 2, table: [{"skeleton", 1}], window: "night", loot_tables: ["graveyard_common"]}
        ],
        clear: %{loot_table: "camp_chest_minor", xp_mult: 1.5, escalate_after: 3, boss: "goblin_warchief"}
      }

  The zone process (`BaconWorld.Mobs.Zone`) spawns `points/2` (ids `"c:<camp id>:<slot>:<n>"`, the
  camp field `"c:<camp id>"`), picks each respawn's creature with `BaconWorld.Mobs.Rotation`, makes
  campmates assist (`assist/3`), and when the last creature of a camp falls (`cleared?/2`) the
  killer's corpse gets the clear's loot, the kill its experience bonus, and every
  `escalate_after` clears its `boss` rises in the middle (`boss_point/2`, spawned once).

  The code's camps and placed `mob:` spawns keep working as they are; `from_legacy/2` turns one of
  the lobby's camps into a managed one (and remembers what it replaced, `legacy`, so it can go back).
  """

  alias BaconWorld.{Defs, Loot}
  alias BaconWorld.Mobs.{Brain, Rotation, Spawns}

  @kind "camp"
  @sizes [{"small", 7.0, 3}, {"medium", 10.0, 5}, {"large", 14.0, 8}, {"huge", 20.0, 12}]
  @themes ~w(goblin orc bandit graveyard ruins barrow warren lair none)
  @features ~w(campfire tents palisade banners supplies braziers graves bones weapon_rack forge cauldron treasure ruins rocks dead_trees throne)
  @max_creatures 24
  @max_radius 40.0

  def kind, do: @kind
  def sizes, do: @sizes
  def themes, do: @themes
  def features, do: @features
  def max_creatures, do: @max_creatures

  @doc "Every managed camp, `[{id, camp}]`."
  def list, do: Defs.list(@kind)

  @doc "A camp by id, or nil."
  def get(id) when is_binary(id), do: Map.get(Defs.map(@kind), id)
  def get(_), do: nil

  @doc "The enabled camps of a zone."
  def for_zone(zone), do: for({id, c} <- list(), c[:zone] == zone, Map.get(c, :enabled, true) != false, do: {id, c})

  @doc "The `camp` field of a managed camp's points and creatures."
  def key(id), do: "c:" <> id

  @doc "The camp id in a `key/1`, or nil."
  def id_of("c:" <> id), do: id
  def id_of(_), do: nil

  @doc "The camp's radius in metres (its size's unless it set its own)."
  def radius(camp) do
    case camp[:radius] do
      r when is_number(r) and r >= 0 -> min(r * 1.0, @max_radius)
      _ -> size_radius(camp[:size])
    end
  end

  def size_radius(size), do: Enum.find_value(@sizes, 10.0, fn {s, r, _} -> s == size && r end)

  @doc "How many creatures a size suggests (the editor's starting point)."
  def size_slots(size), do: Enum.find_value(@sizes, 5, fn {s, _, n} -> s == size && n end)

  @doc "How many creatures the camp holds."
  def population(camp), do: camp |> Map.get(:slots, []) |> Enum.map(&max(0, &1[:count] || 0)) |> Enum.sum()

  # ---------------------------------------------------------------- points

  @doc """
  The camp's spawn points (`BaconWorld.Mobs.Spawns.points/0`'s shape plus the rotation's fields):
  every slot's creatures on one sunflower over the camp, the first slot's nearest the middle.
  """
  def points(id, camp) do
    golden = :math.pi() * (3 - :math.sqrt(5))
    r = radius(camp) * 0.85
    rot = num(camp[:rot], 0.0)

    seats =
      camp
      |> Map.get(:slots, [])
      |> Enum.with_index()
      |> Enum.flat_map(fn {slot, i} -> for n <- 0..(max(slot[:count] || 0, 1) - 1)//1, (slot[:count] || 0) > 0, do: {slot, i, n} end)
      |> Enum.take(@max_creatures)

    total = length(seats)

    seats
    |> Enum.with_index()
    |> Enum.map(fn {{slot, i, n}, k} ->
      rr = if total == 1, do: 0.0, else: r * :math.sqrt((k + 0.5) / total)
      a = k * golden + rot
      table = slot[:table] || []

      %{
        id: "c:#{id}:#{i}:#{n}",
        camp: key(id),
        kind: first_kind(table),
        x: num(camp[:x], 0.0) + rr * :math.cos(a),
        z: num(camp[:z], 0.0) + rr * :math.sin(a),
        table: table,
        mode: slot[:mode] || "random",
        rare: slot[:rare],
        window: slot[:window],
        levels: camp[:levels],
        elite_chance: num(camp[:elite_chance], 0.0),
        respawn_ms: slot[:respawn_ms] || camp[:respawn_ms],
        dynamic_respawn: camp[:dynamic_respawn] == true,
        loot_tables: slot[:loot_tables] || [],
        slot: i
      }
    end)
    |> Enum.filter(&Map.has_key?(Spawns.kinds(), &1.kind))
  end

  @doc "Every enabled managed camp's points in a zone."
  def points_for_zone(zone) do
    Enum.flat_map(for_zone(zone), fn {id, c} -> points(id, c) end)
  rescue
    _ -> []
  end

  @doc "The point a camp's boss rises at when the camp escalates (it spawns once)."
  def boss_point(id, camp) do
    boss = get_in(camp, [:clear, :boss])

    if is_binary(boss) and Map.has_key?(Spawns.kinds(), boss) do
      %{id: "c:#{id}:boss", camp: key(id), kind: boss, x: num(camp[:x], 0.0), z: num(camp[:z], 0.0), once: true, boss_of: id}
    end
  end

  @doc "True for a camp boss's point id."
  def boss_id?(id) when is_binary(id), do: String.ends_with?(id, ":boss")
  def boss_id?(_), do: false

  defp first_kind([{k, _} | _]), do: k
  defp first_kind(_), do: nil

  # ---------------------------------------------------------------- the zone's rules

  @doc "The creatures (living or not) of a camp, by its key, its boss left out."
  def members(mobs, camp_key), do: for({id, m} <- mobs, m.camp == camp_key, not boss_id?(id), do: m)

  @doc "True when none of a camp's creatures (its boss aside) is alive."
  def cleared?(mobs, camp_key) do
    case members(mobs, camp_key) do
      [] -> false
      list -> not Enum.any?(list, &Brain.alive?/1)
    end
  end

  @doc """
  Social aggro: for every `{:aggro, id, character_id}` in `events` whose creature belongs to a
  managed camp with an `assist_radius`, its idle campmates that close come for the same player
  (one hop: an assist doesn't call further help). `camps`: `%{camp_key => camp}`.
  Returns `{mobs, extra_events}`.
  """
  def assist(mobs, events, camps, now) do
    Enum.reduce(events, {mobs, []}, fn
      {:aggro, id, cid}, {acc, extra} ->
        with %{camp: ("c:" <> _) = ck} = mob <- acc[id],
             %{} = camp <- camps[ck],
             r when is_number(r) and r > 0 <- camp[:assist_radius] do
          reach = r * Brain.u()

          Enum.reduce(acc, {acc, extra}, fn {oid, other}, {a2, e2} ->
            if oid != id and other.camp == ck and dist(other, mob) <= reach do
              case Brain.assist(other, cid, now) do
                {_same, []} -> {a2, e2}
                {joined, evs} -> {Map.put(a2, oid, joined), e2 ++ evs}
              end
            else
              {a2, e2}
            end
          end)
        else
          _ -> {acc, extra}
        end

      _other, acc ->
        acc
    end)
  end

  defp dist(a, b), do: :math.sqrt((a.x - b.x) * (a.x - b.x) + (a.z - b.z) * (a.z - b.z))

  @doc """
  What a camp's clear gives, rolled for the creature that fell last: `%{items, coins, xp_mult}`
  (nothing when the camp has no clear reward).
  """
  def clear_reward(camp, level) do
    clear = camp[:clear] || %{}
    loot = if is_binary(clear[:loot_table]), do: Loot.roll(clear[:loot_table], level), else: %{items: [], coins: 0}
    Map.put(loot, :xp_mult, max(num(clear[:xp_mult], 1.0), 0.0))
  end

  @doc "True when this many clears (since the last boss) call the camp's boss."
  def escalates?(camp, clears) do
    n = get_in(camp, [:clear, :escalate_after]) || 0
    is_integer(n) and n > 0 and clears >= n and boss_point("x", camp) != nil
  end

  # ---------------------------------------------------------------- editing

  @doc """
  A camp from the admin form. Top-level fields: `name zone x z rot size radius theme levels
  elite_pct assist_radius respawn_s dynamic_respawn enabled`, `features` (a list), `clear_*`
  (`loot_table xp_mult escalate_after boss`), and `slots` (`%{"0" => %{"count", "table", "mode",
  "rare_kind", "rare_pct", "rare_cooldown_min", "window", "loot_tables", "respawn_s"}}`).
  Tables are written `goblin 70, goblin_archer 30`. `{:ok, camp}` or `{:error, [message]}`.
  """
  def from_form(p, old \\ %{}) do
    size = if p["size"] in Enum.map(@sizes, &elem(&1, 0)) ++ ["custom"], do: p["size"], else: "medium"

    radius =
      case {size, float(p["radius"])} do
        {"custom", r} when is_number(r) -> r |> max(0.0) |> min(@max_radius)
        {s, _} -> size_radius(s)
      end

    slots =
      (p["slots"] || %{})
      |> Enum.sort_by(fn {k, _} -> int(k, 0) end)
      |> Enum.map(fn {_k, s} -> slot_from_form(s) end)
      |> Enum.reject(&(&1.count <= 0 and &1.table == []))

    camp = %{
      name: text(p["name"], 80),
      zone: text(p["zone"], 40),
      x: float(p["x"]) || 0.0,
      z: float(p["z"]) || 0.0,
      rot: float(p["rot"]) || 0.0,
      size: size,
      radius: radius,
      theme: if(p["theme"] in @themes, do: p["theme"], else: "none"),
      features: Enum.filter(List.wrap(p["features"]), &(&1 in @features)),
      levels: Loot.parse_range(to_string(p["levels"] || "")),
      elite_chance: ((float(p["elite_pct"]) || 0.0) / 100) |> max(0.0) |> min(1.0),
      assist_radius: (float(p["assist_radius"]) || 0.0) |> max(0.0) |> min(60.0),
      respawn_ms: seconds_range(p["respawn_s"]),
      dynamic_respawn: p["dynamic_respawn"] in ["true", "on", true],
      enabled: p["enabled"] in ["true", "on", true],
      slots: slots,
      clear: %{
        loot_table: blank_nil(p["clear_loot_table"]),
        xp_mult: (float(p["clear_xp_mult"]) || 1.0) |> max(0.0) |> min(10.0),
        escalate_after: int(p["clear_escalate_after"], 0) |> max(0) |> min(100),
        boss: blank_nil(p["clear_boss"])
      }
    }

    camp = if old[:legacy], do: Map.put(camp, :legacy, old[:legacy]), else: camp

    case validate(camp) do
      [] -> {:ok, camp}
      errors -> {:error, errors}
    end
  end

  defp slot_from_form(s) do
    rare_kind = blank_nil(s["rare_kind"])

    rare =
      if rare_kind,
        do: %{kind: rare_kind, chance: ((float(s["rare_pct"]) || 5.0) / 100) |> max(0.0) |> min(1.0), cooldown_ms: round((float(s["rare_cooldown_min"]) || 0.0) * 60_000)},
        else: nil

    %{
      # not clamped: validate/1 says when there are too many
      count: int(s["count"], 1) |> max(0),
      table: parse_table(s["table"]),
      mode: if(s["mode"] in Rotation.modes(), do: s["mode"], else: "random"),
      rare: rare,
      window: if(s["window"] in ["day", "night"], do: s["window"], else: nil),
      loot_tables: s["loot_tables"] |> to_string() |> String.split(~r/[\s,]+/, trim: true),
      respawn_ms: seconds_range(s["respawn_s"])
    }
  end

  @doc "A camp as the admin form's fields (`from_form/2`'s inverse)."
  def to_form(camp) do
    clear = camp[:clear] || %{}

    %{
      "name" => camp[:name] || "",
      "zone" => camp[:zone] || "lobby",
      "x" => fmt(camp[:x] || 0.0),
      "z" => fmt(camp[:z] || 0.0),
      "rot" => fmt(camp[:rot] || 0.0),
      "size" => camp[:size] || "medium",
      "radius" => fmt(radius(camp)),
      "theme" => camp[:theme] || "none",
      "features" => camp[:features] || [],
      "levels" => (camp[:levels] && Loot.range_text(camp[:levels])) || "",
      "elite_pct" => fmt(num(camp[:elite_chance], 0.0) * 100),
      "assist_radius" => fmt(num(camp[:assist_radius], 0.0)),
      "respawn_s" => seconds_text(camp[:respawn_ms]),
      "dynamic_respawn" => camp[:dynamic_respawn] == true,
      "enabled" => Map.get(camp, :enabled, true) != false,
      "clear_loot_table" => clear[:loot_table] || "",
      "clear_xp_mult" => fmt(num(clear[:xp_mult], 1.0)),
      "clear_escalate_after" => to_string(clear[:escalate_after] || 0),
      "clear_boss" => clear[:boss] || "",
      "slots" =>
        camp
        |> Map.get(:slots, [])
        |> Enum.with_index()
        |> Map.new(fn {s, i} ->
          {to_string(i),
           %{
             "count" => to_string(s[:count] || 1),
             "table" => table_text(s[:table] || []),
             "mode" => s[:mode] || "random",
             "rare_kind" => (s[:rare] && s.rare[:kind]) || "",
             "rare_pct" => (s[:rare] && fmt(num(s.rare[:chance], 0.0) * 100)) || "",
             "rare_cooldown_min" => (s[:rare] && fmt((s.rare[:cooldown_ms] || 0) / 60_000)) || "",
             "window" => s[:window] || "",
             "loot_tables" => Enum.join(s[:loot_tables] || [], ", "),
             "respawn_s" => seconds_text(s[:respawn_ms])
           }}
        end)
    }
  end

  @doc "A blank camp of a size, at a spot."
  def blank(zone, x, z, size \\ "medium") do
    %{name: "", zone: zone, x: x, z: z, rot: 0.0, size: size, radius: size_radius(size), theme: "none", features: [], levels: nil,
      elite_chance: 0.0, assist_radius: 0.0, respawn_ms: nil, dynamic_respawn: false, enabled: true,
      slots: [%{count: size_slots(size), table: [], mode: "random", rare: nil, window: nil, loot_tables: [], respawn_ms: nil}],
      clear: %{loot_table: nil, xp_mult: 1.0, escalate_after: 0, boss: nil}}
  end

  @doc "What's wrong with a camp (messages; empty when it's fine)."
  def validate(camp) do
    kinds = Spawns.kinds()
    tables = Defs.map(Loot.kind())
    slots = camp[:slots] || []
    named = fn k -> Map.has_key?(kinds, k) end

    [
      camp[:name] in [nil, ""] && "Give the camp a name.",
      camp[:zone] in [nil, ""] && "Pick the camp's zone.",
      slots == [] && "A camp needs at least one slot of creatures.",
      population(camp) > @max_creatures && "At most #{@max_creatures} creatures a camp.",
      population(camp) < 1 && "A camp needs at least one creature.",
      match?(%Range{}, camp[:levels]) and (camp.levels.first < 1 or camp.levels.last > 60) && "Levels go from 1 to 60."
    ]
    |> Kernel.++(
      Enum.flat_map(Enum.with_index(slots, 1), fn {s, i} ->
        unknown = for {k, _} <- s.table, not named.(k), do: k

        [
          s.table == [] && "Slot #{i}: which creatures? (e.g. goblin 70, goblin_archer 30)",
          unknown != [] && "Slot #{i}: no monster type #{Enum.join(unknown, ", ")}.",
          s[:rare] && not named.(s.rare.kind) && "Slot #{i}: no monster type #{s.rare.kind} for the rare.",
          Enum.any?(s[:loot_tables] || [], &(not Map.has_key?(tables, &1))) && "Slot #{i}: an unknown loot table."
        ]
      end)
    )
    |> Kernel.++([
      (b = get_in(camp, [:clear, :boss])) && not named.(b) && "No monster type #{b} for the boss.",
      (t = get_in(camp, [:clear, :loot_table])) && not Map.has_key?(tables, t) && "No loot table #{t} for the clear."
    ])
    |> Enum.filter(&is_binary/1)
  end

  @doc "`goblin 70, goblin_archer 30` (or one a line) as `[{kind, weight}]`; a missing weight is 1."
  def parse_table(text) do
    text
    |> to_string()
    |> String.split(~r/[,\n]+/, trim: true)
    |> Enum.map(&String.split(String.trim(&1), ~r/\s+/, trim: true))
    |> Enum.flat_map(fn
      [k] -> [{k, 1}]
      [k, w | _] -> [{k, max(int(w, 1), 0)}]
      _ -> []
    end)
    |> Enum.reject(fn {_k, w} -> w <= 0 end)
  end

  def table_text(table), do: Enum.map_join(table, ", ", fn {k, w} -> "#{k} #{w}" end)

  @doc "An id for a new camp from its name."
  def slug(name), do: Loot.slug(name)

  # ---------------------------------------------------------------- the old camps

  @doc """
  A managed camp made from one of the lobby's code camps (`BaconWorld.Mobs.Spawns.camps/0`) and the
  `mob:` spawn placements its seeding made (`placements`: `BaconWorld.Placement`s whose
  `data["origin"]` is `"camp:<camp id>"`): one slot per spawn, the same creatures, the same place.
  The placements go in `legacy`, so `BaconWorldWeb.Admin.BestiaryLive` can put them back.
  """
  def from_legacy(code_camp, zone, placements) do
    spawns = Enum.filter(placements, &String.starts_with?(&1.asset, "mob:"))

    slots =
      Enum.map(spawns, fn p ->
        "mob:" <> kind = p.asset
        %{count: (p.data || %{})["count"] || 1, table: [{kind, 1}], mode: "random", rare: nil, window: nil, loot_tables: [], respawn_ms: nil}
      end)

    %{
      name: code_camp.name |> String.replace_prefix("the ", "") |> cap(),
      zone: zone,
      x: code_camp.x,
      z: code_camp.z,
      rot: 0.0,
      size: "custom",
      radius: code_camp.radius,
      theme: if(code_camp.theme in @themes, do: code_camp.theme, else: "none"),
      features: [],
      levels: nil,
      elite_chance: 0.0,
      assist_radius: 0.0,
      respawn_ms: nil,
      dynamic_respawn: false,
      enabled: true,
      slots: slots,
      clear: %{loot_table: nil, xp_mult: 1.0, escalate_after: 0, boss: nil},
      legacy: %{
        camp: code_camp.id,
        placements: Enum.map(spawns, &%{"asset" => &1.asset, "x" => &1.x, "y" => &1.y, "z" => &1.z, "rot" => &1.rot, "scale" => &1.scale, "data" => &1.data || %{}})
      }
    }
  end

  defp cap(<<c::utf8, rest::binary>>), do: String.upcase(<<c::utf8>>) <> rest
  defp cap(s), do: s

  # ---------------------------------------------------------------- small things

  defp seconds_range(v) do
    case Loot.parse_range(to_string(v || "")) do
      %Range{first: a, last: b} when a >= 1 -> (a * 1000)..(b * 1000)
      _ -> nil
    end
  end

  defp seconds_text(%Range{first: a, last: b}) when a == b, do: to_string(div(a, 1000))
  defp seconds_text(%Range{first: a, last: b}), do: "#{div(a, 1000)}-#{div(b, 1000)}"
  defp seconds_text(_), do: ""

  defp text(v, n), do: v |> to_string() |> String.trim() |> String.slice(0, n)

  defp blank_nil(v) do
    case v |> to_string() |> String.trim() do
      "" -> nil
      s -> s
    end
  end

  defp float(v) do
    case Float.parse(to_string(v || "")) do
      {f, _} -> f
      :error -> nil
    end
  end

  defp int(v, default) do
    case Integer.parse(to_string(v || "")) do
      {n, _} -> n
      :error -> default
    end
  end

  defp num(v, _d) when is_float(v), do: v
  defp num(v, _d) when is_integer(v), do: v * 1.0
  defp num(_, d), do: d

  defp fmt(f) when is_float(f), do: :erlang.float_to_binary(f, [:compact, decimals: 2])
  defp fmt(v), do: to_string(v)
end

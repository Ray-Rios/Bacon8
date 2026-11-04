defmodule BaconWorld.Bestiary do
  @moduledoc """
  The monster editor's rules (2026-11-03, `/admin/bacon_world/bestiary`): monster types
  (`bacon_world_defs` kind `"monster"`, read by `BaconWorld.Mobs.Spawns`) to and from the page's
  form, a preview of what one is at a level, and the examples the page can import.

  A monster type made here borrows one of the client's rigs (`model`: `models/0`), so it needs no
  new art: "Grubnak" is a goblin with his own name, numbers, gear and loot. Everything the form
  doesn't show (a dragon's `breath`, the Kraken's `specials`...) rides along in the Advanced box as
  JSON (`BaconWorld.Defs` codec), so editing never loses it.
  """

  alias BaconWorld.{Defs, Items, Loot, Melee, Progression, Tuning}
  alias BaconWorld.Mobs.{Camps, Spawns}

  # the rigs the client can draw (mobs-view.ts MODELS, RATS, DRAGONS, KRAKENS)
  @models ~w(skeleton decaying_skeleton skeleton_warrior goblin goblin_archer orc orc_warlord giant_rat plague_rat baconator kraken)

  # what the form edits; anything else goes to Advanced
  @form_keys ~w(name model rank family levels hp dmg dly_ms walk run aggro leash reach radius scale respawn_ms coins
                weapon_drop weapons offhand loot drops loot_tables xp_mult boss ranged aquatic roam moves)a

  def models, do: @models

  @doc "The monster types as `[{id, kind}]`."
  def list, do: Defs.list("monster")

  @doc "Where a monster type is used: the managed camps that name it (`[{camp id, name}]`)."
  def used_by(id) do
    for {cid, c} <- Camps.list(),
        Enum.any?(c[:slots] || [], fn s -> Enum.any?(s[:table] || [], &(elem(&1, 0) == id)) or (s[:rare] && s.rare[:kind] == id) end) or
          get_in(c, [:clear, :boss]) == id,
        do: {cid, c[:name]}
  end

  # ---------------------------------------------------------------- the form

  @doc "A blank monster type to start from (a level 1 skeleton's numbers)."
  def blank do
    %{name: "", model: "skeleton", rank: "normal", levels: 1..2, hp: {20, 8}, dmg: {1, 4}, dly_ms: 2000, walk: 1.2, run: 3.6,
      aggro: 10.0, reach: 1.0, coins: 1..6, weapon_drop: 0.5, weapons: [{"worn_club", 1}], offhand: [{nil, 1}], loot: []}
  end

  @doc "A monster type as the form's fields (strings)."
  def to_form(id, k) do
    {hb, hp} = k[:hp] || {20, 8}
    {dl, dh} = k[:dmg] || {1, 4}
    advanced = Map.drop(k, @form_keys)

    %{
      "id" => id || "",
      "name" => k[:name] || "",
      "model" => k[:model] || (id in @models && id) || "skeleton",
      "rank" => Spawns.rank(k),
      "family" => k[:family] || "",
      "levels" => Loot.range_text(k[:levels] || 1..1),
      "hp_base" => to_string(hb),
      "hp_per" => to_string(hp),
      "dmg" => "#{dl}-#{dh}",
      "dly_ms" => to_string(k[:dly_ms] || 2000),
      "walk" => fmt(k[:walk] || 1.2),
      "run" => fmt(k[:run] || 3.6),
      "aggro" => fmt(k[:aggro] || 10.0),
      "leash" => (k[:leash] && fmt(k[:leash])) || "",
      "reach" => fmt(k[:reach] || 1.0),
      "radius" => (k[:radius] && fmt(k[:radius])) || "",
      "scale" => (k[:scale] && fmt(k[:scale])) || "",
      "respawn_s" => respawn_text(k[:respawn_ms]),
      "coins" => Loot.range_text(k[:coins] || 0..0),
      "weapon_drop" => fmt((k[:weapon_drop] || 0.0) * 100),
      "weapons" => weighted_text(k[:weapons] || []),
      "offhand" => weighted_text(k[:offhand] || []),
      "loot" => Enum.map_join(k[:loot] || [], "\n", fn {item, chance, qty} -> "#{item} #{fmt(chance * 100)}% #{Loot.range_text(qty)}" end),
      "drops" => Enum.map_join(k[:drops] || [], "\n", fn {item, chance} -> "#{item} #{fmt(chance * 100)}%" end),
      "loot_tables" => Enum.join(k[:loot_tables] || [], ", "),
      "xp_mult" => fmt(k[:xp_mult] || 1.0),
      "boss" => k[:boss] == true,
      "ranged" => k[:ranged] == true,
      "aquatic" => k[:aquatic] == true,
      "roam" => (k[:roam] && fmt(k[:roam])) || "",
      "moves" => weighted_text(k[:moves] || []),
      "advanced" => if(advanced == %{}, do: "", else: Jason.encode!(Defs.encode(advanced), pretty: true))
    }
  end

  @doc """
  A monster type from the form: `{:ok, id, kind}` or `{:error, [message]}`. `old` is the type being
  edited (its id can't change here; Save as new makes a copy).
  """
  def from_form(p, old \\ nil) do
    id = (old && old.id) || slug(p["id"] |> blank_or(p["name"]))

    {advanced, adv_err} =
      case String.trim(p["advanced"] || "") do
        "" ->
          {%{}, []}

        json ->
          case Jason.decode(json) do
            {:ok, %{} = m} -> {Defs.decode(m), []}
            _ -> {%{}, ["Advanced isn't valid JSON (an object: {\"breath\": ...})."]}
          end
      end

    {weapons, e1} = weighted(p["weapons"], "Weapons")
    {offhand, e2} = weighted(p["offhand"], "Off hand")
    {moves, e3} = weighted(p["moves"], "Moves")
    {loot, e4} = loot_lines(p["loot"])
    {drops, e5} = drop_lines(p["drops"])

    k =
      %{
        name: String.slice(String.trim(p["name"] || ""), 0, 60),
        model: if(p["model"] in @models, do: p["model"], else: "skeleton"),
        rank: if(p["rank"] in Spawns.ranks(), do: p["rank"], else: "normal"),
        levels: Loot.parse_range(p["levels"] || "") || 1..1,
        hp: {int(p["hp_base"], 20) |> max(1), int(p["hp_per"], 0) |> max(0)},
        dmg: dmg(p["dmg"]),
        dly_ms: int(p["dly_ms"], 2000) |> max(300) |> min(10_000),
        walk: float(p["walk"], 1.2) |> max(0.0) |> min(20.0),
        run: float(p["run"], 3.6) |> max(0.0) |> min(30.0),
        aggro: float(p["aggro"], 10.0) |> max(0.0) |> min(200.0),
        reach: float(p["reach"], 1.0) |> max(0.3) |> min(40.0),
        coins: Loot.parse_range(p["coins"] || "") || 0..0,
        weapon_drop: (float(p["weapon_drop"], 0.0) / 100) |> max(0.0) |> min(1.0),
        weapons: if(weapons == [], do: [{nil, 1}], else: weapons),
        offhand: if(offhand == [], do: [{nil, 1}], else: offhand),
        loot: loot,
        xp_mult: float(p["xp_mult"], 1.0) |> max(0.0) |> min(50.0)
      }
      |> put_opt(:family, blank_or(p["family"], nil))
      |> put_opt(:leash, opt_float(p["leash"]))
      |> put_opt(:radius, opt_float(p["radius"]))
      |> put_opt(:scale, opt_float(p["scale"]))
      |> put_opt(:roam, opt_float(p["roam"]))
      |> put_opt(:respawn_ms, respawn_range(p["respawn_s"]))
      |> put_opt(:drops, if(drops == [], do: nil, else: drops))
      |> put_opt(:moves, if(moves == [], do: nil, else: moves))
      |> put_opt(:loot_tables, case String.split(p["loot_tables"] || "", ~r/[\s,]+/, trim: true) do
        [] -> nil
        l -> l
      end)
      |> put_opt(:boss, p["boss"] in ["true", "on", true] || nil)
      |> put_opt(:ranged, p["ranged"] in ["true", "on", true] || nil)
      |> put_opt(:aquatic, p["aquatic"] in ["true", "on", true] || nil)

    k = Map.merge(advanced, k)
    errors = adv_err ++ e1 ++ e2 ++ e3 ++ e4 ++ e5 ++ validate(id, k)
    if errors == [], do: {:ok, id, k}, else: {:error, errors}
  end

  @doc "What's wrong with a monster type (messages)."
  def validate(id, k) do
    items = for({i, _} <- k.weapons ++ k.offhand, i != nil, do: i) ++ Enum.map(k.loot, &elem(&1, 0)) ++ Enum.map(k[:drops] || [], &elem(&1, 0))
    tables = Defs.map(Loot.kind())

    [
      id in [nil, ""] && "Give it an id (letters, digits and underscores).",
      k.name == "" && "Give it a name (\"a goblin shaman\", \"Grubnak the Cruel\").",
      k.levels.first < 1 && "Levels start at 1.",
      k.levels.last > 60 && "Levels go up to 60."
    ]
    |> Kernel.++(for i <- Enum.uniq(items), Items.get(i) == nil, do: "There is no item \"#{i}\".")
    |> Kernel.++(for t <- k[:loot_tables] || [], not Map.has_key?(tables, t), do: "There is no loot table \"#{t}\".")
    |> Kernel.++(if k[:specials] && is_nil(k[:special_every_ms]), do: ["Specials need special_every_ms (Advanced)."], else: [])
    |> Enum.filter(&is_binary/1)
  end

  # ---------------------------------------------------------------- previews

  @doc """
  What a monster type is at `level` (World tuning applied), and what it's worth to a player of
  `player_level`: `%{hp, dmg_lo, dmg_hi, dps, hit_pct, con, xp, coins_lo, coins_hi}`.
  """
  def preview(k, level, player_level) do
    {base, per} = k[:hp] || {1, 0}
    {lo, hi} = k[:dmg] || {1, 1}
    dm = num(Tuning.get("mob_damage_mult"))
    hp = max(1, round((base + per * level) * num(Tuning.get("mob_hp_mult"))))
    dlo = max(1, round((lo + level - 1) * dm))
    dhi = max(1, round((hi + 2 * (level - 1)) * dm))
    hit = Melee.hit_chance(level, player_level)
    dps = (dlo + dhi) / 2 * hit / ((k[:dly_ms] || 2000) / 1000)
    rank_mult = Spawns.rank_xp_mult(Spawns.rank(k)) * num(k[:xp_mult] || 1.0)
    coins = k[:coins] || 0..0

    %{
      hp: hp,
      dmg_lo: dlo,
      dmg_hi: dhi,
      hit_pct: round(hit * 100),
      dps: Float.round(dps, 1),
      con: Progression.con(level, player_level),
      xp: Progression.kill_xp(level, player_level, rank_mult),
      coins_lo: coins.first * level,
      coins_hi: coins.last * level
    }
  end

  @doc "A thousand (or `n`) corpses of a type at `level`: `BaconWorld.Loot.simulate/2`'s summary."
  def simulate_loot(k, level, n \\ 1000) do
    mob = %{weapon: nil, offhand: nil, level: level, loot_tables: [], elite: false}

    Loot.simulate(
      fn ->
        weapon = Spawns.weighted(k.weapons)
        off = if weapon && Items.two_handed?(Items.get(weapon)), do: nil, else: Spawns.weighted(k.offhand)
        {items, coins} = BaconWorld.Mobs.Brain.roll_loot_and_coins(%{mob | weapon: weapon, offhand: off}, k)
        %{items: items, coins: round(Enum.random(k.coins) * level * Loot.coin_mult()) + coins}
      end,
      n
    )
  end

  @doc "The experience curve, level by level: `[%{level, to_next, kill_xp, kills, total}]` (an even-con kill of a normal creature)."
  def xp_table do
    {rows, _} =
      Enum.map_reduce(1..(Progression.max_level() - 1), 0, fn l, total ->
        need = Progression.xp_to_next(l)
        xp = Progression.kill_xp(l, l)
        {%{level: l, to_next: need, kill_xp: xp, kills: if(xp > 0, do: Float.ceil(need / xp) |> round(), else: nil), total: total + need}, total + need}
      end)

    rows
  end

  # ---------------------------------------------------------------- examples

  @doc """
  The examples shipped in `priv/seed/bestiary_examples.json` (monster types and loot tables in the
  `BaconWorld.Defs` codec). `import_examples/0` adds the ones not there yet and never overwrites.
  """
  def examples do
    path = Path.join([Bacon8.Plugins.priv_dir("bacon_world"), "seed", "bestiary_examples.json"])

    case File.read(path) do
      {:ok, body} -> Jason.decode!(body)
      _ -> %{}
    end
  end

  @doc "Adds the example loot tables and monster types that aren't there yet. `{:ok, %{added: [ids]}}`."
  def import_examples do
    ex = examples()
    tables = Defs.map(Loot.kind())
    monsters = Defs.map("monster")

    added_tables = for %{"id" => id, "data" => d} <- ex["loot_tables"] || [], not Map.has_key?(tables, id), do: (Defs.put(Loot.kind(), id, Defs.decode(d)); id)
    added_monsters = for %{"id" => id, "data" => d} <- ex["monsters"] || [], not Map.has_key?(monsters, id), do: (Defs.put("monster", id, Defs.decode(d)); id)

    {:ok, %{added: added_tables ++ added_monsters}}
  end

  # ---------------------------------------------------------------- small things

  @doc "An id from a name: lowercase letters, digits and underscores."
  def slug(s), do: Loot.slug(s || "")

  defp weighted(text, label) do
    lines(text)
    |> Enum.reduce({[], []}, fn line, {ok, errs} ->
      case String.split(line, ~r/\s+/, trim: true) do
        [v] -> {ok ++ [{nil_if_none(v), 1}], errs}
        [v, w | _] -> case Integer.parse(w) do
          {n, _} when n > 0 -> {ok ++ [{nil_if_none(v), n}], errs}
          _ -> {ok, errs ++ ["#{label}: can't read \"#{line}\" (thing weight)."]}
        end
      end
    end)
  end

  defp loot_lines(text) do
    lines(text)
    |> Enum.reduce({[], []}, fn line, {ok, errs} ->
      case String.split(line, ~r/\s+/, trim: true) do
        [item, chance | rest] ->
          q = Loot.parse_range(List.first(rest) || "1") || 1..1
          {ok ++ [{item, pct(chance), q}], errs}

        _ ->
          {ok, errs ++ ["Loot: can't read \"#{line}\" (item chance% qty)."]}
      end
    end)
  end

  defp drop_lines(text) do
    lines(text)
    |> Enum.reduce({[], []}, fn line, {ok, errs} ->
      case String.split(line, ~r/\s+/, trim: true) do
        [item, chance | _] -> {ok ++ [{item, pct(chance)}], errs}
        _ -> {ok, errs ++ ["Drops: can't read \"#{line}\" (item chance%)."]}
      end
    end)
  end

  defp lines(text), do: (text || "") |> String.split(~r/\r?\n/) |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == "" or String.starts_with?(&1, "#")))

  defp nil_if_none(v) when v in ["none", "nothing", "-", "nil"], do: nil
  defp nil_if_none(v), do: v

  # "35%", "35" or "0.35" -> 0.35
  defp pct(v) do
    case Float.parse(String.trim_trailing(v, "%")) do
      {f, _} -> if(String.ends_with?(v, "%") or f > 1.0, do: f / 100, else: f) |> max(0.0) |> min(1.0)
      :error -> 0.0
    end
  end

  defp weighted_text(list), do: Enum.map_join(list, "\n", fn {v, w} -> "#{v || "none"} #{w}" end)

  defp dmg(text) do
    case Loot.parse_range(text || "") do
      %Range{first: a, last: b} -> {max(a, 0), max(b, 1)}
      nil -> {1, 4}
    end
  end

  defp respawn_range(v) do
    case Loot.parse_range(to_string(v || "")) do
      %Range{first: a, last: b} when a >= 5 -> (a * 1000)..(b * 1000)
      _ -> nil
    end
  end

  defp respawn_text(%Range{first: a, last: b}), do: if(a == b, do: "#{div(a, 1000)}", else: "#{div(a, 1000)}-#{div(b, 1000)}")
  defp respawn_text(_), do: ""

  defp put_opt(m, _k, nil), do: m
  defp put_opt(m, k, v), do: Map.put(m, k, v)

  defp blank_or(v, fallback) do
    case String.trim(to_string(v || "")) do
      "" -> fallback
      s -> s
    end
  end

  defp opt_float(v) do
    case Float.parse(to_string(v || "")) do
      {f, _} when f >= 0 -> f
      _ -> nil
    end
  end

  defp float(v, d) do
    case Float.parse(to_string(v || "")) do
      {f, _} -> f
      :error -> d
    end
  end

  defp int(v, d) do
    case Integer.parse(to_string(v || "")) do
      {n, _} -> n
      :error -> d
    end
  end

  defp num(n) when is_number(n), do: n * 1.0
  defp num(_), do: 1.0

  defp fmt(f) when is_float(f), do: :erlang.float_to_binary(f, [:compact, decimals: 3])
  defp fmt(v), do: to_string(v)
end

defmodule BaconWorld.Loot do
  @moduledoc """
  Loot tables (2026-11-03): what creatures and cleared camps drop beyond the weapon in a
  creature's hand and its kind's own `loot` and `drops` lists (`BaconWorld.Mobs.Brain.roll_loot/2`,
  which still rolls those first, exactly as before).

  Tables are rows of `bacon_world_defs` kind `"loot_table"` (`BaconWorld.Defs`), edited on
  `/admin/bacon_world/bestiary?tab=loot`, and named by a monster type's `loot_tables`, a camp
  slot's `loot_tables` or a camp's clear reward. A table:

      %{
        name: "Goblin pockets",
        rolls: 1..2,            # picks from the weighted pool: an integer or a range
        empty: 40,              # the pool's weight for "nothing"
        pool: [%{item: "rusty_dagger", weight: 10, qty: 1..1, min_level: 1, max_level: 50}],
        always: [%{item: "goblin_ear", chance: 0.75, qty: 1..2}],   # each rolled on its own
        tables: [%{table: "gems_minor", chance: 0.05}],              # nested, at most 4 deep
        coins: 0..0             # extra copper (times the creature's level)
      }

  Every chance is scaled by `chance_mult/0` (World tuning's `loot_chance_mult` times any XP & loot
  event running, `BaconWorld.LiveEvents`) and capped at 1; the pool's empty weight is divided by
  it. Coins are scaled by `coin_mult/0`. An item that no longer exists is skipped.
  """

  require Logger

  alias BaconWorld.{Defs, Items, LiveEvents, Tuning}

  @kind "loot_table"
  @max_depth 4
  @max_rolls 20

  @doc "The Defs kind loot tables are stored under."
  def kind, do: @kind

  @doc "Every table, `[{id, table}]` in order."
  def list, do: Defs.list(@kind)

  @doc "A table by id, or nil."
  def get(id) when is_binary(id), do: Map.get(Defs.map(@kind), id)
  def get(_), do: nil

  @doc "The chance multiplier in force: World tuning's `loot_chance_mult` times the events running."
  def chance_mult, do: num(Tuning.get("loot_chance_mult"), 1.0) * LiveEvents.mult(:loot)

  @doc "The coin multiplier in force: World tuning's `coin_mult` times the events running."
  def coin_mult, do: num(Tuning.get("coin_mult"), 1.0) * LiveEvents.mult(:coin)

  @doc """
  Rolls a table (an id or the table itself) for a creature of `level`.
  Returns `%{items: [%{item_id, quantity}], coins: integer}`.

  Options: `:chance_mult` (default `chance_mult/0`), `:coin_mult` (default `coin_mult/0`).
  """
  def roll(table, level, opts \\ []) do
    mult = Keyword.get_lazy(opts, :chance_mult, &chance_mult/0)
    cmult = Keyword.get_lazy(opts, :coin_mult, &coin_mult/0)
    do_roll(table, max(1, level || 1), mult, cmult, 0)
  end

  @doc "Rolls several tables and adds up what they give."
  def roll_many(ids, level, opts \\ []) when is_list(ids) do
    Enum.reduce(ids, %{items: [], coins: 0}, fn id, acc ->
      r = roll(id, level, opts)
      %{items: acc.items ++ r.items, coins: acc.coins + r.coins}
    end)
  end

  defp do_roll(_table, _level, _mult, _cmult, depth) when depth > @max_depth, do: %{items: [], coins: 0}

  defp do_roll(id, level, mult, cmult, depth) when is_binary(id) do
    case get(id) do
      nil ->
        Logger.debug("bacon_world:loot no table #{inspect(id)}")
        %{items: [], coins: 0}

      t ->
        do_roll(t, level, mult, cmult, depth)
    end
  end

  defp do_roll(%{} = t, level, mult, cmult, depth) do
    always =
      for e <- Map.get(t, :always, []), item_ok?(e), :rand.uniform() < min(1.0, num(e[:chance], 1.0) * mult) do
        %{item_id: e.item, quantity: qty(e[:qty])}
      end

    pool = Enum.filter(Map.get(t, :pool, []), &(item_ok?(&1) and level_ok?(&1, level)))
    empty = max(0.0, num(t[:empty], 0.0)) / max(mult, 0.01)

    picks =
      if pool == [] do
        []
      else
        weighted = [{nil, empty} | Enum.map(pool, &{&1, max(0.0, num(&1[:weight], 1.0))})]

        for _ <- 1..rolls(t[:rolls])//1, e <- [pick(weighted)], e != nil do
          %{item_id: e.item, quantity: qty(e[:qty])}
        end
      end

    nested =
      for n <- Map.get(t, :tables, []), is_binary(n[:table]), :rand.uniform() < min(1.0, num(n[:chance], 1.0) * mult) do
        do_roll(n.table, level, mult, cmult, depth + 1)
      end

    coins =
      case t[:coins] do
        %Range{} = r -> if Range.size(r) > 0 and r.last > 0, do: round(Enum.random(r) * level * cmult), else: 0
        n when is_integer(n) and n > 0 -> round(n * level * cmult)
        _ -> 0
      end

    %{items: always ++ picks ++ Enum.flat_map(nested, & &1.items), coins: coins + Enum.sum(Enum.map(nested, & &1.coins))}
  end

  defp do_roll(_other, _level, _mult, _cmult, _depth), do: %{items: [], coins: 0}

  defp rolls(%Range{} = r), do: r |> Enum.random() |> max(0) |> min(@max_rolls)
  defp rolls(n) when is_integer(n), do: n |> max(0) |> min(@max_rolls)
  defp rolls(_), do: 1

  defp qty(%Range{} = r), do: max(1, Enum.random(r))
  defp qty(n) when is_integer(n) and n > 0, do: n
  defp qty(_), do: 1

  defp item_ok?(%{item: id}) when is_binary(id), do: Items.get(id) != nil
  defp item_ok?(_), do: false

  defp level_ok?(e, level), do: level >= (e[:min_level] || 1) and level <= (e[:max_level] || 1_000)

  # `[{value, weight}]`; nothing at all when every weight is 0
  defp pick(weighted) do
    total = weighted |> Enum.map(&elem(&1, 1)) |> Enum.sum()

    if total <= 0 do
      nil
    else
      at = :rand.uniform() * total

      Enum.reduce_while(weighted, 0.0, fn {v, w}, acc ->
        if at < acc + w, do: {:halt, {:ok, v}}, else: {:cont, acc + w}
      end)
      |> case do
        {:ok, v} -> v
        _ -> weighted |> List.last() |> elem(0)
      end
    end
  end

  # ---------------------------------------------------------------- simulating

  @doc """
  Runs `fun` (returning `%{items: [...], coins: n}`) `n` times and adds up what came out, for the
  admin's simulator: `%{n, coins_avg, coins_min, coins_max, nothing_pct, rows}` where `rows` are
  `%{item_id, name, kills, quantity, pct, per_kill}` (pct: share of rolls that gave it at least once),
  most often first.
  """
  def simulate(fun, n) when is_function(fun, 0) and is_integer(n) and n > 0 do
    n = min(n, 100_000)

    {counts, qtys, coins, nothing} =
      Enum.reduce(1..n, {%{}, %{}, [], 0}, fn _, {counts, qtys, coins, nothing} ->
        %{items: items, coins: c} = fun.()
        ids = items |> Enum.map(& &1.item_id) |> Enum.uniq()
        counts = Enum.reduce(ids, counts, &Map.update(&2, &1, 1, fn x -> x + 1 end))
        qtys = Enum.reduce(items, qtys, fn i, acc -> Map.update(acc, i.item_id, i.quantity, &(&1 + i.quantity)) end)
        {counts, qtys, [c | coins], if(items == [], do: nothing + 1, else: nothing)}
      end)

    rows =
      counts
      |> Enum.map(fn {id, k} ->
        %{item_id: id, name: (Items.get(id) || %{name: id}).name, kills: k, quantity: qtys[id], pct: Float.round(k * 100 / n, 2), per_kill: Float.round(qtys[id] / n, 3)}
      end)
      |> Enum.sort_by(&{-&1.kills, &1.item_id})

    %{
      n: n,
      coins_avg: Float.round(Enum.sum(coins) / n, 1),
      coins_min: Enum.min(coins),
      coins_max: Enum.max(coins),
      nothing_pct: Float.round(nothing * 100 / n, 2),
      rows: rows
    }
  end

  # ---------------------------------------------------------------- editing

  @doc """
  A table from the admin form's text fields (all optional):

    * `"name"`, `"rolls"` (`"1"` or `"1-3"`), `"empty"` (a weight), `"coins"` (`"5-20"`)
    * `"pool"`: one entry a line, `item weight [qty] [min_level-max_level]`, e.g. `rusty_dagger 10 1 1-8`
    * `"always"`: one a line, `item chance [qty]`, e.g. `goblin_ear 0.75 1-2` (`75%` works too)
    * `"tables"`: one a line, `table chance`

  Returns `{:ok, table}` or `{:error, [message]}` (unknown items or tables, bad numbers).
  """
  def from_form(p) when is_map(p) do
    errors = []

    {pool, e1} = lines(p["pool"], &pool_line/1)
    {always, e2} = lines(p["always"], &always_line/1)
    {tables, e3} = lines(p["tables"], &table_line/1)

    t = %{
      name: p |> Map.get("name", "") |> to_string() |> String.trim() |> String.slice(0, 80),
      rolls: range_or_int(p["rolls"], 1),
      empty: max(0, int(p["empty"], 0)),
      pool: pool,
      always: always,
      tables: tables,
      coins: range_or_int(p["coins"], 0)
    }

    errors = errors ++ e1 ++ e2 ++ e3 ++ check_items(t)
    if errors == [], do: {:ok, t}, else: {:error, errors}
  end

  @doc "A table as the admin form's text fields (`from_form/1`'s inverse)."
  def to_form(nil), do: %{"name" => "", "rolls" => "1", "empty" => "0", "coins" => "0", "pool" => "", "always" => "", "tables" => ""}

  def to_form(t) do
    %{
      "name" => t[:name] || "",
      "rolls" => range_text(t[:rolls] || 1),
      "empty" => to_string(t[:empty] || 0),
      "coins" => range_text(t[:coins] || 0),
      "pool" =>
        Enum.map_join(t[:pool] || [], "\n", fn e ->
          lv = if e[:min_level] || e[:max_level], do: " #{e[:min_level] || 1}-#{e[:max_level] || 50}", else: ""
          "#{e.item} #{fmt(e[:weight] || 1)} #{range_text(e[:qty] || 1)}#{lv}"
        end),
      "always" => Enum.map_join(t[:always] || [], "\n", &"#{&1.item} #{fmt(&1[:chance] || 1.0)} #{range_text(&1[:qty] || 1)}"),
      "tables" => Enum.map_join(t[:tables] || [], "\n", &"#{&1.table} #{fmt(&1[:chance] || 1.0)}")
    }
  end

  @doc "The items and tables a table names that don't exist (messages)."
  def check_items(t) do
    items = Enum.map(t[:pool] || [], & &1.item) ++ Enum.map(t[:always] || [], & &1.item)
    bad_items = for id <- Enum.uniq(items), Items.get(id) == nil, do: "There is no item \"#{id}\"."
    known = Defs.map(@kind)
    bad_tables = for n <- t[:tables] || [], not Map.has_key?(known, n.table), do: "There is no loot table \"#{n.table}\"."
    bad_items ++ bad_tables
  end

  @doc "An id for a new table from its name: lowercase letters, digits and underscores."
  def slug(name) do
    name |> to_string() |> String.downcase() |> String.replace(~r/[^a-z0-9]+/, "_") |> String.trim("_") |> String.slice(0, 48)
  end

  defp lines(nil, _fun), do: {[], []}

  defp lines(text, fun) do
    text
    |> to_string()
    |> String.split(~r/\r?\n/)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == "" or String.starts_with?(&1, "#")))
    |> Enum.reduce({[], []}, fn line, {ok, errs} ->
      case fun.(String.split(line, ~r/[\s,]+/, trim: true)) do
        {:ok, e} -> {ok ++ [e], errs}
        :error -> {ok, errs ++ ["Can't read \"#{line}\"."]}
      end
    end)
  end

  defp pool_line([item | rest]) do
    {weight, rest} = take_num(rest, 1.0)
    {q, rest} = take_range(rest, 1..1)
    lv = List.first(rest)

    e = %{item: item, weight: weight, qty: q}

    case lv && parse_range(lv) do
      nil -> {:ok, e}
      %Range{first: a, last: b} -> {:ok, Map.merge(e, %{min_level: a, max_level: b})}
      _ -> :error
    end
  end

  defp pool_line(_), do: :error

  defp always_line([item | rest]) do
    {chance, rest} = take_chance(rest)
    {q, _} = take_range(rest, 1..1)
    {:ok, %{item: item, chance: chance, qty: q}}
  end

  defp always_line(_), do: :error

  defp table_line([table | rest]) do
    {chance, _} = take_chance(rest)
    {:ok, %{table: table, chance: chance}}
  end

  defp table_line(_), do: :error

  defp take_num([v | rest], default) do
    case Float.parse(v) do
      {f, ""} -> {f, rest}
      _ -> {default, [v | rest]}
    end
  end

  defp take_num([], default), do: {default, []}

  defp take_chance([v | rest]) do
    case Float.parse(String.trim_trailing(v, "%")) do
      {f, _} -> {if(String.ends_with?(v, "%") or f > 1.0, do: f / 100, else: f) |> max(0.0) |> min(1.0), rest}
      :error -> {1.0, [v | rest]}
    end
  end

  defp take_chance([]), do: {1.0, []}

  defp take_range([v | rest], default) do
    case parse_range(v) do
      nil -> {default, [v | rest]}
      r -> {r, rest}
    end
  end

  defp take_range([], default), do: {default, []}

  @doc false
  def parse_range(v) when is_binary(v) do
    case String.split(String.trim(v), "-", parts: 2) do
      [a] -> with({n, ""} <- Integer.parse(a), do: n..n, else: (_ -> nil))
      [a, b] -> with({x, ""} <- Integer.parse(a), {y, ""} <- Integer.parse(b), do: min(x, y)..max(x, y), else: (_ -> nil))
    end
  end

  def parse_range(_), do: nil

  defp range_or_int(v, default) do
    case parse_range(to_string(v || "")) do
      %Range{first: a, last: a} -> a
      %Range{} = r -> r
      nil -> default
    end
  end

  @doc false
  def range_text(%Range{first: a, last: a}), do: to_string(a)
  def range_text(%Range{first: a, last: b}), do: "#{a}-#{b}"
  def range_text(n) when is_integer(n), do: to_string(n)
  def range_text(_), do: ""

  defp fmt(f) when is_float(f), do: :erlang.float_to_binary(f, [:compact, decimals: 4])
  defp fmt(v), do: to_string(v)

  defp int(v, default) do
    case Integer.parse(to_string(v || "")) do
      {n, _} -> n
      :error -> default
    end
  end

  defp num(v, _default) when is_float(v), do: v
  defp num(v, _default) when is_integer(v), do: v * 1.0
  defp num(_, default), do: default
end

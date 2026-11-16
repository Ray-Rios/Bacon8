defmodule Bacon8.GameContent.Loot do
  @moduledoc """
  Rolls a game's loot tables (2026-11-15): Bacon World's roller (`BaconWorld.Loot`, 2026-11-03) for
  every game, over the tables as they are stored (`Bacon8.GameContent`, kind `"loot_table"`).
  A table's `data`:

      {
        "name": "Pack scraps",
        "rolls": [1, 2],          picks from the weighted pool: a number, or [least, most]
        "empty": 40,              the pool's weight for "nothing"
        "pool": [{"item": "scrap_metal", "weight": 10, "qty": [1, 3], "min_level": 1, "max_level": 50}],
        "always": [{"item": "wolf_pelt", "chance": 0.75, "qty": 1}],     each rolled on its own
        "tables": [{"table": "ammo_small", "chance": 0.2}],              other tables, 4 deep at most
        "coins": [0, 3]           copper, times the level
      }

  `roll/4` gives `%{items: [%{item_id, quantity}], coins: n}`. Options:

    * `:chance_mult` (1.0) - every chance is multiplied by it (capped at 1) and the pool's empty
      weight divided by it: a loot event, a boss
    * `:coin_mult` (1.0)
    * `:item_ok` - `fn item_id -> boolean`: an item that no longer exists is skipped. The default
      keeps an item when the game has no `"item"` definitions at all, or has that one.

  Who may ask for a roll is the caller's business: the API gives it to game servers (the server
  key) and to staff trying a table, never to a player's own client.
  """

  alias Bacon8.GameContent

  @kind "loot_table"
  @max_depth 4
  @max_rolls 20

  def kind, do: @kind

  @doc "Rolls a table (its id, or the table's data) for something of `level`."
  def roll(game_slug, table, level, opts \\ []) do
    ctx = %{
      game: game_slug,
      level: max(1, to_int(level, 1)),
      mult: max(0.01, num(opts[:chance_mult], 1.0)),
      cmult: max(0.0, num(opts[:coin_mult], 1.0)),
      ok: opts[:item_ok] || default_item_ok(game_slug)
    }

    do_roll(table, ctx, 0)
  end

  @doc "Rolls a table `times` times (10,000 at most) and adds it up: `%{kills, items: [%{item_id, quantity, kills}], coins, empty}`."
  def simulate(game_slug, table, level, times, opts \\ []) do
    times = times |> to_int(1000) |> max(1) |> min(10_000)

    {items, coins, empty} =
      Enum.reduce(1..times, {%{}, 0, 0}, fn _, {items, coins, empty} ->
        r = roll(game_slug, table, level, opts)

        items =
          r.items
          |> Enum.group_by(& &1.item_id, & &1.quantity)
          |> Enum.reduce(items, fn {id, qs}, acc -> Map.update(acc, id, {Enum.sum(qs), 1}, fn {q, k} -> {q + Enum.sum(qs), k + 1} end) end)

        {items, coins + r.coins, if(r.items == [], do: empty + 1, else: empty)}
      end)

    %{
      kills: times,
      coins: coins,
      empty: empty,
      items: items |> Enum.map(fn {id, {q, k}} -> %{item_id: id, quantity: q, kills: k} end) |> Enum.sort_by(&(-&1.kills))
    }
  end

  defp default_item_ok(game_slug) do
    items = GameContent.map(game_slug, "item")
    if map_size(items) == 0, do: fn _ -> true end, else: &Map.has_key?(items, &1)
  end

  defp do_roll(_table, _ctx, depth) when depth > @max_depth, do: %{items: [], coins: 0}

  defp do_roll(id, ctx, depth) when is_binary(id) do
    case GameContent.get(ctx.game, @kind, id) do
      nil -> %{items: [], coins: 0}
      t -> do_roll(t, ctx, depth)
    end
  end

  defp do_roll(%{} = t, ctx, depth) do
    always =
      for e <- list(t["always"]), item_ok?(e, ctx), :rand.uniform() < min(1.0, num(e["chance"], 1.0) * ctx.mult) do
        %{item_id: e["item"], quantity: qty(e["qty"])}
      end

    pool = Enum.filter(list(t["pool"]), &(item_ok?(&1, ctx) and level_ok?(&1, ctx.level)))
    empty = max(0.0, num(t["empty"], 0.0)) / ctx.mult

    picks =
      if pool == [] do
        []
      else
        weighted = [{nil, empty} | Enum.map(pool, &{&1, max(0.0, num(&1["weight"], 1.0))})]

        for _ <- 1..rolls(t["rolls"])//1, e <- [pick(weighted)], e != nil do
          %{item_id: e["item"], quantity: qty(e["qty"])}
        end
      end

    nested =
      for n <- list(t["tables"]), is_binary(n["table"]), :rand.uniform() < min(1.0, num(n["chance"], 1.0) * ctx.mult) do
        do_roll(n["table"], ctx, depth + 1)
      end

    coins =
      case span(t["coins"]) do
        {_, hi} = s when hi > 0 -> round(between(s) * ctx.level * ctx.cmult)
        _ -> 0
      end

    %{items: always ++ picks ++ Enum.flat_map(nested, & &1.items), coins: coins + Enum.sum(Enum.map(nested, & &1.coins))}
  end

  defp do_roll(_other, _ctx, _depth), do: %{items: [], coins: 0}

  defp rolls(nil), do: 1
  defp rolls(v), do: v |> span() |> between() |> max(0) |> min(@max_rolls)

  defp qty(nil), do: 1
  defp qty(v), do: v |> span() |> between() |> max(1)

  # a number or [least, most] as {least, most}
  defp span([a, b]) when is_number(a) and is_number(b), do: {round(min(a, b)), round(max(a, b))}
  defp span(n) when is_number(n), do: {round(n), round(n)}
  defp span(_), do: {0, 0}

  defp between({a, a}), do: a
  defp between({a, b}), do: a + :rand.uniform(b - a + 1) - 1

  defp item_ok?(%{"item" => id}, ctx) when is_binary(id), do: ctx.ok.(id)
  defp item_ok?(_, _), do: false

  defp level_ok?(e, level), do: level >= to_int(e["min_level"], 1) and level <= to_int(e["max_level"], 1_000)

  # `[{value, weight}]`; nothing at all when every weight is 0
  defp pick(weighted) do
    total = weighted |> Enum.map(&elem(&1, 1)) |> Enum.sum()

    if total <= 0 do
      nil
    else
      at = :rand.uniform() * total

      weighted
      |> Enum.reduce_while(0.0, fn {v, w}, acc -> if at < acc + w, do: {:halt, {:ok, v}}, else: {:cont, acc + w} end)
      |> case do
        {:ok, v} -> v
        _ -> weighted |> List.last() |> elem(0)
      end
    end
  end

  defp list(l) when is_list(l), do: Enum.filter(l, &is_map/1)
  defp list(_), do: []

  defp num(n, _) when is_number(n), do: n * 1.0
  defp num(_, d), do: d

  defp to_int(n, _) when is_integer(n), do: n
  defp to_int(n, _) when is_float(n), do: round(n)
  defp to_int(s, d) when is_binary(s), do: (case Integer.parse(s) do {n, _} -> n; :error -> d end)
  defp to_int(_, d), do: d
end

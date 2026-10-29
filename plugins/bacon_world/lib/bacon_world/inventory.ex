defmodule BaconWorld.Inventory do
  @moduledoc """
  What a character carries, EverQuest style: the hands, `"main"` (right) and `"off"`
  (left); what it wears, `"head"` (2026-10-29), `"under_top"`, `"under_bottom"`, `"chest"`, `"legs"` and
  `"feet"`; and 24 bag slots `"bag0"`..`"bag23"`. One `bacon_world_items` row per
  occupied slot; coins are `stats["coins"]` (copper: 10 copper make a silver, 10 silver
  a gold, 10 gold a platinum).

  Moving an item onto an occupied slot swaps the two; the same stackable item
  merges instead. Equipping follows the item's `slots` and `hands`
  (`BaconWorld.Items`): a two-handed weapon needs the off hand empty, and nothing
  goes in the off hand while one is held.

  The character's LiveView is the only writer (one login per account), so the
  read-then-write here doesn't race with itself.
  """

  import Ecto.Query, only: [from: 2]

  alias Bacon8.GamesRepo
  alias BaconWorld.{InventoryItem, Items, World}

  @bag_slots 24
  @hands ~w(main off)
  @equipment ~w(main off head under_top under_bottom chest legs feet)
  @starter_purse 100

  def bag_slots, do: @bag_slots
  def equipment_slots, do: @equipment

  @doc "Every slot name, equipment first."
  def slots, do: @equipment ++ Enum.map(0..(@bag_slots - 1), &"bag#{&1}")

  defp bag?(slot), do: is_binary(slot) and String.starts_with?(slot, "bag") and slot in slots()
  defp valid_slot?(slot), do: slot in slots()

  @doc "The character's items: `[%{slot, item_id, quantity}]`."
  def list(character_id) do
    from(i in InventoryItem, where: i.character_id == ^character_id, select: %{slot: i.slot, item_id: i.item_id, quantity: i.quantity})
    |> GamesRepo.all()
    |> Enum.filter(&Items.get(&1.item_id))
    |> Enum.sort_by(&slot_order/1)
  end

  defp slot_order(%{slot: "bag" <> n}), do: String.to_integer(n)
  defp slot_order(%{slot: slot}) do
    case Enum.find_index(@equipment, &(&1 == slot)) do
      nil -> 1000
      i -> i - length(@equipment)
    end
  end

  @doc "The catalogue items equipped, by slot (`\"main\"`, `\"off\"`, `\"chest\"`, ...; nil when empty)."
  def equipment(character_id) do
    rows = from(i in InventoryItem, where: i.character_id == ^character_id and i.slot in ^@equipment) |> GamesRepo.all()
    Map.new(@equipment, fn slot -> {slot, Enum.find_value(rows, &(&1.slot == slot && Items.get(&1.item_id)))} end)
  end

  @doc "Item ids equipped, for other players to draw: `%{\"main\" => id | nil, \"chest\" => id | nil, ...}`."
  def gear_ids(equipment), do: Map.new(equipment, fn {slot, item} -> {slot, item && item.id} end)

  @doc "What the inventory window shows."
  def payload(character_id) do
    %{items: list(character_id), coins: coins(character_id), bag_slots: @bag_slots}
  end

  @doc "Copper coins carried."
  def coins(character_id) do
    case World.fetch_character(character_id) do
      {:ok, c} -> World.stat(c, "coins")
      _ -> 0
    end
  end

  @doc "Adds (or with a negative amount, takes) copper. Returns the new total."
  def add_coins(character_id, amount) when is_integer(amount) do
    total = max(0, coins(character_id) + amount)
    World.merge_stats(World.by_id_query(character_id), %{"coins" => total})
    total
  end

  @doc "How many bag slots are empty."
  def free_bag_slots(character_id) do
    used = from(i in InventoryItem, where: i.character_id == ^character_id and like(i.slot, "bag%"), select: count(i.id)) |> GamesRepo.one()
    @bag_slots - used
  end

  @doc """
  True when `quantity` of `item_id` fits: into a stack of the same item with room,
  or an empty bag slot.
  """
  def fits?(character_id, item_id, quantity \\ 1) do
    case Items.get(item_id) do
      nil -> false
      item -> stack_room(character_id, item) >= quantity or free_bag_slots(character_id) > 0
    end
  end

  defp stack_room(_character_id, %{stack: 1}), do: 0

  defp stack_room(character_id, item) do
    from(i in InventoryItem, where: i.character_id == ^character_id and i.item_id == ^item.id and like(i.slot, "bag%"), select: i.quantity)
    |> GamesRepo.all()
    |> Enum.map(&max(0, item.stack - &1))
    |> Enum.sum()
  end

  @doc """
  Puts items in the bags: onto stacks of the same item first, then the first empty
  slots. `{:ok, slots_used}`, or `{:error, :inventory_full}` (nothing is added
  then) or `{:error, :unknown_item}`.
  """
  def add(character_id, item_id, quantity \\ 1) when is_integer(quantity) and quantity > 0 do
    case Items.get(item_id) do
      nil ->
        {:error, :unknown_item}

      item ->
        GamesRepo.transaction(fn ->
          rows = from(i in InventoryItem, where: i.character_id == ^character_id) |> GamesRepo.all()
          {left, used} = fill_stacks(rows, item, quantity)
          free = free_bags(rows)
          needed = div(left + item.stack - 1, item.stack)

          if needed > length(free) do
            GamesRepo.rollback(:inventory_full)
          else
            {_, more} =
              free
              |> Enum.take(needed)
              |> Enum.reduce({left, []}, fn slot, {remaining, acc} ->
                n = min(remaining, item.stack)
                GamesRepo.insert!(%InventoryItem{character_id: character_id, item_id: item.id, slot: slot, quantity: n})
                {remaining - n, [slot | acc]}
              end)

            used ++ Enum.reverse(more)
          end
        end)
    end
  end

  defp fill_stacks(_rows, %{stack: 1}, quantity), do: {quantity, []}

  defp fill_stacks(rows, item, quantity) do
    rows
    |> Enum.filter(&(&1.item_id == item.id and bag?(&1.slot) and &1.quantity < item.stack))
    |> Enum.sort_by(&slot_order/1)
    |> Enum.reduce({quantity, []}, fn row, {left, used} ->
      if left == 0 do
        {0, used}
      else
        n = min(left, item.stack - row.quantity)
        row |> Ecto.Changeset.change(quantity: row.quantity + n) |> GamesRepo.update!()
        {left - n, used ++ [row.slot]}
      end
    end)
  end

  defp free_bags(rows) do
    taken = MapSet.new(rows, & &1.slot)
    Enum.reject(Enum.map(0..(@bag_slots - 1), &"bag#{&1}"), &MapSet.member?(taken, &1))
  end

  @doc """
  Moves what is in `from` to `to`, swapping with what is there (or merging a stack).
  Errors: `:empty_slot`, `:invalid_slot`, `:cannot_equip_there`,
  `:off_hand_full` (equipping a two-hander), `:two_hander_equipped` (filling the
  off hand while holding one).
  """
  def move(character_id, from, to) when is_binary(from) and is_binary(to) do
    cond do
      not valid_slot?(from) or not valid_slot?(to) ->
        {:error, :invalid_slot}

      from == to ->
        {:ok, list(character_id)}

      true ->
        GamesRepo.transaction(fn ->
          rows = from(i in InventoryItem, where: i.character_id == ^character_id) |> GamesRepo.all()
          by_slot = Map.new(rows, &{&1.slot, &1})
          moving = by_slot[from] || GamesRepo.rollback(:empty_slot)
          there = by_slot[to]
          item = Items.get(moving.item_id) || GamesRepo.rollback(:empty_slot)

          with :ok <- check_fit(item, to, Map.delete(Map.delete(by_slot, from), to)),
               :ok <- if(there, do: check_fit(Items.get(there.item_id), from, Map.delete(Map.delete(by_slot, from), to) |> Map.put(to, moving)), else: :ok) do
            cond do
              there && there.item_id == moving.item_id && item.stack > 1 && bag?(to) ->
                total = there.quantity + moving.quantity
                keep = min(total, item.stack)
                there |> Ecto.Changeset.change(quantity: keep) |> GamesRepo.update!()

                if total - keep > 0,
                  do: moving |> Ecto.Changeset.change(quantity: total - keep) |> GamesRepo.update!(),
                  else: GamesRepo.delete!(moving)

              there ->
                # The (character_id, slot) index is unique: park one row while swapping.
                there |> Ecto.Changeset.change(slot: "swap") |> GamesRepo.update!()
                moving |> Ecto.Changeset.change(slot: to) |> GamesRepo.update!()
                GamesRepo.update_all(from(i in InventoryItem, where: i.id == ^there.id), set: [slot: from])

              true ->
                moving |> Ecto.Changeset.change(slot: to) |> GamesRepo.update!()
            end

            :ok
          else
            {:error, reason} -> GamesRepo.rollback(reason)
          end
        end)
        |> case do
          {:ok, :ok} -> {:ok, list(character_id)}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  # May `item` sit in `slot`, given what else is equipped (`others`, by slot)?
  defp check_fit(_item, "bag" <> _, _others), do: :ok

  defp check_fit(item, slot, _others) when slot not in @hands do
    if Items.equippable?(item, slot), do: :ok, else: {:error, :cannot_equip_there}
  end

  defp check_fit(item, slot, others) do
    main = others["main"] && Items.get(others["main"].item_id)

    cond do
      not Items.equippable?(item, slot) -> {:error, :cannot_equip_there}
      slot == "main" and Items.two_handed?(item) and others["off"] -> {:error, :off_hand_full}
      slot == "off" and Items.two_handed?(main) -> {:error, :two_hander_equipped}
      true -> :ok
    end
  end

  @doc """
  Equips an item from a bag into its natural hand: an empty main hand, else an
  empty off hand it fits, else it swaps with the main hand (shields with the off
  hand). A two-hander first moves the off-hand item into the bag it came from.
  """
  def auto_equip(character_id, from) do
    rows = list(character_id)
    by_slot = Map.new(rows, &{&1.slot, &1})

    with %{item_id: id} <- by_slot[from] || {:error, :empty_slot},
         %{} = item <- Items.get(id) || {:error, :empty_slot} do
      main_free = is_nil(by_slot["main"])
      off_free = is_nil(by_slot["off"])

      cond do
        Items.wearable?(item) ->
          # worn things go to their own slot, swapping with what is there
          move(character_id, from, hd(item.slots))

        Items.equippable?(item, "main") and Items.two_handed?(item) ->
          with {:ok, _} <- if(off_free, do: {:ok, rows}, else: move(character_id, "off", first_free(rows) || from)) do
            move(character_id, from, "main")
          end

        Items.equippable?(item, "main") and main_free ->
          move(character_id, from, "main")

        Items.equippable?(item, "off") and off_free and not two_handed_main?(by_slot) ->
          move(character_id, from, "off")

        Items.equippable?(item, "main") ->
          move(character_id, from, "main")

        Items.equippable?(item, "off") ->
          if two_handed_main?(by_slot), do: {:error, :two_hander_equipped}, else: move(character_id, from, "off")

        true ->
          {:error, :cannot_equip_there}
      end
    end
  end

  defp two_handed_main?(by_slot), do: Items.two_handed?(by_slot["main"] && Items.get(by_slot["main"].item_id))

  defp first_free(rows) do
    taken = MapSet.new(rows, & &1.slot)
    Enum.find(Enum.map(0..(@bag_slots - 1), &"bag#{&1}"), &(not MapSet.member?(taken, &1)))
  end

  @doc "Unequips into the first free bag slot. `{:error, :inventory_full}` if there is none."
  def unequip(character_id, slot) when slot in @equipment do
    case first_free(list(character_id)) do
      nil -> {:error, :inventory_full}
      bag -> move(character_id, slot, bag)
    end
  end

  def unequip(_, _), do: {:error, :invalid_slot}

  @doc """
  Takes what is in a bag slot out of the inventory (selling it): `{:ok, %{item_id,
  quantity}}`, or `{:error, :empty_slot}` / `{:error, :invalid_slot}` (only bag slots).
  """
  def remove(character_id, "bag" <> _ = slot) do
    case GamesRepo.one(from(i in InventoryItem, where: i.character_id == ^character_id and i.slot == ^slot)) do
      nil ->
        {:error, :empty_slot}

      row ->
        GamesRepo.delete!(row)
        {:ok, %{item_id: row.item_id, quantity: row.quantity}}
    end
  end

  def remove(_character_id, _slot), do: {:error, :invalid_slot}

  @doc "Destroys what is in a slot (EverQuest's Destroy)."
  def destroy(character_id, slot) do
    {n, _} = from(i in InventoryItem, where: i.character_id == ^character_id and i.slot == ^slot) |> GamesRepo.delete_all()
    if n > 0, do: {:ok, list(character_id)}, else: {:error, :empty_slot}
  end

  @doc """
  Gives a character the starter kit once (flag `stats["starter_kit"]`): a short
  sword in hand and one of each basic weapon in the bags, to try every stance.
  """
  def grant_starter_kit(character_id) do
    with {:ok, c} <- World.fetch_character(character_id),
         false <- World.stat(c, "starter_kit") do
      World.merge_stats(World.by_id_query(c.id), %{"starter_kit" => true})

      for {item_id, slot} <- Items.starter_kit() do
        case slot do
          nil -> add(c.id, item_id)
          slot -> place(c.id, item_id, slot)
        end
      end

      :granted
    else
      _ -> :already
    end
  end

  @doc """
  Dresses a character in the starter underwear once (flag `stats["starter_wear"]`), and
  gives it a starting purse once (`stats["starter_purse"]`, #{@starter_purse} copper).
  Characters made before clothes were items get both at their next login.
  """
  def grant_starter_wear(character_id) do
    with {:ok, c} <- World.fetch_character(character_id) do
      unless World.stat(c, "starter_wear") do
        World.merge_stats(World.by_id_query(c.id), %{"starter_wear" => true})
        for {item_id, slot} <- Items.starter_wear(), do: place(c.id, item_id, slot)
      end

      unless World.stat(c, "starter_purse") do
        World.merge_stats(World.by_id_query(c.id), %{"starter_purse" => true})
        add_coins(c.id, @starter_purse)
      end

      :ok
    end
  end

  @doc "What a character that hasn't logged in since clothes became items will be wearing."
  def starter_gear, do: Map.new(Items.starter_wear(), fn {id, slot} -> {slot, id} end)

  @doc "Equipped item ids for several characters at once: `%{character_id => gear}` (select screen)."
  def gear_for(character_ids) when is_list(character_ids) do
    rows =
      from(i in InventoryItem, where: i.character_id in ^character_ids and i.slot in ^@equipment, select: {i.character_id, i.slot, i.item_id})
      |> GamesRepo.all()

    Map.new(character_ids, fn id ->
      worn = for {^id, slot, item_id} <- rows, Items.get(item_id), into: %{}, do: {slot, item_id}
      {id, Map.new(@equipment, &{&1, worn[&1]})}
    end)
  end

  defp place(character_id, item_id, slot) do
    taken = from(i in InventoryItem, where: i.character_id == ^character_id and i.slot == ^slot) |> GamesRepo.exists?()
    if taken, do: add(character_id, item_id), else: {:ok, GamesRepo.insert!(%InventoryItem{character_id: character_id, item_id: item_id, slot: slot, quantity: 1})}
  end
end

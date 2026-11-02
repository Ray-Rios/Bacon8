defmodule BaconWorld.Jeweller do
  @moduledoc """
  Buying a jeweller's set for Gems (2026-11-01, owner: the polished sets are bought "from a merchant
  in-game for gems", and each purchase is "a transaction recorded in the store plugin").

  `buy/5` puts every piece the buyer's body wears into the character's bags (all of them or none),
  then spends the Gems from the user's Bacon Store wallet (`BaconStore.Wallet.spend/3`): one
  `spend` transaction on the owner's ledger, `game_slug` `"bacon_world"`, `memo` naming the set and
  the character, `reference_type` `"bacon_world_jewel"`, `reference_id` the set. The store's
  Purchases page lists these under "Bought with Gems". If the spend fails, the pieces are taken
  back. The idempotency key includes the client's per-click nonce, so a retried request charges
  once and gives the pieces once.

  The bags live in the games database and the wallet in the hub's, so the two steps can't be one
  database transaction: adding first and taking back on failure means a player is never charged for
  nothing.
  """

  alias BaconWorld.{Inventory, Items}

  @wallet Module.concat([BaconStore, Wallet])

  @doc "The user's Gem balance (0 when the store plugin isn't installed)."
  def balance(user) do
    if user && Code.ensure_loaded?(@wallet), do: apply(@wallet, :balance, [user]), else: 0
  end

  @doc """
  Buys the set `item_id` belongs to for `character` (`%{character_id, name, body}`).
  `{:ok, %{set, pieces, gems_spent, balance}}` or `{:error, message}`.
  """
  def buy(user, character, item_id, nonce, sells \\ nil) do
    with true <- (is_nil(sells) or item_id in sells) || {:error, "They don't sell that."},
         %{jewel: set} = item when is_binary(set) <- Items.get(item_id) || {:error, "They don't sell that."},
         true <- Code.ensure_loaded?(@wallet) || {:error, "Gems aren't available right now."},
         price = Items.jewel_price_gems(),
         have = balance(user),
         true <- have >= price || {:error, "You need #{price} Gems for that (you have #{have})."},
         pieces = Items.jewel_bundle(item, character[:body] || "female"),
         {:ok, added} <- add_all(character.character_id, pieces),
         {:ok, charged?} <- spend(user, price, character, item, nonce, added) do
      {:ok, %{set: set, pieces: pieces, gems_spent: if(charged?, do: price, else: 0), balance: balance(user)}}
    end
  end

  @doc "The set's name (\"Gilded Filament\")."
  def set_name(set) do
    case Items.get("#{set}_bottom") do
      %{name: name} -> name |> String.split(" ") |> Enum.drop(-2) |> Enum.join(" ")
      _ -> set
    end
  end

  defp add_all(character_id, ids) do
    Enum.reduce_while(ids, {:ok, []}, fn id, {:ok, done} ->
      case Inventory.add(character_id, id, 1) do
        {:ok, slots} ->
          {:cont, {:ok, done ++ [{id, slots}]}}

        _ ->
          take_back(character_id, done)
          {:halt, {:error, "Your inventory is full."}}
      end
    end)
  end

  defp take_back(character_id, added) do
    for {_id, slots} <- added, slot <- List.wrap(slots) do
      slot = if is_map(slot), do: slot[:slot] || slot["slot"], else: slot
      if is_binary(slot), do: Inventory.remove(character_id, slot)
    end

    :ok
  end

  # {:ok, true} charged now; {:ok, false} this click was already paid for (the pieces just added go back)
  defp spend(user, price, character, item, nonce, added) do
    set = item.jewel
    shoes? = item.slots == ["feet"]
    what = if shoes?, do: "shoes", else: "set"
    key = "bacon_world:jewel:#{character.character_id}:#{set}:#{what}:#{nonce || System.unique_integer([:positive])}"
    who = if character[:name], do: ", for #{character.name}", else: ""
    memo = if shoes?, do: "#{item.name}#{who}", else: "#{set_name(set)} set#{who}"

    opts = [idempotency_key: key, game_slug: "bacon_world", memo: memo,
            reference_type: "bacon_world_jewel", reference_id: if(shoes?, do: item.id, else: set)]

    case apply(@wallet, :spend, [user, price, opts]) do
      {:ok, _txn, :duplicate} ->
        take_back(character.character_id, added)
        {:ok, false}

      {:ok, _txn} ->
        {:ok, true}

      {:error, :insufficient_gems} ->
        take_back(character.character_id, added)
        {:error, "You don't have enough Gems."}

      _ ->
        take_back(character.character_id, added)
        {:error, "The Gems couldn't be spent; nothing was bought."}
    end
  end
end

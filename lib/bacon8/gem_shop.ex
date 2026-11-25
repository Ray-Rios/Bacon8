defmodule Bacon8.GemShop do
  @moduledoc """
  The jeweller's Gem-only sets for every game (2026-11-24, the owner: a Jeweler in Tears of Babylon and RaysSpaceSim
  "that sells the Gem only items", with real Gem purchases). Bacon World's own jeweller is `BaconWorld.Jeweller`,
  which puts the pieces in its server-kept bags; the other games keep their characters' bags themselves (a character's
  `stats`), so here the hub only takes the Gems and says which pieces were bought, and the game adds them.

  The sets and their price are Bacon World's (`BaconWorld.Items`: items with a `jewel` set; `jewel_price_gems/0`). A
  purchase is one `spend` on the buyer's Bacon Store wallet (`BaconStore.Wallet.spend/3`): `game_slug` the game's,
  `memo` naming the set and the character, `reference_type` `"<game>_jewel"`, `reference_id` the set (or the heels'
  item id). The idempotency key carries the client's per-click `nonce`: a retried request charges once, and is told
  the same pieces again (`charged: false`), so a game that lost the first answer can still add them. Both plugins are
  optional at compile time (the hub runs without them): without either, nothing is for sale.
  """

  @items Module.concat([BaconWorld, Items])
  @wallet Module.concat([BaconStore, Wallet])

  @doc "True when the catalogue and the wallet are both there."
  def available?, do: Code.ensure_loaded?(@items) and Code.ensure_loaded?(@wallet)

  @doc "The user's Gem balance (0 without the store)."
  def balance(nil), do: 0
  def balance(user), do: if(Code.ensure_loaded?(@wallet), do: apply(@wallet, :balance, [user]), else: 0)

  @doc "What a set (or a pair of heels) costs, in Gems."
  def price, do: if(Code.ensure_loaded?(@items), do: apply(@items, :jewel_price_gems, []), else: 0)

  @doc """
  What the jeweller has: `[%{item_id, name, set, slots, pieces}]`, one entry per set (bought as its top and bottom,
  the male's bottom alone) and one per pair of heels, for `body` ("female" or "male").
  """
  def stock(body \\ "female") do
    if Code.ensure_loaded?(@items) do
      items = Enum.filter(apply(@items, :all, []), &is_binary(Map.get(&1, :jewel)))

      sets =
        items
        |> Enum.reject(&(&1.slots == ["feet"]))
        |> Enum.uniq_by(& &1.jewel)
        |> Enum.map(fn i -> %{item_id: i.id, name: set_name(i.jewel), set: i.jewel, slots: [], pieces: pieces(i, body)} end)

      heels = for i <- items, i.slots == ["feet"], do: %{item_id: i.id, name: i.name, set: i.jewel, slots: i.slots, pieces: pieces(i, body)}
      sets ++ heels
    else
      []
    end
  end

  @doc "The pieces buying `item` gives `body`."
  def pieces(item, body), do: apply(@items, :jewel_bundle, [item, if(body == "male", do: "male", else: "female")])

  @doc "A set's name (\"Gilded Filament\")."
  def set_name(set) do
    case apply(@items, :get, ["#{set}_bottom"]) do
      %{name: name} -> name |> String.split(" ") |> Enum.drop(-2) |> Enum.join(" ")
      _ -> set
    end
  end

  @doc """
  Buys `item_id` for `character` (`%{id, name}`) of `user` in game `slug`, for `body`. `nonce` is the client's, one per
  click. `{:ok, %{item_id, pieces, gems_spent, charged, balance}}` or `{:error, message}`.
  """
  def buy(slug, user, character, item_id, body, nonce) do
    with true <- available?() || {:error, "Gems aren't available right now."},
         true <- (is_binary(nonce) and byte_size(nonce) in 6..80) || {:error, "A purchase needs a nonce."},
         %{jewel: set} = item when is_binary(set) <- apply(@items, :get, [item_id]) || {:error, "The jeweller doesn't sell that."},
         price = price(),
         true <- price > 0 || {:error, "The jeweller doesn't sell that."},
         pieces = pieces(item, body),
         {:ok, charged?} <- spend(slug, user, price, character, item, nonce) do
      {:ok, %{item_id: item_id, pieces: pieces, gems_spent: if(charged?, do: price, else: 0), charged: charged?, balance: balance(user)}}
    else
      {:error, _} = e -> e
      _ -> {:error, "The jeweller doesn't sell that."}
    end
  end

  # {:ok, true} charged now; {:ok, false} this click was already paid for
  defp spend(slug, user, price, character, item, nonce) do
    shoes? = item.slots == ["feet"]
    what = if shoes?, do: "shoes", else: "set"
    who = if character[:name], do: ", for #{character.name}", else: ""
    memo = if shoes?, do: "#{item.name}#{who}", else: "#{set_name(item.jewel)} set#{who}"

    opts = [
      idempotency_key: "#{slug}:jewel:#{character.id}:#{item.jewel}:#{what}:#{nonce}",
      game_slug: slug,
      memo: memo,
      reference_type: "#{slug}_jewel",
      reference_id: if(shoes?, do: item.id, else: item.jewel)
    ]

    case apply(@wallet, :spend, [user, price, opts]) do
      {:ok, _txn, :duplicate} -> {:ok, false}
      {:ok, _txn} -> {:ok, true}
      {:error, :insufficient_gems} -> {:error, "You need #{price} Gems for that (you have #{balance(user)})."}
      _ -> {:error, "The Gems couldn't be spent; nothing was bought."}
    end
  end
end

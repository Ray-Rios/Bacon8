defmodule Bacon8.GemShopTest do
  # The jeweller's Gem-only sets for the games that keep their own bags (Bacon8.GemShop, 2026-11-24): the Gems are
  # spent on the buyer's ledger under the game's name, a retried click charges once and is told the same pieces.
  use Bacon8.DataCase, async: false

  alias BaconStore.Wallet
  alias Bacon8.GemShop

  setup do
    %{user: user_fixture(), who: %{id: "c-1", name: "Rosebud"}}
  end

  test "the stock: each set once (its top and bottom; the male's bottom) and each pair of heels" do
    assert GemShop.available?()
    stock = GemShop.stock("female")
    rose = Enum.find(stock, &(&1.set == "jw_rose" and &1.slots == []))
    assert rose.name == "Rose Wire"
    assert Enum.sort(rose.pieces) == ["jw_rose_bottom", "jw_rose_top"]
    assert Enum.any?(stock, &(&1.item_id == "jw_rose_shoes" and &1.pieces == ["jw_rose_shoes"]))
    assert Enum.find(GemShop.stock("male"), &(&1.set == "jw_rose" and &1.slots == [])).pieces == ["jw_rose_bottom"]
    assert GemShop.price() == 100
  end

  test "a set costs 100 Gems, recorded under the game; the same click again charges nothing", %{user: user, who: who} do
    {:ok, _} = Wallet.grant(user, 250, idempotency_key: "gs-test-grant")

    assert {:ok, %{pieces: ["jw_rose_top", "jw_rose_bottom"], gems_spent: 100, charged: true, balance: 150}} =
             GemShop.buy("tears_of_babylon", user, who, "jw_rose_bottom", "female", "click-0001")

    assert [%{amount: 100, memo: "Rose Wire set, for Rosebud", game_slug: "tears_of_babylon", reference_type: "tears_of_babylon_jewel", reference_id: "jw_rose"}] =
             Wallet.spends(user)

    assert {:ok, %{pieces: ["jw_rose_top", "jw_rose_bottom"], gems_spent: 0, charged: false, balance: 150}} =
             GemShop.buy("tears_of_babylon", user, who, "jw_rose_bottom", "female", "click-0001")

    assert length(Wallet.spends(user)) == 1
  end

  test "too few Gems, no nonce, or not a jeweller's piece buys nothing", %{user: user, who: who} do
    {:ok, _} = Wallet.grant(user, 50, idempotency_key: "gs-test-grant-2")
    assert {:error, msg} = GemShop.buy("rays_space_sim", user, who, "jw_thorn_bottom", "male", "click-0002")
    assert msg =~ "100 Gems"
    assert {:error, _} = GemShop.buy("rays_space_sim", user, who, "jw_thorn_bottom", "male", nil)
    assert {:error, _} = GemShop.buy("rays_space_sim", user, who, "homespun_bottom", "male", "click-0003")
    assert Wallet.balance(user) == 50
    assert Wallet.spends(user) == []
  end
end

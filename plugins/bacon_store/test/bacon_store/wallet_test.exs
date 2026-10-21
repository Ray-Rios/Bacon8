defmodule BaconStore.WalletTest do
  use Bacon8.DataCase, async: true

  alias BaconStore.Wallet

  defp entries_sum do
    Repo.one(from e in BaconStore.Wallet.Entry, select: coalesce(sum(e.amount), 0)) |> Decimal.new() |> Decimal.to_integer()
  end

  test "a new user has no Gems" do
    assert Wallet.balance(user_fixture()) == 0
  end

  test "credits, spends and grants are double-entry and idempotent" do
    user = user_fixture()
    order = %{id: Ecto.UUID.generate()}

    assert {:ok, _} = Wallet.credit_purchase(user, 500, order)
    assert {:ok, _, :duplicate} = Wallet.credit_purchase(user, 500, order)
    assert Wallet.balance(user) == 500

    assert {:ok, _} = Wallet.spend(user, 120, idempotency_key: "spend-1", game_slug: "web_lobby", memo: "Hat")
    assert {:ok, _, :duplicate} = Wallet.spend(user, 120, idempotency_key: "spend-1")
    assert {:ok, _} = Wallet.grant(user, 30, idempotency_key: "promo-1", memo: "Welcome")
    assert Wallet.balance(user) == 410

    # Every transaction balances, so the whole ledger sums to zero.
    assert entries_sum() == 0
    assert Wallet.system_balance("gem_sales") == -500
    assert Wallet.system_balance("gem_spend") == 120

    assert [%{kind: "grant", amount: 30}, %{kind: "spend", amount: -120, game_slug: "web_lobby"}, %{kind: "gem_purchase", amount: 500}] =
             Wallet.history(user)
  end

  test "spending can't go below zero" do
    user = user_fixture()
    {:ok, _} = Wallet.grant(user, 50, idempotency_key: "g")

    assert {:error, :insufficient_gems} = Wallet.spend(user, 51, idempotency_key: "too-much")
    assert Wallet.balance(user) == 50
    assert {:ok, _} = Wallet.spend(user, 50, idempotency_key: "exact")
    assert Wallet.balance(user) == 0
  end

  test "a clawback may go negative, and then spending is blocked" do
    user = user_fixture()
    order = %{id: Ecto.UUID.generate()}
    {:ok, _} = Wallet.credit_purchase(user, 500, order)
    {:ok, _} = Wallet.spend(user, 400, idempotency_key: "s")

    assert {:ok, _} = Wallet.clawback(user, 500, order)
    assert {:ok, _, :duplicate} = Wallet.clawback(user, 500, order)
    assert Wallet.balance(user) == -400
    assert {:error, :insufficient_gems} = Wallet.spend(user, 1, idempotency_key: "blocked")
    assert entries_sum() == 0
  end
end

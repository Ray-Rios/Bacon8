defmodule BaconStore.BasketTest do
  # Several items in one purchase (2026-10-29): the cart, one checkout or one Gem payment for all,
  # one receipt number. Not async: the fake provider and hub events use global config.
  use Bacon8.DataCase, async: false

  alias Bacon8.Entitlements
  alias BaconStore.{Store, Wallet}
  alias BaconStore.Payments.Fake
  alias BaconStore.Store.{Cart, Catalog, Fulfilment}

  defp buyer(gems \\ 0) do
    user = user_fixture(%{email_verified_at: DateTime.utc_now() |> DateTime.truncate(:second)})
    if gems > 0, do: {:ok, _} = Wallet.grant(user, gems, idempotency_key: "test-grant-#{user.id}")
    user
  end

  defp download!(name, cents, gems) do
    {:ok, p} = Catalog.create_product(%{active: true, kind: "download", name: name, price_cents: cents, price_gems: gems})
    p
  end

  defp pack(slug \\ "gems_1000"), do: Repo.get_by!(Store.Product, slug: slug)

  test "the cart keeps one of each product and follows the buyer" do
    user = buyer()
    a = download!("Soundtrack", 499, 499)
    b = download!("Art book", 999, 999)

    assert :ok = Cart.add(user, a)
    assert :ok = Cart.add(user, a)
    assert :ok = Cart.add(user, b)
    assert Enum.map(Cart.products(user), & &1.id) == [a.id, b.id]
    assert Cart.count(user) == 2

    assert :ok = Cart.remove(user, a.id)
    assert Enum.map(Cart.products(user), & &1.id) == [b.id]
    assert Cart.products(nil) == []
  end

  test "one card checkout for the whole cart: one number, one payment, everything delivered" do
    user = buyer()
    a = download!("Soundtrack", 499, nil)
    b = download!("Art book", 999, nil)
    for p <- [a, b, pack()], do: Cart.add(user, p)

    assert {:ok, [o1, o2, o3] = orders, "/store/fake-checkout/" <> ref} = Store.start_basket_checkout(user, Cart.products(user))
    assert Enum.all?(orders, &(&1.status == "awaiting_payment" and &1.provider_ref == ref))
    assert o1.basket_id == o2.basket_id and o2.basket_id == o3.basket_id
    assert o1.number == o2.number and is_integer(o1.number) and o1.number >= 8001

    # the provider took the basket's total
    total = 499 + 999 + 1000
    assert {:error, {:amount_mismatch, _}} = Fake.complete(ref, 499)
    assert :ok = Fake.complete(ref, total)

    assert Enum.all?(Store.basket(o1), &(&1.status == "fulfilled"))
    assert Entitlements.active?(user, Fulfilment.download_kind(), a.id)
    assert Entitlements.active?(user, Fulfilment.download_kind(), b.id)
    assert Wallet.balance(user) == 1000
    assert Cart.count(user) == 0, "what was bought leaves the cart"

    receipt = Store.receipt(Store.basket(o2))
    assert receipt.number == o1.number and receipt.status == "fulfilled" and length(receipt.orders) == 3
    assert receipt.total == "$24.98"
    assert [%{number: n}] = Store.list_user_receipts(user)
    assert n == o1.number
  end

  test "a basket can't hold what the buyer can't buy" do
    user = buyer()
    owned = download!("Owned", 499, nil)
    {:ok, _} = Entitlements.grant(user, %{kind: Fulfilment.download_kind(), key: owned.id, source_type: "test", source_id: Ecto.UUID.generate()})
    other = download!("Other", 499, nil)

    assert {:error, {%{id: id}, :already_owned}} = Store.start_basket_checkout(user, [other, owned])
    assert id == owned.id
    assert {:error, :empty_basket} = Store.start_basket_checkout(user, [])
    assert {:error, :duplicate_item} = Store.start_basket_checkout(user, [other, other])
    assert Store.reason_text({owned, :already_owned}) == "Owned: You already own this."
  end

  test "Gems pay for a whole basket at once, or for none of it" do
    a = download!("Soundtrack", 499, 400)
    b = download!("Art book", 999, 800)

    poor = buyer(1000)
    assert {:error, :insufficient_gems} = Store.buy_basket_with_gems(poor, [a, b])
    assert Wallet.balance(poor) == 1000
    refute Entitlements.active?(poor, Fulfilment.download_kind(), a.id), "nothing is half bought"

    rich = buyer(1500)
    Cart.add(rich, a)
    Cart.add(rich, b)
    assert {:ok, [o1, o2]} = Store.buy_basket_with_gems(rich, Cart.products(rich))
    assert o1.number == o2.number and o1.basket_id == o2.basket_id
    assert Wallet.balance(rich) == 300
    assert Cart.count(rich) == 0
    assert Store.receipt([o1, o2]).total == "💎 1,200"

    # a Gem pack is never bought with Gems
    assert {:error, {_, :not_for_gems}} = Store.buy_basket_with_gems(rich, [pack()])
  end

  test "one item is still a basket of one, with its own number" do
    user = buyer()
    {:ok, o1, _} = Store.start_checkout(user, pack("gems_500"))
    {:ok, o2, _} = Store.start_checkout(user, pack("gems_1000"))
    assert o1.basket_id != o2.basket_id and o2.number > o1.number
    assert Store.basket(o1) |> Enum.map(& &1.id) == [o1.id]
    assert Store.get_order_by_ref("fake", o1.provider_ref).id == o1.id
  end
end

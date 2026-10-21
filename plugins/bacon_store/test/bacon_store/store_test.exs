defmodule BaconStore.StoreTest do
  use Bacon8.DataCase, async: false

  alias BaconStore.{Store, Wallet}
  alias BaconStore.Payments.Fake

  defp buyer(attrs \\ %{}) do
    user_fixture(Map.merge(%{email_verified_at: DateTime.utc_now() |> DateTime.truncate(:second)}, attrs))
  end

  defp pack(slug \\ "gems_1000"), do: Repo.get_by!(Store.Product, slug: slug)

  test "the launch packs are seeded at 100 Gems per dollar" do
    packs = Store.gem_packs()
    assert Enum.map(packs, & &1.gems) == [500, 1000, 2500, 5000, 10000]
    assert Enum.all?(packs, &(&1.gems == &1.price_cents))
  end

  test "a pack must sell Gems at the house rate; extra Gems are a bonus" do
    assert {:error, cs} = Store.create_product(%{slug: "cheap", kind: "gem_pack", name: "Cheap", price_cents: 100, gems: 500})
    assert %{gems: [_]} = errors_on(cs)
    assert {:ok, _} = Store.create_product(%{slug: "promo", kind: "gem_pack", name: "Promo", price_cents: 100, gems: 100, bonus_gems: 50})
  end

  test "who may buy" do
    assert {:error, :not_signed_in} = Store.can_buy(nil)
    assert {:error, :email_unverified} = Store.can_buy(user_fixture())
    assert {:error, :not_eligible} = Store.can_buy(buyer(%{role: "guest"}))
    assert {:error, :not_eligible} = Store.can_buy(buyer(%{role: "banned"}))
    assert :ok = Store.can_buy(buyer())
  end

  test "checkout starts straight from the Buy button" do
    assert {:ok, %{status: "awaiting_payment", terms_accepted_at: %DateTime{}}, "/store/fake-checkout/" <> _} =
             Store.start_checkout(buyer(), pack())
  end

  test "paying credits the Gems once, even if the event is delivered again" do
    user = buyer()
    {:ok, order, "/store/fake-checkout/" <> ref} = Store.start_checkout(user, pack())
    assert order.status == "awaiting_payment" and order.gems == 1000
    Phoenix.PubSub.subscribe(Bacon8.PubSub, Store.topic(order))

    assert :ok = Fake.complete(ref, 1000)
    assert_receive {:order_updated, %{status: "fulfilled"}}
    assert Wallet.balance(user) == 1000

    # A second "payment" event for the same checkout changes nothing.
    assert :ok = Fake.complete(ref, 1000)
    assert Wallet.balance(user) == 1000
    assert %{status: "fulfilled", paid_at: %DateTime{}} = Store.get_user_order(user, order.id)
  end

  test "a payment for the wrong amount isn't accepted" do
    user = buyer()
    {:ok, order, _} = Store.start_checkout(user, pack())

    assert {:error, {:amount_mismatch, _}} = Fake.complete(order.provider_ref, 1)
    assert Wallet.balance(user) == 0
    assert %{status: "awaiting_payment"} = Store.get_user_order(user, order.id)
  end

  test "a payment that arrives after the buyer cancelled is still honoured" do
    user = buyer()
    {:ok, order, _} = Store.start_checkout(user, pack("gems_500"))
    {:ok, _} = Store.cancel_unpaid(order)

    assert :ok = Fake.complete(order.provider_ref, 500)
    assert Wallet.balance(user) == 500
  end

  test "a declined card fails the order" do
    user = buyer()
    {:ok, order, _} = Store.start_checkout(user, pack())
    assert :ok = Fake.fail(order.provider_ref)
    assert %{status: "failed"} = Store.get_user_order(user, order.id)
  end

  test "a lost chargeback takes the Gems back; a won one restores the order" do
    user = buyer()
    {:ok, order, _} = Store.start_checkout(user, pack("gems_500"))
    :ok = Fake.complete(order.provider_ref, 500)

    :ok = Fake.dispute(order.provider_ref, :dispute_opened)
    assert %{status: "disputed"} = Store.get_user_order(user, order.id)
    # Held while the bank decides.
    assert Wallet.balance(user) == 0
    :ok = Fake.dispute(order.provider_ref, :dispute_won)
    assert %{status: "fulfilled"} = Store.get_user_order(user, order.id)
    assert Wallet.balance(user) == 500

    :ok = Fake.dispute(order.provider_ref, :dispute_opened)
    :ok = Fake.dispute(order.provider_ref, :dispute_lost)
    assert %{status: "charged_back"} = Store.get_user_order(user, order.id)
    assert Wallet.balance(user) == 0
  end

  test "an event for an unknown checkout is stored and reported, not crashed on" do
    assert {:error, :unknown_order} = Fake.complete("fake_cs_nope", 500)
    assert [%{event_type: "checkout_completed", processed_at: nil, error: error} | _] = BaconStore.Payments.recent_events()
    assert error =~ "unknown_order"
  end

  test "someone else's order isn't visible" do
    {:ok, order, _} = Store.start_checkout(buyer(), pack())
    assert Store.get_user_order(buyer(), order.id) == nil
  end

  test "the fake provider is refused when it isn't enabled" do
    config = Application.get_env(:bacon8, BaconStore.Payments)
    Application.put_env(:bacon8, BaconStore.Payments, Keyword.put(config, :fake_enabled, false))
    on_exit(fn -> Application.put_env(:bacon8, BaconStore.Payments, config) end)

    refute Store.checkout_available?()
    assert {:error, :unknown_provider} = Store.start_checkout(buyer(), pack())
  end

  test "admin lists and stats count paid orders and their revenue" do
    user = buyer()
    {:ok, paid, "/store/fake-checkout/" <> ref} = Store.start_checkout(user, pack("gems_2500"))
    assert :ok = Fake.complete(ref, 2500)
    {:ok, unpaid, _} = Store.start_checkout(user, pack())

    assert [%{id: id}] = Store.list_orders(status: "fulfilled")
    assert id == paid.id
    assert Enum.map(Store.list_orders(), & &1.id) == [unpaid.id, paid.id]
    assert %{user: %{id: user_id}} = Store.get_order(paid.id)
    assert user_id == user.id
    assert Store.get_order("not-a-uuid") == nil

    assert %{orders: 1, products: 5, revenue_today_cents: 2500, revenue_month_cents: 2500} = Store.stats()
  end
end

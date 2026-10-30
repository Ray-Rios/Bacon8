defmodule BaconStore.CheckoutSettleTest do
  # Unfinished checkouts (2026-10-29c): the buyer leaves the provider's page, starts another,
  # cancels, or a webhook is late. Each is settled, and Purchases shows only what was paid for.
  # Not async: the fake provider's pretend statuses are global config.
  use Bacon8.DataCase, async: false
  import Ecto.Query

  alias Bacon8.Entitlements
  alias BaconStore.{Store, Wallet}
  alias BaconStore.Payments.{Fake, Stripe}
  alias BaconStore.Store.{Cart, Catalog, Fulfilment, Order}

  setup do
    on_exit(fn -> Application.delete_env(:bacon8, Fake) end)
    :ok
  end

  defp buyer, do: user_fixture(%{email_verified_at: DateTime.utc_now() |> DateTime.truncate(:second)})

  defp drake! do
    {:ok, p} = Catalog.create_product(%{active: true, kind: "download", name: "Verdant Drake", price_cents: 1500})
    p
  end

  defp pack(slug \\ "gems_1000"), do: Repo.get_by!(Store.Product, slug: slug)

  # The provider knows a checkout was paid, but its webhook hasn't arrived.
  defp provider_says_paid(ref, cents),
    do: Application.put_env(:bacon8, Fake, status: %{ref => %{state: :paid, amount_cents: cents, currency: "usd", payment_ref: "pi_" <> ref}})

  defp reload(order), do: Repo.get!(Order, order.id)

  test "Back from the provider, then another checkout: the first is closed, and only paid things are purchases" do
    user = buyer()
    drake = drake!()

    {:ok, first, _} = Store.start_checkout(user, pack())
    assert [%{lead: %{id: first_id}}] = Store.open_checkouts(user)
    assert first_id == first.id
    assert Store.list_user_receipts(user) == [], "an unpaid checkout isn't a purchase"

    {:ok, [second | _], _} = Store.start_basket_checkout(user, [drake, pack()])
    assert %{status: "cancelled", failure_reason: "replaced by a newer checkout"} = reload(first)
    assert [%{lead: %{id: second_id}, orders: [_, _]}] = Store.open_checkouts(user)
    assert second_id == second.id

    assert :ok = Fake.complete(second.provider_ref, 2500)
    assert [%{number: n}] = Store.list_user_receipts(user)
    assert n == second.number
    assert Store.open_checkouts(user) == []
  end

  test "Cancel (the button, or the provider's cancel link) closes the checkout and leaves the cart alone" do
    user = buyer()
    drake = drake!()
    Cart.add(user, drake)

    {:ok, [order], _} = Store.start_basket_checkout(user, Cart.products(user))
    assert {:ok, [%{status: "cancelled", failure_reason: "cancelled by the buyer"}]} = Store.cancel_checkout(user, order.id)
    assert Store.open_checkouts(user) == []
    assert Store.list_user_receipts(user) == []
    assert Cart.count(user) == 1, "the cart keeps what was in it"

    # someone else can't cancel it; cancelling twice is harmless
    assert {:error, :not_found} = Store.cancel_checkout(buyer(), order.id)
    assert {:ok, _} = Store.cancel_checkout(user, order.id)
  end

  test "a payment whose webhook is late is delivered, not cancelled" do
    user = buyer()
    drake = drake!()
    {:ok, order, _} = Store.start_checkout(user, drake)
    provider_says_paid(order.provider_ref, 1500)

    # cancelling finds out it was paid
    assert {:error, :already_paid} = Store.cancel_checkout(user, order.id)
    assert %{status: "fulfilled", provider_payment_ref: "pi_" <> _} = reload(order)
    assert Entitlements.active?(user, Fulfilment.download_kind(), drake.id)

    # and the real webhook, when it comes, changes nothing
    assert :ok = Fake.complete(order.provider_ref, 1500)
    assert [_] = Store.list_user_receipts(user)
  end

  test "starting a checkout after one that was paid but not yet reported never sells the same thing twice" do
    user = buyer()
    drake = drake!()
    {:ok, first, _} = Store.start_checkout(user, drake)
    provider_says_paid(first.provider_ref, 1500)

    assert {:error, {%{id: id}, :already_owned}} = Store.start_basket_checkout(user, [drake, pack()])
    assert id == drake.id
    assert reload(first).status == "fulfilled"
  end

  test "reconcile/1 asks the provider: paid is delivered, expired is closed, open is left" do
    user = buyer()
    {:ok, order, _} = Store.start_checkout(user, pack())
    assert Store.reconcile(Store.basket(order)) == :open
    assert reload(order).status == "awaiting_payment"

    provider_says_paid(order.provider_ref, 1000)
    assert Store.reconcile(Store.basket(order)) == :paid
    assert reload(order).status == "fulfilled"
    assert Wallet.balance(user) == 1000

    other = buyer()
    {:ok, gone, _} = Store.start_checkout(other, pack("gems_500"))
    Application.put_env(:bacon8, Fake, status: %{gone.provider_ref => %{state: :expired}})
    assert Store.reconcile(Store.basket(gone)) == :expired
    assert %{status: "failed", paid_at: nil} = reload(gone)
  end

  test "the sweeper settles checkouts whose time is up, and only those" do
    user = buyer()
    {:ok, stale, _} = Store.start_checkout(user, pack())
    Repo.update_all(from(o in Order, where: o.id == ^stale.id), set: [checkout_expires_at: DateTime.add(DateTime.utc_now(), -60, :second)])

    fresh_user = buyer()
    {:ok, fresh, _} = Store.start_checkout(fresh_user, pack())

    paid_user = buyer()
    {:ok, paid, _} = Store.start_checkout(paid_user, pack("gems_500"))
    Repo.update_all(from(o in Order, where: o.id == ^paid.id), set: [checkout_expires_at: DateTime.add(DateTime.utc_now(), -60, :second)])
    provider_says_paid(paid.provider_ref, 500)

    # started before checkouts had an expiry: 35 minutes
    old_user = buyer()
    {:ok, old, _} = Store.start_checkout(old_user, pack())
    Repo.update_all(from(o in Order, where: o.id == ^old.id), set: [checkout_expires_at: nil, inserted_at: DateTime.add(DateTime.utc_now(), -36 * 60, :second)])

    assert Store.settle_stale_checkouts() == 3
    assert %{status: "cancelled", failure_reason: "checkout timed out"} = reload(stale)
    assert reload(fresh).status == "awaiting_payment"
    assert reload(paid).status == "fulfilled"
    assert reload(old).status == "cancelled"
  end

  test "money taken for something the buyer already owns is flagged for a refund, not delivered twice" do
    user = buyer()
    drake = drake!()
    {:ok, order, _} = Store.start_checkout(user, drake)
    # it reached them another way meanwhile (a second checkout paid in another tab, say)
    {:ok, _} = Entitlements.grant(user, %{kind: Fulfilment.download_kind(), key: drake.id, source_type: "test", source_id: Ecto.UUID.generate()})

    assert :ok = Fake.complete(order.provider_ref, 1500)
    assert %{status: "paid", failure_reason: note, paid_at: %DateTime{}} = reload(order)
    assert note == Store.duplicate_note()
    assert [_] = Store.list_user_receipts(user), "it was paid for, so it's a purchase"
  end

  test "admin views: purchases by default, open and abandoned checkouts apart" do
    user = buyer()
    {:ok, paid, _} = Store.start_checkout(user, pack("gems_500"))
    :ok = Fake.complete(paid.provider_ref, 500)
    {:ok, dropped, _} = Store.start_checkout(user, pack())
    {:ok, open, _} = Store.start_checkout(user, pack("gems_2500"))

    ids = fn view -> Enum.map(Store.list_receipts(view: view), & &1.lead.id) end
    assert ids.("purchases") == [paid.id]
    assert ids.("open") == [open.id]
    assert ids.("abandoned") == [dropped.id]
    assert length(ids.("all")) == 3
  end

  test "checkout links: Stripe sessions are short, carry the buyer's email, and come back to the right place" do
    user = buyer()
    {:ok, order, _} = Store.start_checkout(user, pack())
    assert %DateTime{} = order.checkout_expires_at
    assert DateTime.diff(order.checkout_expires_at, DateTime.utc_now(), :minute) in 29..31
    assert "/store/fake-checkout/" <> _ = order.checkout_url
    assert Store.resumable?(Store.receipt(Store.basket(reload(order))))

    params = Stripe.checkout_params(order, success_url: "/s", cancel_url: "/c", email: "a@example.com")
    assert params["customer_email"] == "a@example.com"
    expires = String.to_integer(params["expires_at"])
    assert expires - System.system_time(:second) in (30 * 60)..(32 * 60), "Stripe's minimum is 30 minutes"

    assert %{state: :paid, amount_cents: 1000} = Stripe.session_state(%{"status" => "complete", "payment_status" => "paid", "amount_total" => 1000})
    assert %{state: :processing} = Stripe.session_state(%{"status" => "complete", "payment_status" => "unpaid"})
    assert %{state: :expired} = Stripe.session_state(%{"status" => "expired"})
    assert %{state: :open} = Stripe.session_state(%{"status" => "open"})
    assert {:error, :bad_ref} = Stripe.expire_checkout("../../charges")
  end
end

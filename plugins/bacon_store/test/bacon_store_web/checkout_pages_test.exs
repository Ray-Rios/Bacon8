defmodule BaconStoreWeb.CheckoutPagesTest do
  # The buyer's side of unfinished checkouts (2026-10-29c): paying for one thing with others in
  # the cart, the provider's cancel link, and an unfinished checkout on the store and Purchases.
  use Bacon8.DataCase, async: false
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias BaconStore.Store
  alias BaconStore.Store.{Cart, Catalog, Order}

  @endpoint Bacon8Web.Endpoint

  setup do
    {:ok, _} = Bacon8.Plugins.activate("bacon_store")
    on_exit(fn -> :persistent_term.erase({Bacon8.Plugins, :active}) end)
    :ok
  end

  defp verified, do: user_fixture(%{email_verified_at: DateTime.utc_now() |> DateTime.truncate(:second)})
  defp signed_in(user), do: build_conn() |> Plug.Test.init_test_session(%{"user_id" => user.id})

  defp drake! do
    {:ok, p} = Catalog.create_product(%{active: true, kind: "download", name: "Verdant Drake", price_cents: 1500})
    p
  end

  defp pack, do: Repo.get_by!(Store.Product, slug: "gems_1000")

  test "Pay on a Gem pack with a drake in the cart puts the pack with it and opens the cart" do
    user = verified()
    Cart.add(user, drake!())

    {:ok, view, html} = live(signed_in(user), "/store?item=#{pack().slug}")
    assert html =~ "1 other item in your cart"
    view |> element("button", "Pay $10.00") |> render_click()

    assert_patch(view, "/store?cart=1")
    html = render(view)
    assert html =~ "Your cart" and html =~ "Verdant Drake" and html =~ "is in your cart with 1 other item"
    assert Cart.count(user) == 2
    assert Repo.aggregate(Order, :count) == 0, "no checkout was started behind the buyer's back"
  end

  test "Pay with an empty cart still goes straight to checkout" do
    user = verified()
    {:ok, view, _} = live(signed_in(user), "/store?item=#{pack().slug}")
    view |> element("button", "Pay $10.00") |> render_click()
    assert {"/store/fake-checkout/" <> _, _} = assert_redirect(view)
  end

  test "the provider's cancel link closes the checkout and says nothing was charged" do
    user = verified()
    {:ok, order, _} = Store.start_checkout(user, drake!())

    {:ok, _view, html} = live(signed_in(user), "/store/orders/#{order.id}?checkout=cancelled")
    assert html =~ "Checkout cancelled. Nothing was charged."
    assert Repo.get!(Order, order.id).status == "cancelled"

    {:ok, _view, html} = live(signed_in(user), "/store/orders")
    assert html =~ "No purchases yet."
    refute html =~ "Unfinished checkout"
  end

  test "an unfinished checkout waits on the store and Purchases, to continue or cancel" do
    user = verified()
    {:ok, order, _} = Store.start_checkout(user, drake!())

    {:ok, view, html} = live(signed_in(user), "/store")
    assert html =~ "Unfinished checkout: Order ##{order.number}"
    assert html =~ ~s(href="/store/fake-checkout/)

    {:ok, purchases, html} = live(signed_in(user), "/store/orders")
    assert html =~ "Unfinished checkout" and html =~ "Continue to payment" and html =~ "No purchases yet."
    purchases |> element("#open-checkouts button", "Cancel checkout") |> render_click()
    refute render(purchases) =~ "Continue to payment"

    view |> element("#open-checkout-#{order.id} button", "Cancel it") |> render_click()
    refute render(view) =~ "Unfinished checkout"
    assert Repo.get!(Order, order.id).status == "cancelled"
  end

  test "a closed checkout can't be paid on the test checkout page" do
    user = verified()
    {:ok, order, "/store/fake-checkout/" <> _ = url} = Store.start_checkout(user, drake!())
    {:ok, _} = Store.cancel_checkout(user, order.id)
    assert {:error, {:live_redirect, %{to: "/store"}}} = live(signed_in(user), url)
  end
end

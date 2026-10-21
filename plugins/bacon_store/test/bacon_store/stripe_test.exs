defmodule BaconStore.Payments.StripeTest do
  # Not async: Stripe's settings are application config.
  use Bacon8.DataCase, async: false
  import Phoenix.ConnTest
  import Plug.Conn, only: [put_req_header: 3]

  alias BaconStore.Payments.Stripe
  alias BaconStore.{Store, Wallet}

  @endpoint Bacon8Web.Endpoint
  @secret "whsec_test_secret"

  setup do
    Application.put_env(:bacon8, Stripe, secret_key: "sk_test_dummy", webhook_secret: @secret)
    on_exit(fn -> Application.delete_env(:bacon8, Stripe) end)
    # The store is a plugin (ADR 0001, phase 3); tests start with none active.
    {:ok, _} = Bacon8.Plugins.activate("bacon_store")
    on_exit(fn -> :persistent_term.erase({Bacon8.Plugins, :active}) end)
    :ok
  end

  defp sign(body, secret \\ @secret, t \\ System.system_time(:second)) do
    mac = :crypto.mac(:hmac, :sha256, secret, "#{t}.#{body}") |> Base.encode16(case: :lower)
    "t=#{t},v1=#{mac}"
  end

  defp event(type, object), do: Jason.encode!(%{"id" => "evt_" <> Ecto.UUID.generate(), "type" => type, "data" => %{"object" => object}})

  # The old URL, which Stripe's dashboard still names (a `fixed` route).
  defp webhook(body, signature, path \\ "/api/webhooks/payments/stripe") do
    build_conn()
    |> put_req_header("content-type", "application/json")
    |> put_req_header("stripe-signature", signature)
    |> post(path, body)
  end

  describe "webhook URLs" do
    test "the plugin's own URL is accepted, with the raw body kept for the signature" do
      body = event("customer.created", %{"id" => "cus_1"})
      conn = webhook(body, sign(body), "/api/store/webhooks/stripe")
      assert conn.status == 200
    end

    test "a bad signature on the new URL is refused, as on the old one" do
      body = event("customer.created", %{"id" => "cus_1"})
      assert webhook(body, sign(body, "whsec_wrong"), "/api/store/webhooks/stripe").status == 400
    end

    test "while the store is inactive both URLs answer 404" do
      {:ok, _} = Bacon8.Plugins.deactivate("bacon_store")
      body = event("customer.created", %{"id" => "cus_1"})
      assert webhook(body, sign(body)).status == 404
      assert webhook(body, sign(body), "/api/store/webhooks/stripe").status == 404
    end
  end

  defp stripe_order(user, gems \\ 1000) do
    product = Repo.get_by!(Store.Product, slug: "gems_1000")

    Repo.insert!(%Store.Order{
      user_id: user.id,
      product_id: product.id,
      status: "awaiting_payment",
      provider: "stripe",
      provider_ref: "cs_test_" <> Ecto.UUID.generate(),
      product_name: product.name,
      amount_cents: 1000,
      currency: "usd",
      gems: gems,
      terms_accepted_at: DateTime.utc_now()
    })
  end

  describe "signatures" do
    test "a correct, fresh signature verifies" do
      assert :ok = Stripe.verify("{}", sign("{}"), @secret, System.system_time(:second))
    end

    test "a wrong secret, a changed body or an old timestamp doesn't" do
      now = System.system_time(:second)
      assert {:error, :bad_signature} = Stripe.verify("{}", sign("{}", "whsec_other"), @secret, now)
      assert {:error, :bad_signature} = Stripe.verify(~s({"a":1}), sign("{}"), @secret, now)
      assert {:error, :stale_signature} = Stripe.verify("{}", sign("{}", @secret, now - 600), @secret, now)
      assert {:error, :bad_signature} = Stripe.verify("{}", "garbage", @secret, now)
      assert {:error, :no_webhook_secret} = Stripe.verify("{}", sign("{}"), nil, now)
    end

    test "any of several v1 signatures may match (secret rotation)" do
      t = System.system_time(:second)
      good = sign("{}", @secret, t)
      assert :ok = Stripe.verify("{}", "t=#{t},v1=deadbeef," <> String.replace(good, "t=#{t},", ""), @secret, t)
    end
  end

  test "checkout params price the order and send the buyer back to its page" do
    order = %{id: "ord_1", currency: "usd", amount_cents: 2500, product_name: "2,500 Gems"}
    params = Stripe.checkout_params(order, success_url: "/store/orders/ord_1", cancel_url: "/store/orders/ord_1")

    assert params["mode"] == "payment"
    assert params["client_reference_id"] == "ord_1"
    assert params["success_url"] == Bacon8Web.Endpoint.url() <> "/store/orders/ord_1"
    assert %{"unit_amount" => "2500", "currency" => "usd", "product_data" => %{"name" => "2,500 Gems"}} =
             params["line_items"]["0"]["price_data"]

    # Form-encodes the way Stripe expects nested fields.
    assert Plug.Conn.Query.encode(params) =~ "line_items[0][price_data][unit_amount]=2500"
  end

  test "Stripe is unavailable without a secret key" do
    Application.delete_env(:bacon8, Stripe)
    assert {:error, :not_configured} = BaconStore.Payments.provider("stripe")
  end

  test "a paid checkout webhook credits the Gems once; bad signatures are refused" do
    user = user_fixture()
    order = stripe_order(user)

    body =
      event("checkout.session.completed", %{
        "id" => order.provider_ref,
        "payment_status" => "paid",
        "payment_intent" => "pi_123",
        "amount_total" => 1000,
        "currency" => "usd"
      })

    assert webhook(body, sign(body, "whsec_wrong")).status == 400
    assert Wallet.balance(user) == 0

    assert webhook(body, sign(body)).status == 200
    assert Wallet.balance(user) == 1000
    assert %{status: "fulfilled", provider_payment_ref: "pi_123"} = Store.get_user_order(user, order.id)

    # Stripe re-delivers: nothing changes.
    assert webhook(body, sign(body)).status == 200
    assert Wallet.balance(user) == 1000
  end

  test "an unpaid (still clearing) session waits for async_payment_succeeded" do
    user = user_fixture()
    order = stripe_order(user)
    session = %{"id" => order.provider_ref, "payment_status" => "unpaid", "amount_total" => 1000, "currency" => "usd"}

    body = event("checkout.session.completed", session)
    assert webhook(body, sign(body)).status == 200
    assert Wallet.balance(user) == 0

    body = event("checkout.session.async_payment_succeeded", Map.put(session, "payment_status", "paid"))
    assert webhook(body, sign(body)).status == 200
    assert Wallet.balance(user) == 1000
  end

  test "an expired session fails the order" do
    user = user_fixture()
    order = stripe_order(user)
    body = event("checkout.session.expired", %{"id" => order.provider_ref})
    assert webhook(body, sign(body)).status == 200
    assert %{status: "failed"} = Store.get_user_order(user, order.id)
  end

  test "a dispute that arrives before the payment is applied as soon as the payment is" do
    user = user_fixture()
    order = stripe_order(user)

    # Stripe sends the dispute first; we don't know the PaymentIntent yet.
    opened = event("charge.dispute.created", %{"id" => "dp_race", "payment_intent" => "pi_race", "status" => "needs_response"})
    assert webhook(opened, sign(opened)).status == 500

    paid = event("checkout.session.completed", %{"id" => order.provider_ref, "payment_status" => "paid", "payment_intent" => "pi_race", "amount_total" => 1000, "currency" => "usd"})
    assert webhook(paid, sign(paid)).status == 200

    assert %{status: "disputed"} = Store.get_user_order(user, order.id)
    assert Wallet.balance(user) == 0
    assert Enum.all?(BaconStore.Payments.recent_events(), &(&1.processed_at && is_nil(&1.error)))
  end

  test "disputes find the order by its PaymentIntent; a lost one takes the Gems back" do
    user = user_fixture()
    order = stripe_order(user)

    paid = event("checkout.session.completed", %{"id" => order.provider_ref, "payment_status" => "paid", "payment_intent" => "pi_disp", "amount_total" => 1000, "currency" => "usd"})
    assert webhook(paid, sign(paid)).status == 200

    opened = event("charge.dispute.created", %{"id" => "dp_1", "payment_intent" => "pi_disp", "status" => "needs_response"})
    assert webhook(opened, sign(opened)).status == 200
    assert %{status: "disputed"} = Store.get_user_order(user, order.id)

    lost = event("charge.dispute.closed", %{"id" => "dp_1", "payment_intent" => "pi_disp", "status" => "lost"})
    assert webhook(lost, sign(lost)).status == 200
    assert %{status: "charged_back"} = Store.get_user_order(user, order.id)
    assert Wallet.balance(user) == 0
  end

  test "event types the hub doesn't use are acknowledged and ignored" do
    body = event("customer.created", %{"id" => "cus_1"})
    assert webhook(body, sign(body)).status == 200
  end

  test "a webhook for a provider that isn't set up is a 404" do
    assert build_conn() |> put_req_header("content-type", "application/json") |> post("/api/webhooks/payments/paypal", "{}") |> Map.fetch!(:status) == 404
  end
end

defmodule BaconStore.Payments.Stripe do
  @moduledoc """
  Stripe, through hosted Checkout (BACON8.md §8). Card details go to
  Stripe's page, never to the hub.

  Talks to Stripe's REST API directly over `Bacon8.Finch` (no SDK): one call
  to create a Checkout Session, and webhook signatures checked here with
  HMAC-SHA256, as Stripe documents.

  Settings, read from the environment at runtime (app config overrides them):

    * `STRIPE_SECRET_KEY` - `sk_test_...` or `sk_live_...`. Without it the
      provider reports itself unavailable.
    * `STRIPE_WEBHOOK_SECRET` - `whsec_...`, from the webhook endpoint in the
      Stripe dashboard (or `stripe listen` locally).

  Webhook URL: `/api/store/webhooks/stripe`, subscribed to
  `checkout.session.completed`, `checkout.session.async_payment_succeeded`,
  `checkout.session.async_payment_failed`, `checkout.session.expired`,
  `charge.dispute.created` and `charge.dispute.closed`.

  Unfinished checkouts (2026-10-29c): a session lives 31 minutes (`expires_at`; Stripe
  allows 30 minutes to 24 hours), `expire_checkout/1` closes one early (a newer checkout, the
  buyer's Cancel, the cancel link), and `checkout_status/1` asks Stripe where one stands, so the
  hub settles a checkout even when a webhook is late or never configured.
  """
  @behaviour BaconStore.Payments.Provider

  alias BaconStore.Payments.Event

  @api "https://api.stripe.com/v1"
  # Stripe's default: refuse signatures older than five minutes (replays).
  @tolerance_seconds 300
  # How long a Checkout Session stays payable. Stripe's minimum is 30 minutes after creation;
  # a minute more so a slow request never lands under it.
  @session_minutes 31

  @doc "Minutes a checkout stays open."
  def session_minutes, do: @session_minutes

  @impl true
  def name, do: "stripe"

  @impl true
  def available?, do: is_binary(secret_key()) and secret_key() != ""

  # App config wins (tests set it); otherwise the environment, at runtime.
  defp config, do: Application.get_env(:bacon8, __MODULE__, [])
  defp secret_key, do: config()[:secret_key] || BaconStore.Payments.env("STRIPE_SECRET_KEY")
  defp webhook_secret, do: config()[:webhook_secret] || BaconStore.Payments.env("STRIPE_WEBHOOK_SECRET")

  # ---------------------------------------------------------------------------
  # Checkout
  # ---------------------------------------------------------------------------

  @impl true
  def create_checkout(order, opts) do
    params = checkout_params(order, opts)

    case post("/checkout/sessions", params, idempotency_key: "checkout-#{opts[:basket_id] || order.id}") do
      {:ok, %{"id" => id, "url" => url} = s} -> {:ok, %{redirect_url: url, provider_ref: id, expires_at: unix(s["expires_at"])}}
      {:ok, other} -> {:error, {:unexpected_response, other}}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc false
  # The Checkout Session form fields for an order, or a basket of them (`opts[:lines]`, one line
  # per item, 2026-10-29). Public for tests.
  def checkout_params(order, opts) do
    lines = opts[:lines] || [%{name: order.product_name, amount_cents: order.amount_cents}]
    meta = %{"order_id" => order.id} |> put_if("basket_id", opts[:basket_id]) |> put_if("order_number", opts[:number] && to_string(opts[:number]))

    %{
      "mode" => "payment",
      "client_reference_id" => opts[:basket_id] || order.id,
      "success_url" => absolute(Keyword.fetch!(opts, :success_url)),
      "cancel_url" => absolute(Keyword.fetch!(opts, :cancel_url)),
      "line_items" =>
        lines
        |> Enum.with_index()
        |> Map.new(fn {line, i} ->
          {Integer.to_string(i),
           %{
             "quantity" => "1",
             "price_data" => %{
               "currency" => order.currency,
               "unit_amount" => Integer.to_string(line.amount_cents),
               "product_data" => %{"name" => line.name}
             }
           }}
        end),
      "metadata" => meta,
      "payment_intent_data" => %{"metadata" => meta},
      "expires_at" => Integer.to_string(opts[:expires_at] || System.system_time(:second) + @session_minutes * 60)
    }
    |> put_if("customer_email", opts[:email])
  end

  defp unix(t) when is_integer(t), do: DateTime.from_unix!(t)
  defp unix(_), do: nil

  # Checkout Session ids only ("cs_test_...", "cs_live_..."): they go into a URL path.
  defp session_id?(ref), do: is_binary(ref) and Regex.match?(~r/\Acs_[A-Za-z0-9_]+\z/, ref)

  @impl true
  def expire_checkout(ref) do
    if session_id?(ref) do
      case post("/checkout/sessions/#{ref}/expire", %{}, []) do
        {:ok, %{"status" => "expired"}} -> :ok
        # Only an open session can be expired: find out what it is instead.
        _ ->
          case checkout_status(ref) do
            {:ok, %{state: :expired}} -> :ok
            {:ok, %{state: state}} when state in [:paid, :processing] -> {:error, :already_paid}
            {:ok, %{state: :open}} -> {:error, :still_open}
            {:error, reason} -> {:error, reason}
          end
      end
    else
      {:error, :bad_ref}
    end
  end

  @impl true
  def checkout_status(ref) do
    if session_id?(ref) do
      case request(:get, "/checkout/sessions/#{ref}", nil, []) do
        {:ok, %{} = s} -> {:ok, session_state(s)}
        {:error, reason} -> {:error, reason}
      end
    else
      {:error, :bad_ref}
    end
  end

  @doc false
  # Public for tests.
  def session_state(s) do
    state =
      case {s["status"], s["payment_status"]} do
        {"complete", p} when p in ["paid", "no_payment_required"] -> :paid
        {"complete", _} -> :processing
        {"expired", _} -> :expired
        _ -> :open
      end

    %{state: state, amount_cents: s["amount_total"], currency: s["currency"], payment_ref: s["payment_intent"]}
  end

  defp put_if(map, _key, nil), do: map
  defp put_if(map, key, value), do: Map.put(map, key, value)

  defp absolute("/" <> _ = path), do: Bacon8Web.Endpoint.url() <> path
  defp absolute(url), do: url

  defp post(path, params, opts), do: request(:post, path, params, opts)

  defp request(method, path, params, opts) do
    headers =
      [
        {"authorization", "Bearer " <> (secret_key() || "")},
        {"content-type", "application/x-www-form-urlencoded"}
      ] ++ if(key = opts[:idempotency_key], do: [{"idempotency-key", key}], else: [])

    body = if method == :get, do: nil, else: Plug.Conn.Query.encode(params || %{})
    request = Finch.build(method, @api <> path, headers, body)

    case Finch.request(request, Bacon8.Finch, receive_timeout: 20_000) do
      {:ok, %Finch.Response{status: status, body: body}} when status in 200..299 ->
        Jason.decode(body)

      {:ok, %Finch.Response{status: status, body: body}} ->
        message =
          case Jason.decode(body) do
            {:ok, %{"error" => %{"message" => m}}} -> m
            _ -> body
          end

        {:error, {:stripe, status, message}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ---------------------------------------------------------------------------
  # Webhooks
  # ---------------------------------------------------------------------------

  @impl true
  def parse_webhook(raw_body, headers) do
    with {:ok, signature} <- header(headers, "stripe-signature"),
         :ok <- verify(raw_body, signature, webhook_secret(), System.system_time(:second)),
         {:ok, %{} = event} <- Jason.decode(raw_body) do
      event_from_payload(event)
    else
      {:error, reason} -> {:error, reason}
      {:ok, _} -> {:error, :malformed_event}
    end
  end

  @impl true
  @doc "An event from its decoded JSON (a verified webhook, or one stored in payment_events)."
  def event_from_payload(%{"id" => event_id, "type" => type} = event),
    do: to_event(event_id, type, get_in(event, ["data", "object"]) || %{}, event)

  def event_from_payload(_), do: {:error, :malformed_event}

  defp header(headers, name) do
    case Enum.find(headers, fn {k, _} -> String.downcase(k) == name end) do
      {_, value} -> {:ok, value}
      nil -> {:error, :missing_signature}
    end
  end

  @doc false
  # Stripe-Signature: t=<unix>,v1=<hex hmac>[,v1=...]. The signed payload is
  # "<t>.<raw body>". Public for tests.
  def verify(_raw, _signature, secret, _now) when secret in [nil, ""], do: {:error, :no_webhook_secret}

  def verify(raw_body, signature, secret, now) do
    parts = signature |> String.split(",") |> Enum.map(&String.split(&1, "=", parts: 2))
    timestamp = Enum.find_value(parts, fn [k, v] -> k == "t" && v; _ -> nil end)
    candidates = for [k, v] <- parts, k == "v1", do: v

    with t when is_binary(t) <- timestamp,
         {ts, ""} <- Integer.parse(t),
         true <- abs(now - ts) <= @tolerance_seconds || {:error, :stale_signature} do
      expected = :crypto.mac(:hmac, :sha256, secret, t <> "." <> raw_body) |> Base.encode16(case: :lower)

      if Enum.any?(candidates, &Plug.Crypto.secure_compare(&1, expected)),
        do: :ok,
        else: {:error, :bad_signature}
    else
      {:error, reason} -> {:error, reason}
      _ -> {:error, :bad_signature}
    end
  end

  # A paid session. "unpaid" means a delayed method (bank debit) still clearing:
  # its outcome arrives as async_payment_succeeded / _failed.
  defp to_event(id, "checkout.session.completed", %{"payment_status" => status} = s, raw) when status in ["paid", "no_payment_required"],
    do: {:ok, checkout_event(:checkout_completed, id, s, raw)}

  defp to_event(id, "checkout.session.async_payment_succeeded", s, raw), do: {:ok, checkout_event(:checkout_completed, id, s, raw)}
  defp to_event(id, "checkout.session.async_payment_failed", s, raw), do: {:ok, checkout_event(:checkout_failed, id, s, raw)}
  defp to_event(id, "checkout.session.expired", s, raw), do: {:ok, checkout_event(:checkout_failed, id, s, raw)}

  defp to_event(id, "charge.dispute.created", d, raw), do: {:ok, dispute_event(:dispute_opened, id, d, raw)}

  defp to_event(id, "charge.dispute.closed", %{"status" => status} = d, raw) do
    case status do
      "won" -> {:ok, dispute_event(:dispute_won, id, d, raw)}
      "lost" -> {:ok, dispute_event(:dispute_lost, id, d, raw)}
      # warning_closed etc.: nothing changes for the order.
      _ -> :ignore
    end
  end

  defp to_event(_id, _type, _object, _raw), do: :ignore

  defp checkout_event(type, id, s, raw) do
    %Event{
      type: type,
      provider: name(),
      provider_event_id: id,
      provider_ref: s["id"],
      payment_ref: s["payment_intent"],
      amount_cents: s["amount_total"],
      currency: s["currency"],
      raw: raw
    }
  end

  # Disputes name the PaymentIntent, not the Checkout Session; the order stored
  # it when it was paid.
  defp dispute_event(type, id, d, raw) do
    %Event{type: type, provider: name(), provider_event_id: id, provider_ref: nil, payment_ref: d["payment_intent"], raw: raw}
  end
end

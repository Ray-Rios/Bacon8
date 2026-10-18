defmodule Bacon8.Payments.Stripe do
  @moduledoc """
  Stripe, through hosted Checkout (BACON8.md §8). Card details go to
  Stripe's page, never to the hub.

  Talks to Stripe's REST API directly over `Bacon8.Finch` (no SDK): one call
  to create a Checkout Session, and webhook signatures checked here with
  HMAC-SHA256, as Stripe documents.

  Settings (runtime.exs, from the environment):

    * `STRIPE_SECRET_KEY` - `sk_test_...` or `sk_live_...`. Without it the
      provider reports itself unavailable.
    * `STRIPE_WEBHOOK_SECRET` - `whsec_...`, from the webhook endpoint in the
      Stripe dashboard (or `stripe listen` locally).

  Webhook URL: `/api/webhooks/payments/stripe`, subscribed to
  `checkout.session.completed`, `checkout.session.async_payment_succeeded`,
  `checkout.session.async_payment_failed`, `checkout.session.expired`,
  `charge.dispute.created` and `charge.dispute.closed`.
  """
  @behaviour Bacon8.Payments.Provider

  alias Bacon8.Payments.Event

  @api "https://api.stripe.com/v1"
  # Stripe's default: refuse signatures older than five minutes (replays).
  @tolerance_seconds 300

  @impl true
  def name, do: "stripe"

  @impl true
  def available?, do: is_binary(secret_key()) and secret_key() != ""

  defp config, do: Application.get_env(:bacon8, __MODULE__, [])
  defp secret_key, do: config()[:secret_key]
  defp webhook_secret, do: config()[:webhook_secret]

  # ---------------------------------------------------------------------------
  # Checkout
  # ---------------------------------------------------------------------------

  @impl true
  def create_checkout(order, opts) do
    params = checkout_params(order, opts)

    case post("/checkout/sessions", params, idempotency_key: "checkout-#{order.id}") do
      {:ok, %{"id" => id, "url" => url}} -> {:ok, %{redirect_url: url, provider_ref: id}}
      {:ok, other} -> {:error, {:unexpected_response, other}}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc false
  # The Checkout Session form fields for an order. Public for tests.
  def checkout_params(order, opts) do
    %{
      "mode" => "payment",
      "client_reference_id" => order.id,
      "success_url" => absolute(Keyword.fetch!(opts, :success_url)),
      "cancel_url" => absolute(Keyword.fetch!(opts, :cancel_url)),
      "line_items" => %{
        "0" => %{
          "quantity" => "1",
          "price_data" => %{
            "currency" => order.currency,
            "unit_amount" => Integer.to_string(order.amount_cents),
            "product_data" => %{"name" => order.product_name}
          }
        }
      },
      "metadata" => %{"order_id" => order.id},
      "payment_intent_data" => %{"metadata" => %{"order_id" => order.id}}
    }
  end

  defp absolute("/" <> _ = path), do: Bacon8Web.Endpoint.url() <> path
  defp absolute(url), do: url

  defp post(path, params, opts) do
    headers =
      [
        {"authorization", "Bearer " <> (secret_key() || "")},
        {"content-type", "application/x-www-form-urlencoded"}
      ] ++ if(key = opts[:idempotency_key], do: [{"idempotency-key", key}], else: [])

    request = Finch.build(:post, @api <> path, headers, Plug.Conn.Query.encode(params))

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

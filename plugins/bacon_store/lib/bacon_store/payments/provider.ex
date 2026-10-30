defmodule BaconStore.Payments.Provider do
  @moduledoc """
  A payment provider (BACON8.md §8). Hosted checkout only: card details
  never touch the hub. Stripe and PayPal will implement this;
  `BaconStore.Payments.Fake` does for development and tests.

  There is deliberately no refund callback: sales are final.
  """
  alias BaconStore.Store.Order

  @doc "The provider's name, as stored on orders and events (\"stripe\")."
  @callback name() :: String.t()

  @doc """
  Starts a hosted checkout for an order. `opts` has `:success_url` and
  `:cancel_url`. Returns where to send the buyer and the provider's reference
  for this checkout (matched against later events).
  """
  @callback create_checkout(%Order{}, opts :: keyword()) ::
              {:ok, %{redirect_url: String.t(), provider_ref: String.t()}} | {:error, term()}

  @doc """
  Checks a webhook's signature against its raw body and turns it into an
  event, or `:ignore` for event types the hub doesn't use.
  """
  @callback parse_webhook(raw_body :: binary(), headers :: [{String.t(), String.t()}]) ::
              {:ok, BaconStore.Payments.Event.t()} | :ignore | {:error, term()}

  @doc "Is it configured (keys present)? Assumed true when not implemented."
  @callback available?() :: boolean()

  @doc """
  Rebuilds an event from the payload stored in `payment_events` (no signature
  check: it was checked when it arrived). Used to re-apply an event that came
  before the event it depends on. Providers without it are never replayed.
  """
  @callback event_from_payload(payload :: map()) :: {:ok, BaconStore.Payments.Event.t()} | :ignore | {:error, term()}

  @doc """
  Closes an open checkout so it can no longer be paid (2026-10-29c). `:ok` (closed, or already
  closed unpaid), `{:error, :already_paid}`, or `{:error, reason}` (couldn't reach the provider).
  """
  @callback expire_checkout(provider_ref :: String.t()) :: :ok | {:error, term()}

  @doc """
  Asks the provider where a checkout stands (2026-10-29c), so the hub never has to wait for a
  webhook to be right: `{:ok, %{state: :open | :paid | :processing | :expired, amount_cents:,
  currency:, payment_ref:}}` or `{:error, reason}`.
  """
  @callback checkout_status(provider_ref :: String.t()) :: {:ok, map()} | {:error, term()}

  @optional_callbacks available?: 0, event_from_payload: 1, expire_checkout: 1, checkout_status: 1
end

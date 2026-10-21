defmodule BaconStore.Payments.Event do
  @moduledoc """
  A provider event, normalised. Providers turn their own webhooks into these;
  `BaconStore.Store` only ever sees this shape.

  `provider_ref` is the checkout's reference (Stripe: the Checkout Session
  id); `payment_ref` is the payment's (Stripe: the PaymentIntent id), which
  disputes name instead. An order is found by whichever is present.

  `type`:
    * `:checkout_completed` - money taken for the checkout `provider_ref`
    * `:checkout_failed` - checkout expired or payment failed
    * `:dispute_opened`, `:dispute_won`, `:dispute_lost` - a chargeback's progress
  """
  @enforce_keys [:type, :provider, :provider_event_id, :provider_ref]
  defstruct [:type, :provider, :provider_event_id, :provider_ref, :payment_ref, :amount_cents, :currency, raw: %{}]

  @type t :: %__MODULE__{
          type: :checkout_completed | :checkout_failed | :dispute_opened | :dispute_won | :dispute_lost,
          provider: String.t(),
          provider_event_id: String.t(),
          provider_ref: String.t() | nil,
          payment_ref: String.t() | nil,
          amount_cents: integer() | nil,
          currency: String.t() | nil,
          raw: map()
        }
end

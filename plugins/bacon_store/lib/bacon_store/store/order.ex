defmodule BaconStore.Store.Order do
  @moduledoc """
  One purchase. Status moves only through `BaconStore.Store`:

      awaiting_payment -> paid -> fulfilled
                       -> failed | cancelled
      fulfilled -> disputed -> fulfilled (won) | charged_back (lost)

  An order left at "paid" with a `failure_reason` was paid for but couldn't
  be delivered (a license key product ran out, say); an admin fixes the cause
  and retries delivery from /admin/bacon_store/orders. A Gem purchase is created already
  paid and fulfilled in one transaction.

  There is no refunded state: sales are final (BACON8.md §2).

  **Baskets** (2026-10-29): a purchase of several items is several orders, one per item, sharing a
  `basket_id` and a `number` (the receipt's "Order #8008"; `BaconStore.Store.Basket`). A card
  basket is one checkout, so its orders also share `provider_ref`. A single purchase is a basket
  of one.

  **Unfinished checkouts** (2026-10-29c): a card basket is "awaiting_payment" only while its
  provider checkout is open (30 minutes). Starting another checkout, cancelling, coming back
  through the provider's cancel link, or the checkout closing all settle it: "cancelled" or
  "failed" with `paid_at` nil, which the buyer's Purchases leaves out (it was never a purchase).
  """
  use Ecto.Schema

  @statuses ~w(awaiting_payment paid fulfilled failed cancelled disputed charged_back)
  def statuses, do: @statuses

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "store_orders" do
    field :status, :string
    field :provider, :string
    field :provider_ref, :string
    field :provider_payment_ref, :string
    field :product_name, :string
    # A card order has amount_cents and currency; a Gem order (provider
    # "gems") has amount_gems and currency "gems".
    field :amount_cents, :integer
    field :amount_gems, :integer
    field :currency, :string
    field :gems, :integer, default: 0
    field :terms_accepted_at, :utc_datetime_usec
    field :paid_at, :utc_datetime_usec
    field :fulfilled_at, :utc_datetime_usec
    field :failure_reason, :string
    field :basket_id, :binary_id
    field :number, :integer
    # A card basket's open checkout (2026-10-29c): where to send the buyer to finish paying, and
    # when the provider closes it.
    field :checkout_url, :string
    field :checkout_expires_at, :utc_datetime_usec
    belongs_to :user, Bacon8.Accounts.User
    belongs_to :product, BaconStore.Store.Product
    timestamps(type: :utc_datetime_usec)
  end
end

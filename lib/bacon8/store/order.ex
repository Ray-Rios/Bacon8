defmodule Bacon8.Store.Order do
  @moduledoc """
  One purchase. Status moves only through `Bacon8.Store`:

      awaiting_payment -> paid -> fulfilled
                       -> failed | cancelled
      fulfilled -> disputed -> fulfilled (won) | charged_back (lost)

  An order left at "paid" with a `failure_reason` was paid for but couldn't
  be delivered (a license key product ran out, say); an admin fixes the cause
  and retries delivery from /admin/orders. A Gem purchase is created already
  paid and fulfilled in one transaction.

  There is no refunded state: sales are final (BACON8.md §2).
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
    belongs_to :user, Bacon8.Accounts.User
    belongs_to :product, Bacon8.Store.Product
    timestamps(type: :utc_datetime_usec)
  end
end

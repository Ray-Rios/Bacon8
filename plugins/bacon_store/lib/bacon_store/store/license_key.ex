defmodule BaconStore.Store.LicenseKey do
  @moduledoc """
  One code from a `license_key` product's pool.

    * available: no `order_id`
    * reserved: `order_id` set, `sold_at` empty (a card checkout in progress)
    * sold: `sold_at` and `user_id` set
    * revoked: sold, then charged back (`revoked_at`)
  """
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "store_license_keys" do
    field :code, :string
    field :reserved_at, :utc_datetime_usec
    field :sold_at, :utc_datetime_usec
    field :revoked_at, :utc_datetime_usec
    belongs_to :product, BaconStore.Store.Product
    belongs_to :order, BaconStore.Store.Order
    belongs_to :user, Bacon8.Accounts.User
    timestamps(type: :utc_datetime_usec)
  end
end

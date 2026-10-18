defmodule Bacon8.Wallet.Account do
  @moduledoc "A wallet account: a user's, or a system account (`gem_sales`, `gem_spend`, ...)."
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "wallet_accounts" do
    field :owner_type, :string
    field :name, :string
    field :currency, :string
    field :balance, :integer, default: 0
    belongs_to :user, Bacon8.Accounts.User
    timestamps(type: :utc_datetime_usec)
  end
end

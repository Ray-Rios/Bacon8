defmodule Bacon8.Wallet.Entry do
  @moduledoc "One leg of a ledger transaction: a signed amount on one account."
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "wallet_entries" do
    field :amount, :integer
    field :inserted_at, :utc_datetime_usec
    belongs_to :transaction, Bacon8.Wallet.Transaction
    belongs_to :account, Bacon8.Wallet.Account
  end
end

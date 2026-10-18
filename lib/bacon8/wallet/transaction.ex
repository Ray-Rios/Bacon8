defmodule Bacon8.Wallet.Transaction do
  @moduledoc "One ledger transaction. Its entries sum to zero."
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "wallet_transactions" do
    field :kind, :string
    field :idempotency_key, :string
    field :reference_type, :string
    field :reference_id, :string
    field :game_slug, :string
    field :memo, :string
    field :actor_id, :binary_id
    field :inserted_at, :utc_datetime_usec
    has_many :entries, Bacon8.Wallet.Entry
  end
end

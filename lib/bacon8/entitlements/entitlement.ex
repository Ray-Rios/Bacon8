defmodule Bacon8.Entitlements.Entitlement do
  @moduledoc "Something a user has been granted. See `Bacon8.Entitlements`."
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "entitlements" do
    field :kind, :string
    field :key, :string
    field :quantity, :integer
    field :source_type, :string
    field :source_id, :string
    field :starts_at, :utc_datetime_usec
    field :ends_at, :utc_datetime_usec
    field :revoked_at, :utc_datetime_usec
    field :revoked_reason, :string
    belongs_to :user, Bacon8.Accounts.User
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(entitlement, attrs) do
    entitlement
    |> cast(attrs, [:user_id, :kind, :key, :quantity, :source_type, :source_id, :starts_at, :ends_at])
    |> validate_required([:user_id, :kind, :key, :source_type, :starts_at])
    |> validate_number(:quantity, greater_than: 0)
    |> foreign_key_constraint(:user_id)
  end
end

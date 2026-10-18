defmodule Bacon8.Security.AllowedIdentifier do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "allowed_identifiers" do
    field :identifier, :string
    field :identifier_type, :string
    field :reason, :string
    field :added_at, :utc_datetime
    
    belongs_to :added_by_user, Bacon8.Accounts.User

    timestamps(type: :utc_datetime)
  end

  def changeset(allowed_identifier, attrs) do
    allowed_identifier
    |> cast(attrs, [:identifier, :identifier_type, :reason, :added_at, :added_by_user_id])
    |> validate_required([:identifier, :identifier_type, :added_at])
    |> validate_inclusion(:identifier_type, ["ip", "fingerprint"])
    |> unique_constraint([:identifier, :identifier_type])
  end
end

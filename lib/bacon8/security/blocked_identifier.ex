defmodule Bacon8.Security.BlockedIdentifier do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "blocked_identifiers" do
    field :identifier, :string
    field :identifier_type, :string
    field :reason, :string
    field :blocked_at, :utc_datetime
    field :expires_at, :utc_datetime
    field :auto_blocked, :boolean, default: false
    
    belongs_to :blocked_by_user, Bacon8.Accounts.User

    timestamps(type: :utc_datetime)
  end

  def changeset(blocked_identifier, attrs) do
    blocked_identifier
    |> cast(attrs, [:identifier, :identifier_type, :reason, :blocked_at, 
                    :expires_at, :auto_blocked, :blocked_by_user_id])
    |> validate_required([:identifier, :identifier_type, :blocked_at])
    |> validate_inclusion(:identifier_type, ["ip", "fingerprint"])
    |> unique_constraint([:identifier, :identifier_type])
  end
end

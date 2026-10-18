defmodule Bacon8.Security.DeviceFingerprint do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "device_fingerprints" do
    field :fingerprint_hash, :string
    field :user_agent, :string
    field :platform, :string
    field :first_seen_at, :utc_datetime
    field :last_seen_at, :utc_datetime
    field :trusted, :boolean, default: false
    field :metadata, :map
    
    belongs_to :user, Bacon8.Accounts.User
    has_many :behavioral_data, Bacon8.Security.BehavioralData

    timestamps(type: :utc_datetime)
  end

  def changeset(device_fingerprint, attrs) do
    device_fingerprint
    |> cast(attrs, [:fingerprint_hash, :user_agent, :platform, :first_seen_at, 
                    :last_seen_at, :trusted, :metadata, :user_id])
    |> validate_required([:fingerprint_hash, :first_seen_at, :last_seen_at])
    |> unique_constraint(:fingerprint_hash)
  end
end

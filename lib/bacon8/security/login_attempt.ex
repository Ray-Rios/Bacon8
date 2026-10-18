defmodule Bacon8.Security.LoginAttempt do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "login_attempts" do
    field :identifier, :string
    field :identifier_type, :string
    field :attempt_count, :integer, default: 0
    field :last_attempt_at, :utc_datetime
    field :ip_address, :string
    field :user_agent, :string
    field :successful, :boolean, default: false
    
    belongs_to :user, Bacon8.Accounts.User

    timestamps(type: :utc_datetime)
  end

  def changeset(login_attempt, attrs) do
    login_attempt
    |> cast(attrs, [:identifier, :identifier_type, :attempt_count, :last_attempt_at, 
                    :ip_address, :user_agent, :successful, :user_id])
    |> validate_required([:identifier, :identifier_type])
    |> validate_inclusion(:identifier_type, ["ip", "fingerprint"])
  end
end

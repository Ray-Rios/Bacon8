defmodule Bacon8.Push.Subscription do
  @moduledoc "One device that gets push notifications for a user. See `Bacon8.Push`."
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "push_subscriptions" do
    belongs_to :user, Bacon8.Accounts.User
    field :endpoint, :string
    field :p256dh, :string
    field :auth, :string
    field :user_agent, :string
    field :previews, :boolean, default: true
    field :failures, :integer, default: 0
    field :last_used_at, :utc_datetime
    timestamps(type: :utc_datetime)
  end

  def changeset(sub, attrs) do
    sub
    |> cast(attrs, [:user_id, :endpoint, :p256dh, :auth, :user_agent, :previews])
    |> validate_required([:user_id, :endpoint, :p256dh, :auth])
    |> update_change(:user_agent, &(&1 && String.slice(&1, 0, 250)))
    |> validate_length(:endpoint, max: 2000)
    |> unique_constraint(:endpoint)
    |> foreign_key_constraint(:user_id)
  end
end

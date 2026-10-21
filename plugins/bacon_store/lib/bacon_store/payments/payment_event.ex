defmodule BaconStore.Payments.PaymentEvent do
  @moduledoc "The event inbox: every provider event, stored before it's processed."
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "payment_events" do
    field :provider, :string
    field :provider_event_id, :string
    field :event_type, :string
    field :payload, :map, default: %{}
    field :processed_at, :utc_datetime_usec
    field :error, :string
    field :inserted_at, :utc_datetime_usec
  end
end

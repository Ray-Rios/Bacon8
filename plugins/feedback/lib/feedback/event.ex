defmodule Feedback.Event do
  @moduledoc "One line of an item's history: a status change or a note, by a person or by Claude's runner."
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "feedback_events" do
    belongs_to(:item, Feedback.Item)
    belongs_to(:actor, Bacon8.Accounts.User)
    field(:actor_kind, :string, default: "user")
    field(:from_status, :string)
    field(:to_status, :string)
    field(:note, :string)
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end
end

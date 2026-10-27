defmodule Feedback.Shot do
  @moduledoc "A screenshot attached to an item. The body is in `Bacon8.Storage` under its SHA-256."
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "feedback_shots" do
    belongs_to(:item, Feedback.Item)
    field(:sha256, :string)
    field(:filename, :string)
    field(:content_type, :string)
    field(:byte_size, :integer)
    field(:position, :integer, default: 0)
    timestamps(type: :utc_datetime_usec)
  end
end

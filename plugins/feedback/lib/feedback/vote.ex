defmodule Feedback.Vote do
  @moduledoc "One member's up (+1) or down (-1) vote on an item."
  use Ecto.Schema

  @primary_key false
  @foreign_key_type :binary_id
  schema "feedback_votes" do
    belongs_to(:item, Feedback.Item, primary_key: true)
    belongs_to(:user, Bacon8.Accounts.User, primary_key: true)
    field(:value, :integer)
    timestamps(type: :utc_datetime_usec)
  end
end

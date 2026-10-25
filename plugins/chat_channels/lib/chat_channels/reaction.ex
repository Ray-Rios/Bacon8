defmodule ChatChannels.Reaction do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "chat_reactions" do
    field :emoji, :string

    belongs_to :message, ChatChannels.Message
    belongs_to :user, Bacon8.Accounts.User

    timestamps(type: :utc_datetime)
  end

  def changeset(reaction, attrs) do
    reaction
    |> cast(attrs, [:emoji, :message_id, :user_id])
    |> validate_required([:emoji])
    |> unique_constraint([:message_id, :user_id, :emoji])
  end
end
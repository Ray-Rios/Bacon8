defmodule ChatChannels.Thread do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "chat_threads" do
    field :name, :string
    field :is_archived, :boolean, default: false

    belongs_to :channel, ChatChannels.Channel
    belongs_to :message, ChatChannels.Message
    belongs_to :user, Bacon8.Accounts.User
    has_many :messages, ChatChannels.Message

    timestamps(type: :utc_datetime)
  end

  def changeset(thread, attrs) do
    thread
    |> cast(attrs, [:name, :is_archived])
    |> validate_length(:name, max: 100)
  end
end
defmodule ChatChannels.Message do
  use Ecto.Schema
  use Arc.Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "chat_messages" do
    field :content, :string
    field :message_type, :string, default: "text" # text, image, file, system
    field :edited_at, :utc_datetime
    field :is_pinned, :boolean, default: false

    belongs_to :user, Bacon8.Accounts.User
    belongs_to :channel, ChatChannels.Channel
    belongs_to :thread, ChatChannels.Thread, on_replace: :nilify
    belongs_to :reply_to, ChatChannels.Message, on_replace: :nilify

    has_many :reactions, ChatChannels.Reaction
    has_many :attachments, ChatChannels.MessageAttachment
    has_one :created_thread, ChatChannels.Thread, foreign_key: :message_id
    has_many :replies, ChatChannels.Message, foreign_key: :reply_to_id, preload_order: [asc: :inserted_at]

    timestamps(type: :utc_datetime)
  end

  def changeset(message, attrs) do
    message
    |> cast(attrs, [:content, :message_type, :is_pinned, :reply_to_id, :thread_id, :channel_id, :user_id])
    |> validate_required([:content])
    |> validate_length(:content, min: 1, max: 2000)
    |> validate_inclusion(:message_type, ["text", "image", "file", "system"])
  end
end
defmodule ChatChannels.MessageAttachment do
  use Ecto.Schema
  use Arc.Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "chat_message_attachments" do
    field :filename, :string
    field :content_type, :string
    field :file_size, :integer
    field :file, :string

    belongs_to :message, ChatChannels.Message
    belongs_to :channel, ChatChannels.Channel
    # Optional: keep track of which user uploaded this attachment
    belongs_to :user, Bacon8.Accounts.User

    timestamps(type: :utc_datetime)
  end

  def changeset(attachment, attrs) do
    attachment
    |> cast(attrs, [:filename, :content_type, :file_size, :file, :message_id, :channel_id, :user_id])
    |> validate_required([:filename, :content_type, :file_size, :file])
  end
end
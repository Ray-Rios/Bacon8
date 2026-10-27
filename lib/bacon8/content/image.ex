defmodule Bacon8.Content.Image do
  @moduledoc "A picture in the image library (see `Bacon8.Content.Library`)."
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "content_images" do
    field :url, :string
    field :filename, :string
    field :context, :string
    field :sha256, :string
    field :byte_size, :integer
    field :mime_type, :string

    belongs_to :user, Bacon8.Accounts.User

    timestamps(type: :utc_datetime, updated_at: false)
  end
end

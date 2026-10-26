defmodule Bacon8.Content.Revision do
  @moduledoc "An earlier version of a page or post (see `Bacon8.Content.Revisions`)."
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "content_revisions" do
    field :kind, :string
    field :record_id, :binary_id
    field :title, :string
    field :excerpt, :string
    field :content, :string

    belongs_to :user, Bacon8.Accounts.User

    timestamps(type: :utc_datetime, updated_at: false)
  end
end

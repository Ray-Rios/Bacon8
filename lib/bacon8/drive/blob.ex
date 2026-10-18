defmodule Bacon8.Drive.Blob do
  @moduledoc "A file body, stored once per distinct SHA-256. See `Bacon8.Storage`."
  use Ecto.Schema

  @primary_key {:sha256, :string, autogenerate: false}
  schema "drive_blobs" do
    field :size, :integer
    field :content_type, :string
    field :last_referenced_at, :utc_datetime_usec
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end
end

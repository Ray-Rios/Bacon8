defmodule Bacon8.Content.UserMedia do
  @moduledoc "Schema for user uploaded media assets"
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "user_media" do
    field :filename, :string
    field :original_filename, :string
    field :file_type, :string
    field :mime_type, :string
    field :file_size, :integer
    field :file_path, :string
    field :folder_path, :string, default: "/"  # Virtual folder path for organization
    field :url, :string
    field :metadata, :map
    field :alt_text, :string
    field :caption, :string
    field :usage_context, :string
    field :is_public, :boolean, default: false

    belongs_to :user, Bacon8.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @required ~w(filename original_filename file_type mime_type file_size file_path url)a

  def changeset(media, attrs) do
    media
    |> cast(attrs, [
      :filename,
      :original_filename,
      :file_type,
      :mime_type,
      :file_size,
      :file_path,
      :folder_path,
      :url,
      :metadata,
      :alt_text,
      :caption,
      :usage_context,
      :is_public,
      :user_id
    ])
    |> validate_required(@required)
    |> validate_inclusion(:file_type, ["image", "video", "audio", "3d", "document"])
    |> normalize_folder_path()
  end
  
  # Ensure folder path starts with / and has no trailing slash (except for root)
  defp normalize_folder_path(changeset) do
    case get_change(changeset, :folder_path) do
      nil -> changeset
      path ->
        normalized = path
          |> String.trim()
          |> ensure_leading_slash()
          |> remove_trailing_slash()
        put_change(changeset, :folder_path, normalized)
    end
  end
  
  defp ensure_leading_slash(""), do: "/"
  defp ensure_leading_slash("/" <> _ = path), do: path
  defp ensure_leading_slash(path), do: "/" <> path
  
  defp remove_trailing_slash("/"), do: "/"
  defp remove_trailing_slash(path) do
    String.trim_trailing(path, "/")
  end
end

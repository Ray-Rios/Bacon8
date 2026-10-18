defmodule Bacon8.Files.UserFile do
  use Ecto.Schema
  use Arc.Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "user_files" do
    field :filename, :string
    field :original_filename, :string
    field :content_type, :string
    field :file_size, :integer
    field :file_path, :string
    field :folder_path, :string, default: "/"  # Virtual folder path for organization
    field :file, Bacon8.UserFileUpload.Type
    field :is_public, :boolean, default: false
    field :description, :string
    field :tags, {:array, :string}, default: []

    belongs_to :user, Bacon8.Accounts.User

    timestamps(type: :utc_datetime)
  end

  def changeset(user_file, attrs) do
    user_file
    |> cast(attrs, [:filename, :original_filename, :content_type, :file_size, :file_path, :folder_path, :is_public, :description, :tags])
    |> cast_attachments(attrs, [:file])
    |> validate_required([:filename, :content_type, :file_size])
    |> validate_number(:file_size, greater_than: 0)
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

  def is_image?(%__MODULE__{content_type: content_type}) do
    String.starts_with?(content_type, "image/")
  end

  def is_video?(%__MODULE__{content_type: content_type}) do
    String.starts_with?(content_type, "video/")
  end

  def is_audio?(%__MODULE__{content_type: content_type}) do
    String.starts_with?(content_type, "audio/")
  end

  def is_document?(%__MODULE__{content_type: content_type}) do
    content_type in ["application/pdf", "application/msword", "text/plain", "application/vnd.openxmlformats-officedocument.wordprocessingml.document"]
  end

  def format_file_size(size_bytes) when is_integer(size_bytes) do
    cond do
      size_bytes >= 1_073_741_824 -> "#{Float.round(size_bytes / 1_073_741_824, 2)} GB"
      size_bytes >= 1_048_576 -> "#{Float.round(size_bytes / 1_048_576, 2)} MB"
      size_bytes >= 1024 -> "#{Float.round(size_bytes / 1024, 2)} KB"
      true -> "#{size_bytes} B"
    end
  end

  def format_file_size(_), do: "0 B"
end
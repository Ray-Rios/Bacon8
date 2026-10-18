defmodule Bacon8.Files.UserFolder do
  @moduledoc """
  Schema for virtual user folders. These are organizational folders that
  don't correspond to actual filesystem directories - they just organize
  files in the database.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "user_folders" do
    field :name, :string
    field :path, :string
    field :parent_path, :string, default: "/"
    field :color, :string
    field :icon, :string

    belongs_to :user, Bacon8.Accounts.User

    timestamps(type: :utc_datetime)
  end

  def changeset(folder, attrs) do
    folder
    |> cast(attrs, [:name, :path, :parent_path, :color, :icon, :user_id])
    |> validate_required([:name, :path, :user_id])
    |> validate_length(:name, min: 1, max: 255)
    |> validate_format(:name, ~r/^[^\/\\:*?"<>|]+$/, message: "cannot contain special characters")
    |> normalize_paths()
    |> unique_constraint([:user_id, :path], name: :user_folders_user_path_unique)
  end

  defp normalize_paths(changeset) do
    changeset
    |> normalize_path(:path)
    |> normalize_path(:parent_path)
  end

  defp normalize_path(changeset, field) do
    case get_change(changeset, field) do
      nil -> changeset
      path ->
        normalized = path
          |> String.trim()
          |> ensure_leading_slash()
          |> remove_trailing_slash()
        put_change(changeset, field, normalized)
    end
  end

  defp ensure_leading_slash(""), do: "/"
  defp ensure_leading_slash("/" <> _ = path), do: path
  defp ensure_leading_slash(path), do: "/" <> path

  defp remove_trailing_slash("/"), do: "/"
  defp remove_trailing_slash(path), do: String.trim_trailing(path, "/")

  @doc "Generate full path from parent path and folder name"
  def build_path("/", name), do: "/" <> name
  def build_path(parent_path, name), do: parent_path <> "/" <> name
end

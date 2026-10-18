defmodule Bacon8.Drive.File do
  @moduledoc """
  A named file in a user's drive, pointing at a content-addressed blob.

  `visibility`:
    * `"private"` - owner and staff only
    * `"link"`    - also anyone holding `share_token` (via `/s/:token`)
    * `"public"`  - anyone, via `/files/:id`
  """
  use Ecto.Schema
  import Ecto.Changeset

  @visibilities ~w(private link public)

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "drive_files" do
    field :name, :string
    field :size, :integer
    field :content_type, :string
    field :visibility, :string, default: "private"
    field :share_token, :string, redact: true
    field :legacy_ref, :string
    field :blob_sha256, :string
    belongs_to :owner, Bacon8.Accounts.User
    belongs_to :folder, Bacon8.Drive.Folder
    timestamps(type: :utc_datetime_usec)
  end

  def visibilities, do: @visibilities

  @doc false
  def create_changeset(file, attrs) do
    file
    |> cast(attrs, [:name, :folder_id, :blob_sha256, :size, :content_type, :visibility, :legacy_ref])
    |> validate_required([:name, :blob_sha256, :size, :content_type])
    |> Bacon8.Drive.Names.validate_name(:name)
    |> validate_inclusion(:visibility, @visibilities)
    |> name_constraints()
  end

  @doc false
  def rename_changeset(file, attrs) do
    file
    |> cast(attrs, [:name, :folder_id])
    |> Bacon8.Drive.Names.validate_name(:name)
    |> name_constraints()
  end

  @doc false
  def visibility_changeset(file, visibility, share_token) do
    file
    |> change(visibility: visibility, share_token: share_token)
    |> validate_inclusion(:visibility, @visibilities)
    |> check_constraint(:visibility, name: :drive_files_share_token_check)
  end

  defp name_constraints(changeset) do
    changeset
    |> unique_constraint(:name, name: :drive_files_sibling_name_index, message: "already exists here")
    |> unique_constraint(:name, name: :drive_files_root_name_index, message: "already exists here")
  end
end

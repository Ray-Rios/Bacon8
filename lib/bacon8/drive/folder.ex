defmodule Bacon8.Drive.Folder do
  @moduledoc "A folder in a user's drive. `parent_id` nil means the drive root."
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "drive_folders" do
    field :name, :string
    belongs_to :owner, Bacon8.Accounts.User
    belongs_to :parent, __MODULE__
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(folder, attrs) do
    folder
    |> cast(attrs, [:name, :parent_id])
    |> Bacon8.Drive.Names.validate_name(:name)
    |> unique_constraint(:name, name: :drive_folders_sibling_name_index, message: "already exists here")
    |> unique_constraint(:name, name: :drive_folders_root_name_index, message: "already exists here")
    |> foreign_key_constraint(:parent_id)
  end
end

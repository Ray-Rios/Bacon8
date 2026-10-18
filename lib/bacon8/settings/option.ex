defmodule Bacon8.Settings.Option do
  use Ecto.Schema
  import Ecto.Changeset

  # Use default integer primary key to match the DB
  schema "cms_options" do
    field :option_name, :string
    field :option_value, :string
    field :autoload, :string, default: "yes"

    timestamps()
  end

  def changeset(option, attrs) do
    option
    |> cast(attrs, [:option_name, :option_value, :autoload])
    |> validate_required([:option_name, :option_value])
    |> unique_constraint(:option_name)
  end
end
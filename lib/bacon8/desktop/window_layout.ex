defmodule Bacon8.Desktop.WindowLayout do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "window_layouts" do
    field :app, :string
    field :x, :integer
    field :y, :integer
    field :width, :integer
    field :height, :integer
    field :z_index, :integer
    field :minimized, :boolean
    field :maximized, :boolean
    field :current_path, :string
    field :view_mode, :string
    field :breadcrumbs, {:array, :map}, default: []

    belongs_to :user, Bacon8.Accounts.User

    timestamps(type: :utc_datetime)
  end

  def changeset(layout, attrs) do
    layout
    |> cast(attrs, [:app, :x, :y, :width, :height, :z_index, :minimized, :maximized, :current_path, :view_mode, :breadcrumbs])
    |> validate_required([:app, :x, :y, :width, :height])
    |> validate_inclusion(:x, 0..10000)
    |> validate_inclusion(:y, 0..10000)
    |> validate_inclusion(:width, 200..5000)
    |> validate_inclusion(:height, 150..5000)
  end
end

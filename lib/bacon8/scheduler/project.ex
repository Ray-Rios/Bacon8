defmodule Bacon8.Scheduler.Project do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "projects" do
    field :name, :string
    field :description, :string
    field :status, :string, default: "active"
    field :start_date, :utc_datetime
    field :end_date, :utc_datetime
    field :metadata, :map, default: %{}

    has_many :tasks, Bacon8.Scheduler.Task
    belongs_to :owner, Bacon8.Accounts.User, type: :binary_id

    timestamps(type: :utc_datetime)
  end

  def changeset(project, attrs) do
    project
    |> cast(attrs, [:name, :description, :owner_id, :status, :start_date, :end_date, :metadata])
    |> validate_required([:name])
  end
end

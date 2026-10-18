defmodule Bacon8.Scheduler.Task do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "tasks" do
    field :title, :string
    field :description, :string
    field :assignee_id, :binary_id
    field :status, :string, default: "todo"
    field :percent_complete, :integer, default: 0
    field :duration_seconds, :integer
    field :start_at, :utc_datetime
    field :end_at, :utc_datetime
    field :earliest_start_at, :utc_datetime
    # Computed by Scheduler.Engine (column added 20261015220500).
    field :earliest_finish_at, :utc_datetime
    field :latest_finish_at, :utc_datetime
    field :lock_version, :integer, default: 1

    belongs_to :project, Bacon8.Scheduler.Project, type: :binary_id

    timestamps(type: :utc_datetime)
  end

  def changeset(task, attrs) do
    task
    |> cast(attrs, [:project_id, :title, :description, :assignee_id, :status, :percent_complete, :duration_seconds, :start_at, :end_at, :earliest_start_at, :latest_finish_at])
    |> validate_required([:project_id, :title])
  end
end

defmodule Bacon8.Scheduler.TaskDependency do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "task_dependencies" do
    field :dependency_type, :string, default: "finish-start"
    field :lag_seconds, :integer, default: 0

    belongs_to :task, Bacon8.Scheduler.Task, type: :binary_id
    belongs_to :depends_on_task, Bacon8.Scheduler.Task, type: :binary_id

    timestamps(type: :utc_datetime)
  end

  def changeset(dep, attrs) do
    dep
    |> cast(attrs, [:task_id, :depends_on_task_id, :dependency_type, :lag_seconds])
    |> validate_required([:task_id, :depends_on_task_id])
    |> foreign_key_constraint(:task_id)
    |> foreign_key_constraint(:depends_on_task_id)
  end
end

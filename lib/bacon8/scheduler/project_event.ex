defmodule Bacon8.Scheduler.ProjectEvent do
  @moduledoc """
  Schema for project lifecycle events.
  
  Records when projects/tasks start, complete, or change status.
  Used for:
  - Audit trail of project changes
  - Triggering scheduled events
  - Calendar display
  - Project timeline visualization
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @event_types ~w(project_created project_started project_completed project_archived 
                  task_created task_started task_completed milestone_reached 
                  deadline_approaching deadline_passed)

  schema "project_events" do
    field :event_type, :string
    field :title, :string
    field :description, :string
    field :occurred_at, :utc_datetime
    field :metadata, :map, default: %{}
    
    # Related entities
    field :project_id, :binary_id
    field :task_id, :binary_id
    field :triggered_by_user_id, :binary_id
    
    # Trigger tracking
    field :triggered_events, {:array, :binary_id}, default: []
    
    belongs_to :project, Bacon8.Scheduler.Project, type: :binary_id, define_field: false
    belongs_to :task, Bacon8.Scheduler.Task, type: :binary_id, define_field: false
    belongs_to :triggered_by_user, Bacon8.Accounts.User, type: :binary_id, define_field: false
    
    timestamps(type: :utc_datetime)
  end

  def changeset(event, attrs) do
    event
    |> cast(attrs, [
      :event_type, :title, :description, :occurred_at, :metadata,
      :project_id, :task_id, :triggered_by_user_id, :triggered_events
    ])
    |> validate_required([:event_type, :title, :occurred_at])
    |> validate_inclusion(:event_type, @event_types)
    |> validate_project_or_task()
  end

  defp validate_project_or_task(changeset) do
    project_id = get_field(changeset, :project_id)
    task_id = get_field(changeset, :task_id)
    
    if is_nil(project_id) && is_nil(task_id) do
      add_error(changeset, :project_id, "either project_id or task_id is required")
    else
      changeset
    end
  end

  def event_types, do: @event_types
end

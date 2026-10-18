defmodule Bacon8.Scheduler.ScheduledEventRun do
  @moduledoc """
  Schema for tracking individual runs of scheduled events.
  Provides execution history, debugging, and audit capabilities.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @statuses ~w(running success failed)

  schema "scheduled_event_runs" do
    field :started_at, :utc_datetime
    field :completed_at, :utc_datetime
    field :status, :string, default: "running"
    field :result, :map, default: %{}
    field :error, :string
    field :duration_ms, :integer
    
    belongs_to :scheduled_event, Bacon8.Scheduler.ScheduledEvent

    timestamps(type: :utc_datetime)
  end

  def changeset(run, attrs) do
    run
    |> cast(attrs, [:scheduled_event_id, :started_at, :completed_at, :status, :result, :error, :duration_ms])
    |> validate_required([:scheduled_event_id, :started_at])
    |> validate_inclusion(:status, @statuses)
  end

  def mark_completed(run, status, result \\ %{}, error \\ nil) do
    now = DateTime.utc_now()
    duration = if run.started_at do
      DateTime.diff(now, run.started_at, :millisecond)
    else
      0
    end

    run
    |> changeset(%{
      completed_at: now,
      status: status,
      result: result,
      error: error,
      duration_ms: duration
    })
  end
end

defmodule Bacon8.Scheduler.ScheduledEvent do
  @moduledoc """
  Schema for scheduled events - cron jobs, one-time events, recurring tasks, webhooks.
  
  Event types:
  - "one_time": Executes once at scheduled_at
  - "recurring": Repeats based on cron_expression
  - "webhook": Triggered by external HTTP call
  - "project_trigger": Triggered by project events (start/complete)
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @event_types ~w(one_time recurring webhook project_trigger)
  @statuses ~w(active paused completed failed)
  @actions ~w(http_request create_project complete_project send_email run_script notify)

  schema "scheduled_events" do
    field :title, :string
    field :description, :string
    field :event_type, :string, default: "one_time"
    field :status, :string, default: "active"
    
    # Scheduling
    field :scheduled_at, :utc_datetime
    field :cron_expression, :string  # e.g., "0 9 * * 1" for 9am every Monday
    field :timezone, :string, default: "UTC"
    field :next_run_at, :utc_datetime
    field :last_run_at, :utc_datetime
    field :run_count, :integer, default: 0
    field :max_runs, :integer  # nil = unlimited
    
    # Action configuration
    field :action_type, :string  # http_request, create_project, send_email, etc.
    field :action_config, :map, default: %{}
    # For http_request: %{url: "", method: "POST", headers: %{}, body: %{}}
    # For create_project: %{name: "", template_id: "", owner_id: ""}
    # For send_email: %{to: "", subject: "", template: ""}
    # For notify: %{channel: "", message: ""}
    
    # Webhook configuration
    field :webhook_secret, :string  # For webhook type events
    field :webhook_url, :string     # Auto-generated URL for triggering
    
    # Project integration
    field :trigger_project_id, :binary_id   # Which project triggers this event
    field :trigger_on, :string              # "project_start", "project_complete", "task_complete"
    field :target_project_id, :binary_id    # Which project this event affects
    
    # Ownership
    field :created_by_id, :binary_id
    belongs_to :created_by, Bacon8.Accounts.User, type: :binary_id, define_field: false
    
    # Execution tracking
    field :last_error, :string
    field :metadata, :map, default: %{}
    
    timestamps(type: :utc_datetime)
  end

  def changeset(event, attrs) do
    event
    |> cast(attrs, [
      :title, :description, :event_type, :status,
      :scheduled_at, :cron_expression, :timezone, :next_run_at, :last_run_at,
      :run_count, :max_runs,
      :action_type, :action_config,
      :webhook_secret, :webhook_url,
      :trigger_project_id, :trigger_on, :target_project_id,
      :created_by_id, :last_error, :metadata
    ])
    |> validate_required([:title, :event_type])
    |> validate_inclusion(:event_type, @event_types)
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:action_type, @actions, allow_nil: true)
    |> validate_scheduling()
    |> maybe_generate_webhook_secret()
    |> compute_next_run()
  end

  defp validate_scheduling(changeset) do
    event_type = get_field(changeset, :event_type)
    
    case event_type do
      "one_time" ->
        validate_required(changeset, [:scheduled_at])
        
      "recurring" ->
        changeset
        |> validate_required([:cron_expression])
        |> validate_cron_expression()
        
      "project_trigger" ->
        changeset
        |> validate_required([:trigger_project_id, :trigger_on])
        |> validate_inclusion(:trigger_on, ~w(project_start project_complete task_complete))
        
      _ ->
        changeset
    end
  end

  defp validate_cron_expression(changeset) do
    cron = get_field(changeset, :cron_expression)
    
    if cron && !valid_cron?(cron) do
      add_error(changeset, :cron_expression, "invalid cron expression")
    else
      changeset
    end
  end

  defp valid_cron?(cron) do
    # Basic validation: 5 or 6 parts separated by spaces
    parts = String.split(cron, " ")
    length(parts) in 5..6
  end

  defp maybe_generate_webhook_secret(changeset) do
    if get_field(changeset, :event_type) == "webhook" && is_nil(get_field(changeset, :webhook_secret)) do
      secret = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
      put_change(changeset, :webhook_secret, secret)
    else
      changeset
    end
  end

  defp compute_next_run(changeset) do
    event_type = get_field(changeset, :event_type)
    
    case event_type do
      "one_time" ->
        scheduled_at = get_field(changeset, :scheduled_at)
        put_change(changeset, :next_run_at, scheduled_at)
        
      "recurring" ->
        cron = get_field(changeset, :cron_expression)
        if cron do
          # For now, set next_run to nil - will be computed by the scheduler
          changeset
        else
          changeset
        end
        
      _ ->
        changeset
    end
  end

  # Helper to get event types for forms
  def event_types, do: @event_types
  def statuses, do: @statuses
  def action_types, do: @actions
end

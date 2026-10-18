defmodule Bacon8.Scheduler do
  @moduledoc """
  Scheduler context: Projects, Tasks, Scheduled Events, and automation.
  
  Features:
  - Project management with tasks and dependencies
  - Scheduled events (cron jobs, one-time, webhooks, triggers)
  - Project lifecycle event tracking
  - Integration between projects and scheduler
  """

  import Ecto.Query, warn: false
  alias Bacon8.Repo
  alias Bacon8.Scheduler.{Project, Task, TaskDependency, ScheduledEvent, ProjectEvent, ScheduledEventRun}
  alias Phoenix.PubSub

  # ==================== PROJECTS ====================

  def list_projects do
    Repo.all(from p in Project, order_by: [desc: p.inserted_at]) |> Repo.preload(:owner)
  end

  def list_projects_with_stats do
    projects = list_projects()
    Enum.map(projects, fn p ->
      task_count = Repo.one(from t in Task, where: t.project_id == ^p.id, select: count(t.id))
      completed_count = Repo.one(from t in Task, where: t.project_id == ^p.id and t.status == "completed", select: count(t.id))
      Map.merge(p, %{task_count: task_count, completed_count: completed_count})
    end)
  end

  def get_project!(id) do
    Repo.get!(Project, id) |> Repo.preload([:tasks, :owner])
  end

  def get_project(id) do
    case Repo.get(Project, id) do
      nil -> {:error, :not_found}
      project -> {:ok, Repo.preload(project, [:tasks, :owner])}
    end
  end

  def create_project(attrs, user_id \\ nil) do
    result = %Project{}
    |> Project.changeset(attrs)
    |> Repo.insert()
    
    case result do
      {:ok, project} ->
        # Record project creation event
        create_project_event(%{
          event_type: "project_created",
          title: "Project created: #{project.name}",
          project_id: project.id,
          occurred_at: DateTime.utc_now(),
          triggered_by_user_id: user_id
        })
        broadcast_project_change(project, :created)
        {:ok, project}
      error -> error
    end
  end

  def update_project(%Project{} = project, attrs, user_id \\ nil) do
    old_status = project.status
    
    result = project
    |> Project.changeset(attrs)
    |> Repo.update()
    
    case result do
      {:ok, updated} ->
        # Check for status changes and create events
        if old_status != updated.status do
          event_type = case updated.status do
            "active" when old_status in ["archived", "completed"] -> "project_started"
            "completed" -> "project_completed"
            "archived" -> "project_archived"
            _ -> nil
          end
          
          if event_type do
            {:ok, event} = create_project_event(%{
              event_type: event_type,
              title: "Project #{event_type |> String.replace("project_", "")}: #{updated.name}",
              project_id: updated.id,
              occurred_at: DateTime.utc_now(),
              triggered_by_user_id: user_id
            })
            
            # Trigger any scheduled events linked to this project event
            trigger_scheduled_events(event)
          end
        end
        
        broadcast_project_change(updated, :updated)
        {:ok, updated}
      error -> error
    end
  end

  def delete_project(%Project{} = project) do
    result = Repo.delete(project)
    case result do
      {:ok, _} -> broadcast_project_change(project, :deleted)
      _ -> :ok
    end
    result
  end

  def list_projects_for_calendar do
    now = DateTime.utc_now()
    
    projects = from(p in Project, 
      where: p.status in ["active", "pending"],
      or_where: p.start_date >= ^now or p.end_date >= ^now,
      select: %{id: p.id, name: p.name, start_date: p.start_date, end_date: p.end_date, status: p.status},
      order_by: [asc: p.start_date],
      limit: 20
    ) |> Repo.all()
    
    Enum.map(projects, fn p -> Map.put(p, :path, "/admin/projects?id=#{p.id}") end)
  end

  defp broadcast_project_change(project, action) do
    PubSub.broadcast(Bacon8.PubSub, "scheduler:projects", {:project_change, project, action})
  end

  # ==================== TASKS ====================

  def list_tasks_for_project(project_id) do
    from(t in Task, 
      where: t.project_id == ^project_id, 
      order_by: [asc: t.start_at, asc: t.inserted_at]
    ) |> Repo.all()
  end

  def get_task!(id) do
    Repo.get!(Task, id)
  end

  def create_task(attrs, user_id \\ nil) do
    result = %Task{}
    |> Task.changeset(attrs)
    |> Repo.insert()
    
    case result do
      {:ok, task} ->
        create_project_event(%{
          event_type: "task_created",
          title: "Task created: #{task.title}",
          project_id: task.project_id,
          task_id: task.id,
          occurred_at: DateTime.utc_now(),
          triggered_by_user_id: user_id
        })
        {:ok, task}
      error -> error
    end
  end

  def update_task(%Task{} = task, attrs, user_id \\ nil) do
    old_status = task.status
    
    result = task
    |> Task.changeset(attrs)
    |> Repo.update()
    
    case result do
      {:ok, updated} ->
        if old_status != updated.status && updated.status == "completed" do
          {:ok, event} = create_project_event(%{
            event_type: "task_completed",
            title: "Task completed: #{updated.title}",
            project_id: updated.project_id,
            task_id: updated.id,
            occurred_at: DateTime.utc_now(),
            triggered_by_user_id: user_id
          })
          
          trigger_scheduled_events(event)
        end
        {:ok, updated}
      error -> error
    end
  end

  def delete_task(%Task{} = task) do
    Repo.delete(task)
  end

  # ==================== TASK DEPENDENCIES ====================

  def create_task_dependency(attrs) do
    %TaskDependency{}
    |> TaskDependency.changeset(attrs)
    |> Repo.insert()
  end

  def delete_task_dependency(%TaskDependency{} = dep) do
    Repo.delete(dep)
  end

  def list_dependencies_for_project(project_id) do
    from(d in TaskDependency,
      join: t in Task, on: d.task_id == t.id,
      where: t.project_id == ^project_id,
      preload: [:task, :depends_on_task]
    )
    |> Repo.all()
  end

  # ==================== SCHEDULED EVENTS ====================

  def list_scheduled_events(opts \\ []) do
    status = Keyword.get(opts, :status)
    event_type = Keyword.get(opts, :event_type)
    limit = Keyword.get(opts, :limit, 100)
    
    query = from(e in ScheduledEvent, order_by: [desc: e.inserted_at], limit: ^limit)
    
    query = if status, do: where(query, [e], e.status == ^status), else: query
    query = if event_type, do: where(query, [e], e.event_type == ^event_type), else: query
    
    Repo.all(query)
  end

  def list_upcoming_events(limit \\ 10) do
    now = DateTime.utc_now()
    
    from(e in ScheduledEvent,
      where: e.status == "active",
      where: e.next_run_at >= ^now or e.event_type == "recurring",
      order_by: [asc: e.next_run_at],
      limit: ^limit
    ) |> Repo.all()
  end

  def list_events_due_for_execution do
    now = DateTime.utc_now()
    
    from(e in ScheduledEvent,
      where: e.status == "active",
      where: e.next_run_at <= ^now,
      where: e.event_type in ["one_time", "recurring"]
    ) |> Repo.all()
  end

  def get_scheduled_event!(id) do
    Repo.get!(ScheduledEvent, id)
  end

  def get_scheduled_event(id) do
    case Repo.get(ScheduledEvent, id) do
      nil -> {:error, :not_found}
      event -> {:ok, event}
    end
  end

  def get_scheduled_event_by_webhook_secret(secret) do
    Repo.get_by(ScheduledEvent, webhook_secret: secret, event_type: "webhook")
  end

  def create_scheduled_event(attrs) do
    %ScheduledEvent{}
    |> ScheduledEvent.changeset(attrs)
    |> Repo.insert()
  end

  def update_scheduled_event(%ScheduledEvent{} = event, attrs) do
    event
    |> ScheduledEvent.changeset(attrs)
    |> Repo.update()
  end

  def delete_scheduled_event(%ScheduledEvent{} = event) do
    Repo.delete(event)
  end

  def pause_scheduled_event(%ScheduledEvent{} = event) do
    update_scheduled_event(event, %{status: "paused"})
  end

  def resume_scheduled_event(%ScheduledEvent{} = event) do
    update_scheduled_event(event, %{status: "active"})
  end

  # ==================== SCHEDULED EVENT EXECUTION ====================

  def execute_scheduled_event(%ScheduledEvent{} = event) do
    # Create run record
    {:ok, run} = create_event_run(event)
    
    try do
      result = execute_action(event)
      
      # Update run as successful
      complete_event_run(run, "success", result)
      
      # Update event
      update_event_after_run(event, :success)
      
      {:ok, result}
    rescue
      e ->
        error_msg = Exception.message(e)
        complete_event_run(run, "failed", %{}, error_msg)
        update_event_after_run(event, :failed, error_msg)
        {:error, error_msg}
    end
  end

  defp execute_action(%ScheduledEvent{action_type: "http_request", action_config: config}) do
    url = config["url"] || config[:url]
    method = (config["method"] || config[:method] || "GET") |> String.upcase() |> String.to_atom()
    headers = config["headers"] || config[:headers] || %{}
    body = config["body"] || config[:body]
    
    headers_list = Enum.map(headers, fn {k, v} -> {to_string(k), to_string(v)} end)
    
    case method do
      :GET -> 
        case :httpc.request(:get, {String.to_charlist(url), headers_list}, [], []) do
          {:ok, {{_, status, _}, _, body}} -> %{status: status, body: to_string(body)}
          {:error, reason} -> raise "HTTP request failed: #{inspect(reason)}"
        end
      :POST ->
        json_body = if is_map(body), do: Jason.encode!(body), else: body || ""
        headers_list = [{~c"content-type", ~c"application/json"} | headers_list]
        case :httpc.request(:post, {String.to_charlist(url), headers_list, ~c"application/json", json_body}, [], []) do
          {:ok, {{_, status, _}, _, resp_body}} -> %{status: status, body: to_string(resp_body)}
          {:error, reason} -> raise "HTTP request failed: #{inspect(reason)}"
        end
      _ ->
        raise "Unsupported HTTP method: #{method}"
    end
  end

  defp execute_action(%ScheduledEvent{action_type: "create_project", action_config: config}) do
    attrs = %{
      name: config["name"] || config[:name] || "Auto-created project",
      description: config["description"] || config[:description],
      owner_id: config["owner_id"] || config[:owner_id],
      status: "active"
    }
    
    case create_project(attrs) do
      {:ok, project} -> %{project_id: project.id, name: project.name}
      {:error, changeset} -> raise "Failed to create project: #{inspect(changeset.errors)}"
    end
  end

  defp execute_action(%ScheduledEvent{action_type: "complete_project", target_project_id: project_id}) when not is_nil(project_id) do
    project = get_project!(project_id)
    case update_project(project, %{status: "completed"}) do
      {:ok, updated} -> %{project_id: updated.id, status: "completed"}
      {:error, changeset} -> raise "Failed to complete project: #{inspect(changeset.errors)}"
    end
  end

  defp execute_action(%ScheduledEvent{action_type: "notify", action_config: config}) do
    channel = config["channel"] || config[:channel] || "scheduler:notifications"
    message = config["message"] || config[:message] || "Scheduled notification"
    
    PubSub.broadcast(Bacon8.PubSub, channel, {:scheduled_notification, message})
    %{channel: channel, message: message, delivered: true}
  end

  defp execute_action(%ScheduledEvent{action_type: action_type}) do
    %{action_type: action_type, status: "no_handler", message: "No handler for action type: #{action_type}"}
  end

  defp update_event_after_run(%ScheduledEvent{} = event, status, error \\ nil) do
    now = DateTime.utc_now()
    run_count = event.run_count + 1
    
    attrs = %{
      last_run_at: now,
      run_count: run_count,
      last_error: if(status == :failed, do: error, else: nil)
    }
    
    # Check if event should be marked completed
    attrs = cond do
      event.event_type == "one_time" ->
        Map.put(attrs, :status, "completed")
        
      event.max_runs && run_count >= event.max_runs ->
        Map.put(attrs, :status, "completed")
        
      event.event_type == "recurring" ->
        # Calculate next run time
        next_run = compute_next_cron_run(event.cron_expression, event.timezone)
        Map.put(attrs, :next_run_at, next_run)
        
      true ->
        attrs
    end
    
    update_scheduled_event(event, attrs)
  end

  defp compute_next_cron_run(cron_expression, _timezone) do
    alias Bacon8.Scheduler.CronParser
    
    case CronParser.next_run(cron_expression) do
      {:ok, next_time} -> next_time
      {:error, _} -> 
        # Fallback: add 1 hour if parsing fails
        DateTime.utc_now() |> DateTime.add(3600, :second)
    end
  end

  # ==================== EVENT RUNS ====================

  def create_event_run(%ScheduledEvent{} = event) do
    %ScheduledEventRun{}
    |> ScheduledEventRun.changeset(%{
      scheduled_event_id: event.id,
      started_at: DateTime.utc_now(),
      status: "running"
    })
    |> Repo.insert()
  end

  def complete_event_run(%ScheduledEventRun{} = run, status, result \\ %{}, error \\ nil) do
    now = DateTime.utc_now()
    duration = if run.started_at, do: DateTime.diff(now, run.started_at, :millisecond), else: 0
    
    run
    |> ScheduledEventRun.changeset(%{
      completed_at: now,
      status: status,
      result: result,
      error: error,
      duration_ms: duration
    })
    |> Repo.update()
  end

  def list_event_runs(event_id, limit \\ 20) do
    from(r in ScheduledEventRun,
      where: r.scheduled_event_id == ^event_id,
      order_by: [desc: r.started_at],
      limit: ^limit
    ) |> Repo.all()
  end

  # ==================== PROJECT EVENTS ====================

  def create_project_event(attrs) do
    %ProjectEvent{}
    |> ProjectEvent.changeset(attrs)
    |> Repo.insert()
  end

  def list_project_events(project_id, limit \\ 50) do
    from(e in ProjectEvent,
      where: e.project_id == ^project_id,
      order_by: [desc: e.occurred_at],
      limit: ^limit
    ) |> Repo.all()
  end

  def list_recent_project_events(limit \\ 20) do
    from(e in ProjectEvent,
      order_by: [desc: e.occurred_at],
      limit: ^limit,
      preload: [:project]
    ) |> Repo.all()
  end

  # ==================== TRIGGER SYSTEM ====================

  def trigger_scheduled_events(%ProjectEvent{} = project_event) do
    # Find all scheduled events that should be triggered by this project event
    trigger_on = project_event.event_type
    project_id = project_event.project_id
    
    events = from(e in ScheduledEvent,
      where: e.event_type == "project_trigger",
      where: e.trigger_project_id == ^project_id,
      where: e.trigger_on == ^trigger_on,
      where: e.status == "active"
    ) |> Repo.all()
    
    triggered_ids = Enum.map(events, fn event ->
      # Execute async
      Elixir.Task.start(fn -> execute_scheduled_event(event) end)
      event.id
    end)
    
    # Update project event with triggered event IDs
    if length(triggered_ids) > 0 do
      project_event
      |> ProjectEvent.changeset(%{triggered_events: triggered_ids})
      |> Repo.update()
    end
    
    {:ok, triggered_ids}
  end

  # ==================== WEBHOOK TRIGGERS ====================

  def trigger_webhook(webhook_secret) do
    case get_scheduled_event_by_webhook_secret(webhook_secret) do
      nil -> {:error, :not_found}
      event -> execute_scheduled_event(event)
    end
  end

  def generate_webhook_url(event_id) do
    event = get_scheduled_event!(event_id)
    if event.webhook_secret do
      # This would be constructed based on your app's domain
      "/api/webhooks/scheduler/#{event.webhook_secret}"
    else
      nil
    end
  end

end

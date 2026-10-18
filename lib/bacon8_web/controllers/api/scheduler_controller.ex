defmodule Bacon8Web.Api.SchedulerController do
  @moduledoc """
  API Controller for Scheduler webhooks and automation endpoints.
  
  Endpoints:
  - POST /api/webhooks/scheduler/:secret - Trigger webhook event
  - GET /api/scheduler/events - List scheduled events (authenticated)
  - POST /api/scheduler/events - Create scheduled event (authenticated)
  - POST /api/scheduler/events/:id/run - Run event now (authenticated)
  """
  use Bacon8Web, :controller
  alias Bacon8.Scheduler
  require Logger

  # ==================== WEBHOOK ENDPOINTS (Public with secret) ====================

  @doc """
  Trigger a webhook-type scheduled event.
  The webhook secret acts as authentication.
  """
  def trigger_webhook(conn, %{"secret" => secret}) do
    case Scheduler.trigger_webhook(secret) do
      {:ok, result} ->
        Logger.info("Webhook triggered successfully: #{secret}")
        json(conn, %{success: true, result: result})
        
      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Webhook not found or inactive"})
        
      {:error, reason} ->
        Logger.error("Webhook execution failed: #{inspect(reason)}")
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "Webhook execution failed", details: to_string(reason)})
    end
  end

  # ==================== AUTHENTICATED ENDPOINTS ====================

  @doc """
  List all scheduled events.
  Requires authentication.
  """
  def list_events(conn, params) do
    with {:ok, _user} <- get_current_user(conn) do
      opts = [
        status: params["status"],
        event_type: params["event_type"],
        limit: parse_int(params["limit"], 100)
      ] |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      
      events = Scheduler.list_scheduled_events(opts)
      
      json(conn, %{
        success: true,
        events: Enum.map(events, &serialize_event/1)
      })
    else
      {:error, :unauthorized} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "Unauthorized"})
    end
  end

  @doc """
  Get a single scheduled event by ID.
  """
  def get_event(conn, %{"id" => id}) do
    with {:ok, _user} <- get_current_user(conn),
         {:ok, event} <- Scheduler.get_scheduled_event(id) do
      runs = Scheduler.list_event_runs(id, 10)
      
      json(conn, %{
        success: true,
        event: serialize_event(event),
        runs: Enum.map(runs, &serialize_run/1)
      })
    else
      {:error, :unauthorized} ->
        conn |> put_status(:unauthorized) |> json(%{error: "Unauthorized"})
      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Event not found"})
    end
  end

  @doc """
  Create a new scheduled event.
  """
  def create_event(conn, %{"event" => event_params}) do
    with {:ok, user} <- get_current_user(conn) do
      params = Map.put(event_params, "created_by_id", user.id)
      
      # Parse action_config if it's a string
      params = if is_binary(params["action_config"]) do
        case Jason.decode(params["action_config"]) do
          {:ok, config} -> Map.put(params, "action_config", config)
          _ -> params
        end
      else
        params
      end
      
      case Scheduler.create_scheduled_event(params) do
        {:ok, event} ->
          conn
          |> put_status(:created)
          |> json(%{success: true, event: serialize_event(event)})
          
        {:error, changeset} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{error: "Validation failed", details: format_errors(changeset)})
      end
    else
      {:error, :unauthorized} ->
        conn |> put_status(:unauthorized) |> json(%{error: "Unauthorized"})
    end
  end

  @doc """
  Update a scheduled event.
  """
  def update_event(conn, %{"id" => id, "event" => event_params}) do
    with {:ok, _user} <- get_current_user(conn),
         {:ok, event} <- Scheduler.get_scheduled_event(id) do
      
      # Parse action_config if it's a string
      params = if is_binary(event_params["action_config"]) do
        case Jason.decode(event_params["action_config"]) do
          {:ok, config} -> Map.put(event_params, "action_config", config)
          _ -> event_params
        end
      else
        event_params
      end
      
      case Scheduler.update_scheduled_event(event, params) do
        {:ok, updated} ->
          json(conn, %{success: true, event: serialize_event(updated)})
          
        {:error, changeset} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{error: "Validation failed", details: format_errors(changeset)})
      end
    else
      {:error, :unauthorized} ->
        conn |> put_status(:unauthorized) |> json(%{error: "Unauthorized"})
      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Event not found"})
    end
  end

  @doc """
  Delete a scheduled event.
  """
  def delete_event(conn, %{"id" => id}) do
    with {:ok, _user} <- get_current_user(conn),
         {:ok, event} <- Scheduler.get_scheduled_event(id),
         {:ok, _} <- Scheduler.delete_scheduled_event(event) do
      json(conn, %{success: true, message: "Event deleted"})
    else
      {:error, :unauthorized} ->
        conn |> put_status(:unauthorized) |> json(%{error: "Unauthorized"})
      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Event not found"})
      {:error, _} ->
        conn |> put_status(:internal_server_error) |> json(%{error: "Failed to delete event"})
    end
  end

  @doc """
  Run a scheduled event immediately.
  """
  def run_event(conn, %{"id" => id}) do
    with {:ok, _user} <- get_current_user(conn),
         {:ok, event} <- Scheduler.get_scheduled_event(id) do
      
      case Scheduler.execute_scheduled_event(event) do
        {:ok, result} ->
          json(conn, %{success: true, result: result})
          
        {:error, reason} ->
          conn
          |> put_status(:internal_server_error)
          |> json(%{error: "Execution failed", details: to_string(reason)})
      end
    else
      {:error, :unauthorized} ->
        conn |> put_status(:unauthorized) |> json(%{error: "Unauthorized"})
      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Event not found"})
    end
  end

  @doc """
  Pause a scheduled event.
  """
  def pause_event(conn, %{"id" => id}) do
    with {:ok, _user} <- get_current_user(conn),
         {:ok, event} <- Scheduler.get_scheduled_event(id),
         {:ok, updated} <- Scheduler.pause_scheduled_event(event) do
      json(conn, %{success: true, event: serialize_event(updated)})
    else
      {:error, :unauthorized} ->
        conn |> put_status(:unauthorized) |> json(%{error: "Unauthorized"})
      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Event not found"})
      {:error, _} ->
        conn |> put_status(:internal_server_error) |> json(%{error: "Failed to pause event"})
    end
  end

  @doc """
  Resume a scheduled event.
  """
  def resume_event(conn, %{"id" => id}) do
    with {:ok, _user} <- get_current_user(conn),
         {:ok, event} <- Scheduler.get_scheduled_event(id),
         {:ok, updated} <- Scheduler.resume_scheduled_event(event) do
      json(conn, %{success: true, event: serialize_event(updated)})
    else
      {:error, :unauthorized} ->
        conn |> put_status(:unauthorized) |> json(%{error: "Unauthorized"})
      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Event not found"})
      {:error, _} ->
        conn |> put_status(:internal_server_error) |> json(%{error: "Failed to resume event"})
    end
  end

  # ==================== PROJECT EVENTS ENDPOINTS ====================

  @doc """
  List project lifecycle events.
  """
  def list_project_events(conn, params) do
    with {:ok, _user} <- get_current_user(conn) do
      project_id = params["project_id"]
      limit = parse_int(params["limit"], 50)
      
      events = if project_id do
        Scheduler.list_project_events(project_id, limit)
      else
        Scheduler.list_recent_project_events(limit)
      end
      
      json(conn, %{
        success: true,
        events: Enum.map(events, &serialize_project_event/1)
      })
    else
      {:error, :unauthorized} ->
        conn |> put_status(:unauthorized) |> json(%{error: "Unauthorized"})
    end
  end

  # ==================== HELPERS ====================

  defp get_current_user(conn) do
    case Guardian.Plug.current_resource(conn) do
      nil -> {:error, :unauthorized}
      user -> {:ok, user}
    end
  end

  defp parse_int(nil, default), do: default
  defp parse_int(val, default) when is_binary(val) do
    case Integer.parse(val) do
      {int, _} -> int
      :error -> default
    end
  end
  defp parse_int(val, _default) when is_integer(val), do: val

  defp serialize_event(event) do
    %{
      id: event.id,
      title: event.title,
      description: event.description,
      event_type: event.event_type,
      status: event.status,
      scheduled_at: event.scheduled_at,
      cron_expression: event.cron_expression,
      timezone: event.timezone,
      next_run_at: event.next_run_at,
      last_run_at: event.last_run_at,
      run_count: event.run_count,
      max_runs: event.max_runs,
      action_type: event.action_type,
      action_config: event.action_config,
      trigger_project_id: event.trigger_project_id,
      trigger_on: event.trigger_on,
      target_project_id: event.target_project_id,
      webhook_url: if(event.webhook_secret, do: "/api/webhooks/scheduler/#{event.webhook_secret}", else: nil),
      created_at: event.inserted_at,
      updated_at: event.updated_at
    }
  end

  defp serialize_run(run) do
    %{
      id: run.id,
      started_at: run.started_at,
      completed_at: run.completed_at,
      status: run.status,
      result: run.result,
      error: run.error,
      duration_ms: run.duration_ms
    }
  end

  defp serialize_project_event(event) do
    %{
      id: event.id,
      event_type: event.event_type,
      title: event.title,
      description: event.description,
      occurred_at: event.occurred_at,
      project_id: event.project_id,
      task_id: event.task_id,
      triggered_events: event.triggered_events,
      created_at: event.inserted_at
    }
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end
end

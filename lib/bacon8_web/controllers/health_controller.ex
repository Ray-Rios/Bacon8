defmodule Bacon8Web.HealthController do
  use Bacon8Web, :controller

  def check(conn, _params) do
    # Basic health checks
    health_status = %{
      status: "ok",
      timestamp: DateTime.utc_now(),
      version: Application.spec(:bacon8, :vsn) |> to_string(),
      checks: %{
        database: check_database(),
        redis: check_redis()
      }
    }

    case health_status.checks do
      %{database: :ok, redis: :ok} ->
        json(conn, health_status)
      
      %{database: :ok, redis: :error} ->
        conn
        |> put_status(:service_unavailable)
        |> json(put_in(health_status.status, "degraded"))
      
      _ ->
        conn
        |> put_status(:service_unavailable)
        |> json(put_in(health_status.status, "error"))
    end
  end

  defp check_database do
    try do
      Bacon8.Repo.query!("SELECT 1")
      :ok
    rescue
      _ -> :error
    end
  end

  defp check_redis do
    try do
      case Application.get_env(:bacon8, :enable_redis, false) do
        true ->
          # Add Redis health check here if you're using Redis
          :ok
        false ->
          :ok
      end
    rescue
      _ -> :error
    end
  end
end
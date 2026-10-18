defmodule Bacon8Web.Api.ApiController do
  use Bacon8Web, :controller

  @doc """
  GET /api/status
  Returns service status information matching the Rust API format.
  """
  def status(conn, _params) do
    response = %{
      success: true,
      data: %{
        service: "world_builder_service",
        version: "0.1.0",
        status: "running",
        timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
      },
      message: "Service status retrieved"
    }

    conn
    |> put_status(:ok)
    |> put_resp_header("content-type", "application/json")
    |> json(response)
  end

  @doc """
  POST /api/sessions
  Creates a new game session matching the Rust API format.
  TODO: Implement when game functionality is ready
  """
  def create_session(conn, _params) do
    response = %{
      success: false,
      data: nil,
      message: "Game sessions not yet implemented"
    }

    conn
    |> put_status(:not_implemented)
    |> put_resp_header("content-type", "application/json")
    |> json(response)
  end
end
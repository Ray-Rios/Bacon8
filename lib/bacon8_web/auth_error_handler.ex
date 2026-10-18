defmodule Bacon8Web.AuthErrorHandler do
  @moduledoc """
  Handles authentication errors for Guardian JWT
  """
  import Plug.Conn
  import Phoenix.Controller

  @behaviour Guardian.Plug.ErrorHandler

  @impl Guardian.Plug.ErrorHandler
  def auth_error(conn, {type, _reason}, _opts) do
    body = %{
      success: false,
      error: to_string(type),
      message: auth_error_message(type)
    }

    conn
    |> put_resp_content_type("application/json")
    |> put_status(status_code(type))
    |> json(body)
  end

  defp auth_error_message(type) do
    case type do
      :already_authenticated -> "Already authenticated"
      :unauthenticated -> "Authentication required"
      :no_resource_found -> "User not found"
      :invalid_token -> "Invalid token"
      :token_expired -> "Token expired"
      _ -> "Authentication failed"
    end
  end

  defp status_code(type) do
    case type do
      :already_authenticated -> 200
      :unauthenticated -> 401
      :no_resource_found -> 401
      :invalid_token -> 401
      :token_expired -> 401
      _ -> 401
    end
  end
end
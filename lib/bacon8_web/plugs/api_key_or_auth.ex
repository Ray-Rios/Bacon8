defmodule Bacon8Web.Plugs.ApiKeyOrAuth do
  @moduledoc """
  Plug to authorize by either X-API-Key header (shared secret) or a valid Guardian bearer token.

  Usage: add `plug Bacon8Web.Plugs.ApiKeyOrAuth when action in [:calendar]` to your controller.
  """
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    api_key = get_req_header(conn, "x-api-key") |> List.first()
    expected = Application.get_env(:bacon8, :projects_api_key) || System.get_env("PROJECTS_API_KEY")

    cond do
      api_key && expected && secure_compare(api_key, expected) ->
        conn

      # Check for authenticated resource loaded by Guardian.LoadResource
      Guardian.Plug.current_resource(conn) ->
        conn

      true ->
        body = Jason.encode!(%{error: "Unauthorized"})
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(401, body)
        |> halt()
    end
  end

  defp secure_compare(a, b) when is_binary(a) and is_binary(b) do
    try do
      Plug.Crypto.secure_compare(a, b)
    rescue
      _ -> false
    end
  end
  defp secure_compare(_, _), do: false
end

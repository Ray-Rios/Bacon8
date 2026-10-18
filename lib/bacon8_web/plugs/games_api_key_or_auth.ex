defmodule Bacon8Web.Plugs.GamesApiKeyOrAuth do
  @moduledoc """
  Authorizes `/api/games/*` requests by either:

    - a valid Guardian bearer token (the player acting on their own behalf), or
    - an `X-API-Key` header matching the `GAMES_SERVER_API_KEY` secret (a
      trusted dedicated game server acting on behalf of a player it has
      already authenticated itself, e.g. via `/api/auth/verify-bearer`).

  When authorized via API key, the request must include a `user_id` param
  (the plug does not implicitly trust any user - the game server must supply
  the id of the player it verified).
  """

  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    api_key = get_req_header(conn, "x-api-key") |> List.first()
    expected = Application.get_env(:bacon8, :games_server_api_key)

    cond do
      is_binary(api_key) && is_binary(expected) && expected != "" && secure_compare(api_key, expected) ->
        assign(conn, :games_auth_mode, :server_api_key)

      Guardian.Plug.current_resource(conn) ->
        assign(conn, :games_auth_mode, :player_token)

      true ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(401, Jason.encode!(%{error: "Unauthorized"}))
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

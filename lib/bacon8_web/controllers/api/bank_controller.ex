defmodule Bacon8Web.Api.BankController do
  @moduledoc """
  An account's bank in a game (2026-11-24; `Bacon8.GameBank`), for the games that keep their own bags: Tears of
  Babylon and RaysSpaceSim. `/api/games/:game_slug/bank`

    * `GET` - `{bank: {slots, coins}, revision}`
    * `PUT` - `bank` (`{slots, coins}`) and `revision` (the one read): `{bank, revision}`; a stale revision is
      refused (409) with the bank as it is now.

  Authorized as the player (bearer token) or as a game server (`X-API-Key`, with `user_id`). Bacon World keeps its
  own bank.
  """

  use Bacon8Web, :controller
  alias Bacon8.{GameBank, Games}

  plug Bacon8Web.Plugs.GamesApiKeyOrAuth

  def show(conn, %{"game_slug" => slug} = params) do
    with {:ok, _} <- fetch_game(slug), {:ok, user} <- resolve_user(conn, params) do
      %{data: data, revision: rev} = GameBank.get(slug, user.id)
      json(conn, %{success: true, bank: data, revision: rev, slots: GameBank.slots()})
    else
      {:error, status, message} -> error_response(conn, status, message)
    end
  end

  def update(conn, %{"game_slug" => slug} = params) do
    with {:ok, _} <- fetch_game(slug),
         :ok <- if(slug == "bacon_world", do: {:error, 403, "Bacon World keeps its own bank."}, else: :ok),
         {:ok, user} <- resolve_user(conn, params) do
      case GameBank.put(slug, user.id, params["bank"], params["revision"]) do
        {:ok, %{data: data, revision: rev}} ->
          json(conn, %{success: true, bank: data, revision: rev})

        {:error, :stale, %{data: data, revision: rev}} ->
          conn |> put_status(409) |> json(%{success: false, message: "The bank changed; read it again.", bank: data, revision: rev})

        {:error, message} ->
          error_response(conn, 422, message)
      end
    else
      {:error, status, message} -> error_response(conn, status, message)
    end
  end

  defp fetch_game(slug) do
    case Games.get_game_by_slug(slug) do
      nil -> {:error, 404, "Unknown game: #{slug}"}
      game -> if game.is_active, do: {:ok, game}, else: {:error, 403, "Game is not active"}
    end
  end

  defp resolve_user(conn, params) do
    case conn.assigns[:games_auth_mode] do
      :player_token ->
        {:ok, Guardian.Plug.current_resource(conn)}

      :server_api_key ->
        with id when is_binary(id) <- params["user_id"] || {:error, 400, "user_id is required when authenticating via server API key"},
             {:ok, uuid} <- Ecto.UUID.cast(id) |> then(&if(&1 == :error, do: {:error, 400, "user_id isn't an id"}, else: &1)),
             %{} = u <- Bacon8.Accounts.get_user(uuid) || {:error, 404, "Unknown user"} do
          {:ok, u}
        end

      _ ->
        {:error, 401, "Not signed in"}
    end
  end

  defp error_response(conn, status, message) do
    conn |> put_status(status) |> json(%{success: false, message: message})
  end
end

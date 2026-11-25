defmodule Bacon8Web.Api.GemsController do
  @moduledoc """
  The jeweller's Gem-only sets for the games that keep their own bags (2026-11-24; `Bacon8.GemShop`): Tears of Babylon
  and RaysSpaceSim. `/api/games/:game_slug/gems/...`

    * `GET  jeweller?body=female` - `{balance, price, stock: [%{item_id, name, set, slots, pieces}]}`
    * `POST jeweller/buy` - `item_id`, `character_id`, `body`, `nonce` (one per click): spends the Gems and answers
      `{item_id, pieces, gems_spent, charged, balance}`; the game puts `pieces` in the character's bags. The same
      nonce again charges nothing and answers the same pieces (`charged: false`).

  Authorized as the player (bearer token) or as a game server (`X-API-Key`, with `user_id`: the player it buys for).
  The character must be that player's, in this game. Bacon World buys through its own jeweller.
  """

  use Bacon8Web, :controller
  alias Bacon8.{GemShop, Games}

  plug Bacon8Web.Plugs.GamesApiKeyOrAuth

  def jeweller(conn, %{"game_slug" => slug} = params) do
    with {:ok, _} <- fetch_game(slug), {:ok, user} <- resolve_user(conn, params, false) do
      json(conn, %{success: true, balance: GemShop.balance(user), price: GemShop.price(), available: GemShop.available?(),
        stock: GemShop.stock(body(params))})
    else
      {:error, status, message} -> error_response(conn, status, message)
    end
  end

  def buy(conn, %{"game_slug" => slug} = params) do
    with {:ok, game} <- fetch_game(slug),
         :ok <- if(slug == "bacon_world", do: {:error, 403, "Bacon World buys from its own jeweller."}, else: :ok),
         {:ok, user} <- resolve_user(conn, params, true),
         %Games.GameCharacter{} = character <- Games.get_owned_character(game.id, user.id, params["character_id"]) || {:error, 404, "Character not found"},
         {:ok, result} <- GemShop.buy(slug, user, %{id: character.id, name: character.name}, to_string(params["item_id"] || ""), body(params), params["nonce"]) do
      json(conn, Map.put(result, :success, true))
    else
      {:error, status, message} when is_integer(status) -> error_response(conn, status, message)
      {:error, message} -> error_response(conn, 422, message)
    end
  end

  defp body(%{"body" => "male"}), do: "male"
  defp body(_), do: "female"

  defp fetch_game(slug) do
    case Games.get_game_by_slug(slug) do
      nil -> {:error, 404, "Unknown game: #{slug}"}
      game -> if game.is_active, do: {:ok, game}, else: {:error, 403, "Game is not active"}
    end
  end

  # the player: the token's, or the one a game server acts for (`user_id`); the list may go without one
  defp resolve_user(conn, params, required?) do
    case conn.assigns[:games_auth_mode] do
      :player_token ->
        {:ok, Guardian.Plug.current_resource(conn)}

      :server_api_key ->
        case params["user_id"] do
          id when is_binary(id) ->
            case Ecto.UUID.cast(id) do
              {:ok, uuid} ->
                case Bacon8.Accounts.get_user(uuid) do
                  nil -> {:error, 404, "Unknown user"}
                  u -> {:ok, u}
                end

              :error -> {:error, 400, "user_id isn't an id"}
            end

          _ ->
            if required?, do: {:error, 400, "user_id is required when authenticating via server API key"}, else: {:ok, nil}
        end

      _ ->
        {:error, 401, "Not signed in"}
    end
  end

  defp error_response(conn, status, message) do
    conn |> put_status(status) |> json(%{success: false, message: message})
  end
end

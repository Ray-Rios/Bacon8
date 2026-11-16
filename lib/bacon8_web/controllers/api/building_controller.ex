defmodule Bacon8Web.Api.BuildingController do
  @moduledoc """
  Build mode for the games that build through the hub (2026-11-14; `Bacon8.Building`):
  RaysSpaceSim and Tears of Babylon. `/api/games/:game_slug/build/...`

    * `GET  catalogue` - what may be placed, with each asset's rule, HP and whether this player may
      (and `role`, the player's own: an admin's window offers each asset's rule)
    * `GET  zones/:zone` - the zone's placements (`?frame=` one frame's; `?rev=n`: `{unchanged: true}`
      while the zone's revision is still `n`), with the revision
    * `POST zones/:zone` - place (`asset`, `frame`, `x`, `y`, `z`, `rot`, `scale`, `data`, `character_id`)
    * `PUT  zones/:zone/:id` - move, turn, resize
    * `DELETE zones/:zone/:id` - remove (`?smash=true`: every client shatters it)
    * `POST zones/:zone/:id/damage` - `amount` damage; at 0 HP it is smashed
    * `PUT  rules/:asset` - an admin sets `min_role` and/or `hp`, for every game

  Authorized as the player (bearer token) or as a game server (`X-API-Key`, with `user_id`: the
  player it acts for). Every permission is checked against that player's role, whichever. Bacon
  World builds in game (its LiveView); this API won't write its zones.
  """

  use Bacon8Web, :controller
  alias Bacon8.{Building, Games}

  plug Bacon8Web.Plugs.GamesApiKeyOrAuth

  def catalogue(conn, %{"game_slug" => slug} = params) do
    with {:ok, _} <- fetch_game(slug), {:ok, user} <- resolve_user(conn, params, false) do
      json(conn, %{success: true, roles: Building.roles(), role: Building.role_of(user), catalogue: Building.catalogue_for(slug, user)})
    else
      {:error, status, message} -> error_response(conn, status, message)
    end
  end

  def list(conn, %{"game_slug" => slug, "zone" => zone} = params) do
    with {:ok, _} <- fetch_game(slug) do
      rev = Building.revision(slug, zone)

      if params["rev"] && to_string(rev) == to_string(params["rev"]) do
        json(conn, %{success: true, unchanged: true, revision: rev})
      else
        json(conn, %{success: true, revision: rev, placements: Building.list(slug, zone, frame: params["frame"])})
      end
    else
      {:error, status, message} -> error_response(conn, status, message)
    end
  end

  def place(conn, %{"game_slug" => slug, "zone" => zone} = params) do
    write(conn, slug, params, fn user -> Building.place(slug, zone, user, params, params["character_id"]) end)
  end

  def move(conn, %{"game_slug" => slug, "zone" => zone, "id" => id} = params) do
    write(conn, slug, params, fn user -> Building.move(slug, zone, user, id, params) end)
  end

  def delete(conn, %{"game_slug" => slug, "zone" => zone, "id" => id} = params) do
    smash = params["smash"] in [true, "true", "1"]
    write(conn, slug, params, fn user -> Building.delete(slug, zone, user, id, smash: smash) end)
  end

  def damage(conn, %{"game_slug" => slug, "zone" => zone, "id" => id} = params) do
    amount = case params["amount"] do n when is_number(n) -> n; s when is_binary(s) -> (case Float.parse(s) do {n, _} -> n; :error -> 0 end); _ -> 0 end

    write(conn, slug, params, fn user ->
      case Building.damage(slug, zone, user, id, amount) do
        {:ok, result, view} -> {:ok, Map.put(view, :result, result)}
        other -> other
      end
    end)
  end

  def set_rule(conn, %{"game_slug" => slug, "asset" => asset} = params) do
    with {:ok, _} <- fetch_game(slug),
         {:ok, user} <- resolve_user(conn, params, true),
         {:ok, _} <- maybe(params["min_role"], &Building.set_rule(user, asset, &1)),
         {:ok, _} <- maybe(params["hp"], &Building.set_hp(user, asset, to_int(&1))) do
      json(conn, %{success: true, asset: Enum.find(Building.catalogue_for(slug, user), &(&1.id == asset))})
    else
      {:error, status, message} -> error_response(conn, status, message)
      {:error, message} -> error_response(conn, 422, message)
    end
  end

  # ---------------------------------------------------------------------------

  defp write(conn, slug, params, fun) do
    with {:ok, _} <- fetch_game(slug),
         :ok <- if(slug == "bacon_world", do: {:error, 403, "Bacon World builds in game."}, else: :ok),
         {:ok, user} <- resolve_user(conn, params, true),
         {:ok, view} <- fun.(user) do
      json(conn, %{success: true, placement: view, revision: Building.revision(slug, params["zone"])})
    else
      {:error, status, message} -> error_response(conn, status, message)
      {:error, message} -> error_response(conn, 422, message)
    end
  end

  defp maybe(nil, _), do: {:ok, nil}
  defp maybe(v, f), do: f.(v)

  defp to_int(n) when is_integer(n), do: n
  defp to_int(n) when is_float(n), do: round(n)
  defp to_int(s) when is_binary(s), do: (case Integer.parse(s) do {n, _} -> n; :error -> 0 end)
  defp to_int(_), do: 0

  defp fetch_game(slug) do
    case Games.get_game_by_slug(slug) do
      nil -> {:error, 404, "Unknown game: #{slug}"}
      game -> if game.is_active, do: {:ok, game}, else: {:error, 403, "Game is not active"}
    end
  end

  # the player: the token's, or the one a game server acts for (`user_id`); reads may go without one
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

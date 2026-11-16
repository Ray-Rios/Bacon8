defmodule Bacon8Web.Api.ContentController do
  @moduledoc """
  A game's definitions through the hub (2026-11-15; `Bacon8.GameContent`): its zones, camps,
  creature types, loot tables, items, merchants. `/api/games/:game_slug/content/...`

    * `GET  /`                      - the kinds the game has, with how many of each and each kind's revision
    * `GET  /:kind`                 - a kind's definitions, in order (`?rev=n`: `{unchanged: true}` while its
                                      revision is still `n`; any other parameter keeps those whose data has
                                      that value at its top level, e.g. `?zone=outskirts_01`)
    * `GET  /:kind/:id`             - one definition
    * `PUT  /:kind/:id`             - save one (`data`: an object); staff
    * `DELETE /:kind/:id`           - delete one; staff
    * `POST /loot_table/:id/roll`   - roll a loot table (`level`, `times` 1-100, `chance_mult`, `coin_mult`):
                                      a game server, or staff trying it
    * `GET  /history`               - the changes, newest first (`?kind=`, `?id=`, `?limit=`); staff
    * `POST /history/:change/undo`  - put a definition back as it was before that change; staff

  Authorized as the player (bearer token) or as a game server (`X-API-Key`; with `user_id` when it
  acts for someone). Reading is for anyone signed in to the game. **Staff** is an admin or a GM
  (`GameContent.staff?/1`), whichever way they come. Rolling loot is never a player's client's to
  ask for: a game's server asks, with the server key. Bacon World's definitions are read here and
  edited in its Studio.
  """

  use Bacon8Web, :controller
  alias Bacon8.{GameContent, Games}
  alias Bacon8.GameContent.Loot

  plug Bacon8Web.Plugs.GamesApiKeyOrAuth

  @reserved ~w(rev game_slug kind user_id)

  def index(conn, %{"game_slug" => slug}) do
    with {:ok, _} <- fetch_game(slug) do
      kinds = for k <- GameContent.kinds(slug), do: Map.put(k, :revision, GameContent.revision(slug, k.kind))
      json(conn, %{success: true, kinds: kinds, read_only: GameContent.read_only?(slug)})
    else
      {:error, status, message} -> error_response(conn, status, message)
    end
  end

  def list(conn, %{"game_slug" => slug, "kind" => kind} = params) do
    with {:ok, _} <- fetch_game(slug) do
      rev = GameContent.revision(slug, kind)

      if params["rev"] && to_string(rev) == to_string(params["rev"]) do
        json(conn, %{success: true, unchanged: true, revision: rev})
      else
        where = Map.drop(params, @reserved)
        json(conn, %{success: true, revision: rev, definitions: Enum.map(GameContent.list(slug, kind, where: where), &view/1)})
      end
    else
      {:error, status, message} -> error_response(conn, status, message)
    end
  end

  def show(conn, %{"game_slug" => slug, "kind" => kind, "id" => id}) do
    with {:ok, _} <- fetch_game(slug) do
      case GameContent.get(slug, kind, id) do
        nil -> error_response(conn, 404, "There is no #{kind} #{id}.")
        data -> json(conn, %{success: true, definition: %{id: id, kind: kind, data: data}})
      end
    else
      {:error, status, message} -> error_response(conn, status, message)
    end
  end

  def put(conn, %{"game_slug" => slug, "kind" => kind, "id" => id} = params) do
    with {:ok, _} <- fetch_game(slug),
         {:ok, user} <- staff(conn, params),
         {:ok, row} <- GameContent.put(slug, kind, id, params["data"], user) do
      json(conn, %{success: true, definition: Map.take(row, [:id, :kind, :data]), revision: GameContent.revision(slug, kind)})
    else
      {:error, status, message} -> error_response(conn, status, message)
      {:error, message} -> error_response(conn, 422, message)
    end
  end

  def delete(conn, %{"game_slug" => slug, "kind" => kind, "id" => id} = params) do
    with {:ok, _} <- fetch_game(slug),
         {:ok, user} <- staff(conn, params),
         :ok <- GameContent.delete(slug, kind, id, user) do
      json(conn, %{success: true, revision: GameContent.revision(slug, kind)})
    else
      {:error, status, message} -> error_response(conn, status, message)
      {:error, message} -> error_response(conn, 422, message)
    end
  end

  def roll(conn, %{"game_slug" => slug, "id" => id} = params) do
    with {:ok, _} <- fetch_game(slug),
         :ok <- may_roll(conn, params),
         table when not is_nil(table) <- GameContent.get(slug, Loot.kind(), id) do
      times = params["times"] |> to_int(1) |> max(1) |> min(100)
      opts = [chance_mult: to_num(params["chance_mult"], 1.0), coin_mult: to_num(params["coin_mult"], 1.0)]
      rolls = for _ <- 1..times, do: Loot.roll(slug, table, to_int(params["level"], 1), opts)
      json(conn, %{success: true, rolls: rolls})
    else
      nil -> error_response(conn, 404, "There is no loot table #{id}.")
      {:error, status, message} -> error_response(conn, status, message)
    end
  end

  def history(conn, %{"game_slug" => slug} = params) do
    with {:ok, _} <- fetch_game(slug), {:ok, _user} <- staff(conn, params) do
      rows = GameContent.history(slug, kind: params["kind"], id: params["id"], limit: to_int(params["limit"], 50))
      json(conn, %{success: true, history: Enum.map(rows, &Map.take(&1, [:id, :kind, :ref_id, :action, :before, :after, :user_name, :inserted_at]))})
    else
      {:error, status, message} -> error_response(conn, status, message)
    end
  end

  def undo(conn, %{"game_slug" => slug, "change" => change} = params) do
    with {:ok, _} <- fetch_game(slug),
         {:ok, user} <- staff(conn, params),
         {:ok, _} <- GameContent.undo(slug, to_int(change, 0), user) do
      json(conn, %{success: true})
    else
      {:error, status, message} -> error_response(conn, status, message)
      {:error, message} -> error_response(conn, 422, message)
    end
  end

  # ---------------------------------------------------------------------------

  defp view(r), do: Map.take(r, [:id, :kind, :data, :position, :updated_at])

  # an admin or a GM: the token's user, or the one a game server acts for
  defp staff(conn, params) do
    with {:ok, user} <- resolve_user(conn, params) do
      if GameContent.staff?(user), do: {:ok, user}, else: {:error, 403, "Only admins and GMs change a game's definitions."}
    end
  end

  # a game's server (the server key, acting for nobody or for anyone), or staff trying a table
  defp may_roll(conn, params) do
    case conn.assigns[:games_auth_mode] do
      :server_api_key -> :ok
      _ -> with {:ok, _} <- staff(conn, params), do: :ok
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
        with id when is_binary(id) <- params["user_id"], {:ok, uuid} <- Ecto.UUID.cast(id), %{} = user <- Bacon8.Accounts.get_user(uuid) do
          {:ok, user}
        else
          _ -> {:error, 400, "user_id (the staff member acted for) is required when authenticating via server API key"}
        end

      _ ->
        {:error, 401, "Not signed in"}
    end
  end

  defp to_int(n, _) when is_integer(n), do: n
  defp to_int(n, _) when is_float(n), do: round(n)
  defp to_int(s, d) when is_binary(s), do: (case Integer.parse(s) do {n, _} -> n; :error -> d end)
  defp to_int(_, d), do: d

  defp to_num(n, _) when is_number(n), do: n * 1.0
  defp to_num(s, d) when is_binary(s), do: (case Float.parse(s) do {n, _} -> n; :error -> d end)
  defp to_num(_, d), do: d

  defp error_response(conn, status, message) do
    conn |> put_status(status) |> json(%{success: false, message: message})
  end
end

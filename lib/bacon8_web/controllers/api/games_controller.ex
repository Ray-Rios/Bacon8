defmodule Bacon8Web.Api.GamesController do
  @moduledoc """
  Generic multiplayer game data API - `/api/games/:game_slug/characters`.

  Shared by every game. A request is authorized
  either as the player themselves (Guardian bearer token) or as a trusted
  dedicated game server (`X-API-Key: GAMES_SERVER_API_KEY`, must pass
  `user_id` explicitly since there's no session in that mode).
  """

  use Bacon8Web, :controller
  alias Bacon8.Games

  plug Bacon8Web.Plugs.GamesApiKeyOrAuth

  # GET /api/games/:game_slug/entitlements (2026-10-29): the items and passes the player owns in this
  # game (store items, mounts...), active now. A player token reads its own; the server API key
  # passes `user_id`.
  def list_entitlements(conn, %{"game_slug" => slug} = params) do
    with {:ok, _game} <- fetch_game(slug),
         {:ok, user_id} <- resolve_user_id(conn, params) do
      items = Bacon8.Entitlements.active_for_game(user_id, Bacon8.Plugins.game_entitlement_kinds(slug))
      json(conn, %{success: true, entitlements: Enum.map(items, &entitlement_json/1)})
    else
      {:error, status, message} -> error_response(conn, status, message)
    end
  end

  # GET /api/games/:game_slug/entitlements/check?kind=&key= : does the player have this one?
  def check_entitlement(conn, %{"game_slug" => slug, "kind" => kind, "key" => key} = params) do
    with {:ok, _game} <- fetch_game(slug),
         {:ok, user_id} <- resolve_user_id(conn, params) do
      owned =
        Bacon8.Entitlements.active_for_game(user_id, Bacon8.Plugins.game_entitlement_kinds(slug))
        |> Enum.any?(&(&1.kind == kind and (&1.key == key or &1.key == "*")))

      json(conn, %{success: true, kind: kind, key: key, active: owned})
    else
      {:error, status, message} -> error_response(conn, status, message)
    end
  end

  def check_entitlement(conn, _params), do: error_response(conn, 400, "kind and key are required")

  defp entitlement_json(e) do
    %{kind: e.kind, key: e.key, quantity: e.quantity, starts_at: e.starts_at, ends_at: e.ends_at, source: e.source_type}
  end

  # GET /api/games/:game_slug/characters
  def list_characters(conn, %{"game_slug" => slug} = params) do
    with {:ok, game} <- fetch_game(slug),
         {:ok, user_id} <- resolve_user_id(conn, params) do
      characters = Games.list_characters(game.id, user_id)
      json(conn, %{success: true, characters: Enum.map(characters, &character_json/1)})
    else
      {:error, status, message} -> error_response(conn, status, message)
    end
  end

  # POST /api/games/:game_slug/characters
  def create_character(conn, %{"game_slug" => slug} = params) do
    with {:ok, game} <- fetch_game(slug),
         {:ok, user_id} <- resolve_user_id(conn, params) do
      attrs = %{
        "game_id" => game.id,
        "user_id" => user_id,
        "name" => params["name"],
        "stats" => params["stats"] || %{},
        "settings" => params["settings"] || %{}
      }

      case Games.create_character(attrs) do
        {:ok, character} ->
          conn
          |> put_status(:created)
          |> json(%{success: true, character: character_json(character)})

        {:error, changeset} ->
          error_response(conn, 422, changeset_errors(changeset))
      end
    else
      {:error, status, message} -> error_response(conn, status, message)
    end
  end

  # GET /api/games/:game_slug/characters/:id
  def get_character(conn, %{"game_slug" => slug, "id" => id} = params) do
    with {:ok, game} <- fetch_game(slug),
         {:ok, user_id} <- resolve_user_id(conn, params),
         %Games.GameCharacter{} = character <- Games.get_owned_character(game.id, user_id, id) do
      json(conn, %{success: true, character: character_json(character)})
    else
      {:error, status, message} -> error_response(conn, status, message)
      nil -> error_response(conn, 404, "Character not found")
    end
  end

  # PUT /api/games/:game_slug/characters/:id
  def update_character(conn, %{"game_slug" => slug, "id" => id} = params) do
    with {:ok, game} <- fetch_game(slug),
         {:ok, user_id} <- resolve_user_id(conn, params),
         %Games.GameCharacter{} = character <- Games.get_owned_character(game.id, user_id, id) do
      attrs =
        %{}
        |> maybe_put("name", params["name"])
        |> maybe_put("stats", params["stats"])
        |> maybe_put("settings", params["settings"])
        |> Map.put("last_played_at", DateTime.utc_now() |> DateTime.truncate(:second))

      case Games.update_character(character, attrs) do
        {:ok, updated} -> json(conn, %{success: true, character: character_json(updated)})
        {:error, changeset} -> error_response(conn, 422, changeset_errors(changeset))
      end
    else
      {:error, status, message} -> error_response(conn, status, message)
      nil -> error_response(conn, 404, "Character not found")
    end
  end

  # DELETE /api/games/:game_slug/characters/:id
  def delete_character(conn, %{"game_slug" => slug, "id" => id} = params) do
    with {:ok, game} <- fetch_game(slug),
         {:ok, user_id} <- resolve_user_id(conn, params),
         %Games.GameCharacter{} = character <- Games.get_owned_character(game.id, user_id, id) do
      {:ok, _} = Games.delete_character(character)
      json(conn, %{success: true})
    else
      {:error, status, message} -> error_response(conn, status, message)
      nil -> error_response(conn, 404, "Character not found")
    end
  end

  # ---------------------------------------------------------------------
  # Single-session enforcement
  #
  # Both server-API-key only. A player token must never reach these: claiming
  # on someone else's behalf is a denial of service against their character,
  # and releasing your own claim is how you would sign in twice, which is the
  # entire thing this prevents.
  #
  # POST rather than folded into `GET /characters/:id`, which the world server
  # already calls at exactly the right moment during PreLoginAsync. It was
  # tempting - one fewer round trip - but a GET that takes an exclusive lock as
  # a side effect is a trap for the next person to call it, and that fetch is
  # not only used by the join path.
  # ---------------------------------------------------------------------

  # POST /api/games/:game_slug/characters/:id/claim
  #
  # Called from PreLoginAsync AFTER the token has been verified and BEFORE the
  # join is approved. A 409 here is a refusal to admit the player, and its
  # message is written to be shown to them as-is.
  def claim_character(conn, %{"game_slug" => slug, "id" => id} = params) do
    with :ok <- require_server_auth(conn),
         {:ok, game} <- fetch_game(slug),
         {:ok, user_id} <- resolve_user_id(conn, params),
         {:ok, server} <- fetch_calling_server(game.id, params) do
      case Games.claim_character_session(game.id, user_id, id, server) do
        {:ok, %{character: character, session_id: session_id}} ->
          json(conn, %{
            success: true,
            session_id: session_id,
            character: character_json(character)
          })

        {:error, :not_found} ->
          error_response(conn, 404, "Character not found")

        {:error, {:in_use, holder}} ->
          # 409 Conflict, not 403. Nothing is wrong with the credentials or the
          # request - the character is simply busy, and it will not be shortly.
          conn
          |> put_status(:conflict)
          |> json(%{
            success: false,
            message: in_use_message(holder),
            server: server_json(holder)
          })
      end
    else
      {:error, status, message} -> error_response(conn, status, message)
    end
  end

  # PUT /api/games/:game_slug/characters/:id/instance_location
  #
  # Resume-in-instance (2026-10-09). An instance server writes
  # {instance_id, location} on Logout and {instance_id: null} when the player
  # chose to leave the instance. A PLAYER token may only clear - which the
  # client does when the instance it was told to resume into is gone or refuses
  # it - never set: a player-chosen instance id would be a login loop into a
  # world they cannot enter.
  def set_instance_location(conn, %{"game_slug" => slug, "id" => id} = params) do
    with {:ok, game} <- fetch_game(slug),
         {:ok, user_id} <- resolve_user_id(conn, params) do
      instance_id = params["instance_id"]
      server? = conn.assigns[:games_auth_mode] == :server_api_key

      cond do
        not is_nil(instance_id) and not server? ->
          error_response(conn, 403, "Only a game server may set a resume location.")

        not is_nil(params["location"]) and not is_map(params["location"]) ->
          error_response(conn, 422, "location must be an object")

        true ->
          case Games.set_instance_location(game.id, user_id, id, instance_id, params["location"]) do
            {:ok, character} ->
              json(conn, %{success: true, character: character_json(character)})

            {:error, :not_found} ->
              error_response(conn, 404, "Character not found")

            {:error, changeset} ->
              error_response(conn, 422, changeset_errors(changeset))
          end
      end
    else
      {:error, status, message} -> error_response(conn, status, message)
    end
  end

  # POST /api/games/:game_slug/characters/:id/release
  #
  # Called from Logout. Idempotent, and a release that finds nothing still
  # answers 200: the caller wanted the claim gone and it is gone. Logout runs
  # on paths that can overlap (a disconnect during a travel, a shutdown while
  # players are still leaving), and making those log failures would be noise
  # about a state that is already correct.
  def release_character(conn, %{"game_slug" => slug, "id" => id} = params) do
    with :ok <- require_server_auth(conn),
         {:ok, game} <- fetch_game(slug),
         {:ok, server} <- fetch_calling_server(game.id, params) do
      {:ok, released} =
        Games.release_character_session(game.id, id, server, params["session_id"])

      json(conn, %{success: true, released: released})
    else
      {:error, status, message} -> error_response(conn, status, message)
    end
  end

  # ---------------------------------------------------------------------
  # Server registry
  # ---------------------------------------------------------------------

  # GET /api/games/:game_slug/servers
  #
  # Readable by any authenticated player. Returns only servers with a recent
  # heartbeat and free capacity, least-loaded first, so a client that just
  # takes the head of the list gets a sensible answer.
  def list_servers(conn, %{"game_slug" => slug} = params) do
    with {:ok, game} <- fetch_game(slug) do
      opts =
        []
        |> maybe_opt(:region, params["region"])
        |> maybe_opt(:version, params["version"])
        |> Keyword.put(:include_full, params["include_full"] == "true")

      # World servers only. An instance server in this list would let a player
      # pick someone else's instance out of the browser and sidestep the access
      # check entirely.
      # DEV SHARDS (2026-10-14). A world server a developer runs from the
      # editor on their own machine heartbeats here like any other, and
      # without this it would be offered to - and auto-picked by - players.
      # Players never see one. An admin's editor asks with ?dev=1 and gets the
      # dev shards first, so PIE lands on the local server rather than live.
      {dev, live} = Enum.split_with(Games.list_world_servers(game.id, opts), &dev_server?/1)
      servers = if wants_dev_shards?(conn, params), do: dev ++ live, else: live

      json(conn, %{
        success: true,
        servers: Enum.map(servers, &server_json/1),
        recommended: servers |> List.first() |> server_json()
      })
    else
      {:error, status, message} -> error_response(conn, status, message)
    end
  end

  # The game sends "dev": true from an editor-run server; it is kept in
  # metadata so no column is needed. Only an exact true marks a shard dev.
  defp heartbeat_metadata(params) do
    base = if is_map(params["metadata"]), do: params["metadata"], else: %{}
    if params["dev"] == true, do: Map.put(base, "dev", true), else: Map.delete(base, "dev")
  end

  defp dev_server?(%{metadata: %{"dev" => true}}), do: true
  defp dev_server?(_), do: false

  defp wants_dev_shards?(conn, params) do
    params["dev"] in ["1", "true"] and
      conn.assigns[:games_auth_mode] == :player_token and
      match?(%{is_admin: true}, Guardian.Plug.current_resource(conn))
  end

  # POST /api/games/:game_slug/servers/heartbeat
  #
  # Server API key ONLY. A player token must never be able to write here: a
  # forged registration would advertise an attacker-controlled server to every
  # player browsing the list, which is phishing rather than cheating.
  def heartbeat_server(conn, %{"game_slug" => slug} = params) do
    with :ok <- require_server_auth(conn),
         {:ok, game} <- fetch_game(slug),
         {:ok, host} <- fetch_required(params, "host"),
         {:ok, port} <- fetch_required(params, "port") do
      attrs = %{
        "game_id" => game.id,
        "host" => host,
        "port" => port,
        "name" => params["name"] || "#{host}:#{port}",
        "region" => params["region"] || "unknown",
        "status" => params["status"] || "online",
        "current_players" => params["current_players"] || 0,
        "max_players" => params["max_players"] || 64,
        "map_name" => params["map_name"],
        "version" => params["version"],
        "metadata" => heartbeat_metadata(params),

        # WHO is on the server, not just how many. current_players above cannot
        # answer "which instance is this player in", which is the question the
        # admin section exists to answer.
        "roster" => normalize_roster(params["roster"]),

        # Set by an instance server so the hub can match it to its instance
        # and player. A world server omits both and stays a world server.
        "instance_id" => params["instance_id"],
        "launched_by_user_id" => params["launched_by_user_id"]
      }

      case Games.register_server(attrs) do
        {:ok, server} ->
          # SELF-HEALING FOR THE SESSION CLAIMS.
          #
          # The roster this heartbeat just reported is the authoritative answer
          # to "who is actually on this server", so anyone holding a claim here
          # who is not in it has left without the release landing - a crashed
          # logout path, a connection the server dropped without noticing, a
          # server restarted between the two calls. Reconciling on the request
          # they were already making means those free themselves within one
          # heartbeat instead of waiting out the 90 s staleness window.
          #
          # Deliberately passed `attrs["roster"]` (already normalised) rather
          # than the raw param: reconcile distinguishes "reported an empty
          # roster" from "reported no roster at all", and only the normaliser
          # knows which of those a malformed payload was.
          Games.reconcile_server_sessions(server, attrs["roster"])

          # THE CONTROL CHANNEL.
          #
          # The heartbeat response is the only route the hub has back into a
          # running instance - it may be behind NAT, in a pod with no ingress,
          # or started by hand on a desktop. Rather than a second transport for
          # admin actions, anything queued rides back on a request the server
          # was already making.
          commands =
            case Games.take_pending_commands(server.id) do
              {:ok, list} -> Enum.map(list, &command_json/1)
              _ -> []
            end

          json(conn, %{success: true, server: server_json(server), commands: commands})

        {:error, changeset} ->
          error_response(conn, 422, changeset_errors(changeset))
      end
    else
      {:error, status, message} -> error_response(conn, status, message)
    end
  end

  # POST /api/games/:game_slug/servers/offline - graceful shutdown.
  def deregister_server(conn, %{"game_slug" => slug} = params) do
    with :ok <- require_server_auth(conn),
         {:ok, game} <- fetch_game(slug),
         {:ok, host} <- fetch_required(params, "host"),
         {:ok, port} <- fetch_required(params, "port") do
      case Games.mark_server_offline(game.id, host, port) do
        {:ok, server} -> json(conn, %{success: true, server: server_json(server)})
        {:error, :not_found} -> error_response(conn, 404, "Server not registered")
        {:error, changeset} -> error_response(conn, 422, changeset_errors(changeset))
      end
    else
      {:error, status, message} -> error_response(conn, status, message)
    end
  end

  # ---------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------

  defp require_server_auth(conn) do
    case conn.assigns[:games_auth_mode] do
      :server_api_key -> :ok
      _ -> {:error, 403, "This endpoint requires a server API key"}
    end
  end

  # WHICH SERVER IS ASKING.
  #
  # Identified by host+port, the same pair the heartbeat upserts on, so there is
  # one notion of server identity across the whole API rather than a second id
  # the caller has to remember. A server that has not heartbeat yet has no row
  # and therefore no identity to claim with - that is a 409 rather than a 404
  # because it is a sequencing mistake on the caller's part, and the fix is to
  # heartbeat first, not to look for a different server.
  defp fetch_calling_server(game_id, params) do
    with {:ok, host} <- fetch_required(params, "host"),
         {:ok, port} <- fetch_required(params, "port") do
      case Games.get_server(game_id, host, normalize_port(port)) do
        nil ->
          {:error, 409, "Server #{host}:#{port} is not registered. Send a heartbeat first."}

        server ->
          {:ok, server}
      end
    end
  end

  # JSON gives us either; the column is an integer.
  defp normalize_port(port) when is_integer(port), do: port

  defp normalize_port(port) when is_binary(port) do
    case Integer.parse(port) do
      {value, _} -> value
      :error -> -1
    end
  end

  defp normalize_port(_), do: -1

  defp in_use_message(nil) do
    "This character is already signed in. Wait a moment and try again."
  end

  defp in_use_message(server) do
    "This character is already signed in on #{server.name}. " <>
      "Log out there first, or wait a moment and try again."
  end

  defp fetch_required(params, key) do
    case params[key] do
      nil -> {:error, 400, "#{key} is required"}
      "" -> {:error, 400, "#{key} is required"}
      value -> {:ok, value}
    end
  end

  defp maybe_opt(opts, _key, nil), do: opts
  defp maybe_opt(opts, _key, ""), do: opts
  defp maybe_opt(opts, key, value), do: Keyword.put(opts, key, value)

  defp server_json(nil), do: nil

  defp server_json(server) do
    %{
      id: server.id,
      name: server.name,
      host: server.host,
      port: server.port,
      address: "#{server.host}:#{server.port}",
      region: server.region,
      status: server.status,
      current_players: server.current_players,
      max_players: server.max_players,
      map_name: server.map_name,
      version: server.version,
      last_heartbeat_at: server.last_heartbeat_at,
      metadata: server.metadata,
      instance_id: server.instance_id
    }
  end

  defp command_json(command) do
    %{
      id: command.id,
      command: command.command,
      payload: command.payload,
      issued_at: command.issued_at
    }
  end

  @max_roster_entries 256

  # ACCEPTS EITHER SHAPE, STORES ONE.
  #
  # The wire is easier to write from C++ as a bare array; the column is a plain
  # :map so it cannot be one. Normalising here means the server does not have to
  # care and every reader sees %{"players" => [...]}.
  #
  # Capped because this is written straight into a jsonb column on a request the
  # server makes every few seconds. Heartbeats are authenticated with the server
  # key, so this is not a hostile input - but a bug in an instance should cost
  # one truncated roster, not an unbounded column written forever.
  defp normalize_roster(nil), do: %{}

  defp normalize_roster(players) when is_list(players) do
    %{"players" => players |> Enum.take(@max_roster_entries) |> Enum.map(&normalize_player/1)}
  end

  defp normalize_roster(%{"players" => players}) when is_list(players),
    do: normalize_roster(players)

  # Anything else - a string, a number, a map without "players" - is a client
  # that does not know the format. Dropped rather than stored, so a malformed
  # roster reads as "no roster" instead of poisoning the containment query that
  # finds players.
  defp normalize_roster(_), do: %{}

  defp normalize_player(%{} = player) do
    Map.take(player, ["user_id", "character_id", "name", "joined_at"])
  end

  defp normalize_player(_), do: %{}

  defp fetch_game(slug) do
    case Games.get_game_by_slug(slug) do
      nil -> {:error, 404, "Unknown game: #{slug}"}
      game -> if game.is_active, do: {:ok, game}, else: {:error, 403, "Game is not active"}
    end
  end

  # Player token mode: user_id comes from the authenticated resource.
  # Server API key mode: user_id must be supplied explicitly by the trusted server.
  defp resolve_user_id(conn, params) do
    case conn.assigns[:games_auth_mode] do
      :player_token ->
        {:ok, Guardian.Plug.current_resource(conn).id}

      :server_api_key ->
        case params["user_id"] do
          nil -> {:error, 400, "user_id is required when authenticating via server API key"}
          user_id -> {:ok, user_id}
        end
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp character_json(character) do
    %{
      id: character.id,
      game_id: character.game_id,
      name: character.name,
      stats: character.stats,
      settings: character.settings,
      # Resume-in-instance: non-null means "the last session ended inside this
      # instance" - the client routes the next login there.
      instance_id: character.instance_id,
      instance_location: character.instance_location,
      last_played_at: character.last_played_at,
      inserted_at: character.inserted_at,
      updated_at: character.updated_at
    }
  end

  defp changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end

  defp error_response(conn, status, message) do
    conn
    |> put_status(status)
    |> json(%{success: false, message: message})
  end
end

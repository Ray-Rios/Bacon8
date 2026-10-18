defmodule Bacon8.Games do
  @moduledoc """
  Context for the multiplayer games platform: games, characters, the server
  registry, client releases. Game-specific logic lives in each game's plugin.

  Backed by `Bacon8.GamesRepo`, a database isolated from the main site's
  `Bacon8.Repo`. Player identity (`user_id`) always comes from the main
  app's Guardian-authenticated `users` table; this context never touches
  passwords or emails.
  """

  import Ecto.Query, warn: false
  alias Bacon8.GamesRepo
  alias Bacon8.Games.{AdminAction, Game, GameCharacter, GameServer, ServerCommand}

  @doc """
  Seconds without a heartbeat before a server is treated as gone.

  Deliberately several times the client's heartbeat interval. Set it too tight
  and one slow request drops a healthy, populated shard out of the browser.
  """
  def server_stale_after_seconds do
    Application.get_env(:bacon8, :game_server_stale_after_seconds, 90)
  end

  # ---------------------------------------------------------------------
  # Games
  # ---------------------------------------------------------------------

  def list_games do
    GamesRepo.all(Game)
  end

  def get_game_by_slug(slug) do
    GamesRepo.get_by(Game, slug: slug)
  end

  def get_game_by_slug!(slug) do
    GamesRepo.get_by!(Game, slug: slug)
  end

  def create_game(attrs) do
    %Game{}
    |> Game.changeset(attrs)
    |> GamesRepo.insert()
  end

  # ---------------------------------------------------------------------
  # Game Characters
  # ---------------------------------------------------------------------

  @doc "List all of a user's characters for a given game."
  def list_characters(game_id, user_id) do
    GameCharacter
    |> where([c], c.game_id == ^game_id and c.user_id == ^user_id)
    |> order_by([c], desc: c.last_played_at)
    |> GamesRepo.all()
  end

  def get_character(id), do: GamesRepo.get(GameCharacter, id)

  def get_character!(id), do: GamesRepo.get!(GameCharacter, id)

  @doc "Fetch a character, scoped to the owning user (prevents cross-account access)."
  def get_owned_character(game_id, user_id, character_id) do
    GameCharacter
    |> where([c], c.id == ^character_id and c.game_id == ^game_id and c.user_id == ^user_id)
    |> GamesRepo.one()
  end

  def create_character(attrs) do
    %GameCharacter{}
    |> GameCharacter.changeset(attrs)
    |> GamesRepo.insert()
  end

  @doc "Persist updated stats/settings, e.g. periodic checkpoint or on-disconnect save."
  def update_character(%GameCharacter{} = character, attrs) do
    character
    |> GameCharacter.changeset(attrs)
    |> GamesRepo.update()
  end

  @doc """
  Record (or clear, with a nil instance id) where a character should resume.

  Server-key only in the controller, except that a player may clear their own.
  Bare `change/2`, deliberately bypassing GameCharacter.changeset/2 - these
  fields are not castable from player input, and that changeset is the player
  input path.
  """
  def set_instance_location(game_id, user_id, character_id, instance_id, location \\ nil) do
    case get_owned_character(game_id, user_id, character_id) do
      nil ->
        {:error, :not_found}

      character ->
        character
        |> Ecto.Changeset.change(
          instance_id: instance_id,
          instance_location: if(instance_id, do: location, else: nil)
        )
        |> Ecto.Changeset.foreign_key_constraint(:instance_id)
        |> GamesRepo.update()
    end
  end

  def touch_character_last_played(%GameCharacter{} = character) do
    update_character(character, %{last_played_at: DateTime.utc_now() |> DateTime.truncate(:second)})
  end

  def delete_character(%GameCharacter{} = character) do
    GamesRepo.delete(character)
  end

  # ---------------------------------------------------------------------
  # Single-session enforcement
  #
  # A character may be in at most one live world or instance at a time.
  #
  # THE PROBLEM THIS SOLVES IS DATA LOSS, NOT CHEATING. Without a claim, a
  # game server that approves joins on its own access rules alone lets one
  # character be signed in from several clients at once (seen in practice).
  # Servers write a position checkpoint back here on Logout, so two sessions
  # racing one character means whichever leaves last silently overwrites the
  # other's progress.
  #
  # THREE THINGS RELEASE A CLAIM, and the redundancy is deliberate because each
  # one covers a failure the others cannot:
  #
  #   1. The server calls release when the player logs out. Immediate, and the
  #      normal case - a dedicated server sees a dropped connection right away.
  #   2. Heartbeat roster reconciliation. Every heartbeat carries who is on the
  #      server; anyone holding a claim there who is NOT in that roster is
  #      released. This covers a server that forgot to release, or lost the
  #      player without running its logout path, and self-heals within one
  #      heartbeat interval (~20 s).
  #   3. Server staleness. A claim held by a server whose heartbeat has gone
  #      quiet is simply not honoured, so a crashed shard cannot lock its
  #      players out of their own characters. Reuses `server_stale?/1`, so
  #      there is still exactly ONE definition of "alive" in this context.
  #
  # Without (2) and (3), the first crash of anything anywhere would leave a
  # character permanently unplayable with no way for the player to clear it.
  # ---------------------------------------------------------------------

  @doc """
  Claim a character for a server session. The join gate.

  Atomic by construction: the claimable test lives in the WHERE clause of a
  single UPDATE rather than in a read-then-write, so two clients racing the
  same character cannot both pass it. Exactly one row is affected or none is.

  Deliberately NOT relaxed for "the same server asking again". That looks like
  a harmless convenience - a reconnect to the shard you just dropped from -
  but every PIE client connects to the same world server on 127.0.0.1:7777, so
  a same-server exemption would make this a no-op in exactly the setup it most
  needs to work in. A genuine reconnect is covered by release-on-logout, and a
  hard drop by roster reconciliation, both of which free the claim properly
  rather than looking the other way.

  Returns:
    * `{:ok, %{character: character, session_id: id}}`
    * `{:error, :not_found}`     - no such character, or not this user's
    * `{:error, {:in_use, server_or_nil}}` - live session elsewhere
  """
  def claim_character_session(game_id, user_id, character_id, %GameServer{} = server) do
    with {:ok, id} <- cast_uuid(character_id) do
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      session_id = Ecto.UUID.generate()

      # The live-server set is read FIRST and passed in as a plain list, rather
      # than embedded as a subquery, and the atomicity that matters survives
      # that. The race this function has to win is two clients claiming one
      # character at the same instant, and that is decided entirely inside the
      # single UPDATE below - Postgres evaluates its WHERE against the row
      # under lock, so exactly one of them can see it as claimable.
      #
      # What the two-step does expose is a much smaller race: a server could go
      # stale in the microseconds between the read and the update. The cost is
      # refusing one claim we could have granted, on a request the player will
      # retry - which is the harmless direction to be wrong in.
      live = live_server_ids(game_id)

      query =
        from(c in GameCharacter,
          where: c.id == ^id and c.game_id == ^game_id and c.user_id == ^user_id,
          # Claimable when nobody holds it, or when whoever does is not a
          # server we still believe in.
          where: is_nil(c.active_server_id) or c.active_server_id not in ^live
        )

      case GamesRepo.update_all(query,
             set: [
               active_server_id: server.id,
               active_session_id: session_id,
               session_started_at: now,
               session_last_seen_at: now,
               updated_at: now
             ]
           ) do
        {1, _} ->
          {:ok, %{character: get_character(id), session_id: session_id}}

        {0, _} ->
          # Nothing matched. Two very different reasons, and the caller needs
          # to tell them apart to say anything useful to the player.
          case get_owned_character(game_id, user_id, id) do
            nil ->
              {:error, :not_found}

            held ->
              holder = held.active_server_id && GamesRepo.get(GameServer, held.active_server_id)
              {:error, {:in_use, holder}}
          end
      end
    end
  end

  @doc """
  Release a claim. Called on logout, and by the graceful-shutdown path.

  A server may release either by presenting the `session_id` it was given, or
  by being the server that currently holds the claim. The second form is what
  lets a restarted server clean up sessions whose tokens died with its previous
  process; the first is what stops any OTHER server dropping a claim it does
  not hold just because it knows the character id.

  ALWAYS returns `{:ok, released_count}`, including for an id that is not even
  a UUID. Zero is not an error: a release that finds nothing has got what it
  wanted. Logout paths overlap by nature - a disconnect during a level travel,
  a shutdown while players are still leaving - and a caller that has to
  distinguish "already released" from "failed" will either log noise about a
  state that is already correct or, worse, retry.
  """
  def release_character_session(game_id, character_id, %GameServer{} = server, session_id \\ nil) do
    case cast_uuid(character_id) do
      {:error, _} ->
        {:ok, 0}

      {:ok, id} ->
        do_release_character_session(game_id, id, server, session_id)
    end
  end

  defp do_release_character_session(game_id, id, %GameServer{} = server, session_id) do
    base = from(c in GameCharacter, where: c.id == ^id and c.game_id == ^game_id)

    query =
      case cast_uuid(session_id) do
        {:ok, sid} ->
          from(c in base,
            where: c.active_session_id == ^sid or c.active_server_id == ^server.id
          )

        _ ->
          from(c in base, where: c.active_server_id == ^server.id)
      end

    {count, _} = GamesRepo.update_all(query, set: clear_session_fields())
    {:ok, count}
  end

  @doc """
  Reconcile one server's claims against the roster it just reported.

  Anyone holding a claim on this server who is not in the roster has left
  without the release landing, so the claim goes. Anyone still there has their
  `session_last_seen_at` refreshed, which is what makes that column mean
  something on an admin screen.

  A SERVER THAT REPORTS NO ROSTER AT ALL IS LEFT ALONE. That distinction is the
  whole safety of this function: `%{}` means "this build does not send a
  roster" and `%{"players" => []}` means "nobody is here". Treating the first
  as the second would release every claim on the server on every heartbeat and
  quietly turn the feature off - the same trap `server_players/1` sidesteps.
  """
  def reconcile_server_sessions(%GameServer{} = server, %{"players" => players})
      when is_list(players) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    present =
      players
      |> Enum.map(fn
        %{"character_id" => cid} -> cid
        _ -> nil
      end)
      |> Enum.map(&cast_uuid/1)
      |> Enum.flat_map(fn
        {:ok, id} -> [id]
        _ -> []
      end)

    held = from(c in GameCharacter, where: c.active_server_id == ^server.id)

    {dropped, _} =
      case present do
        [] ->
          GamesRepo.update_all(held, set: clear_session_fields())

        ids ->
          held
          |> where([c], c.id not in ^ids)
          |> GamesRepo.update_all(set: clear_session_fields())
      end

    if present != [] do
      held
      |> where([c], c.id in ^present)
      |> GamesRepo.update_all(set: [session_last_seen_at: now, updated_at: now])
    end

    {:ok, dropped}
  end

  def reconcile_server_sessions(%GameServer{}, _no_roster), do: {:ok, 0}

  @doc """
  Release every claim held by a server. Used on graceful shutdown.

  A crashed server does not reach this, which is what rule (3) above is for.
  """
  def release_server_sessions(%GameServer{} = server) do
    {count, _} =
      GameCharacter
      |> where([c], c.active_server_id == ^server.id)
      |> GamesRepo.update_all(set: clear_session_fields())

    {:ok, count}
  end

  @doc """
  The live session on a character, or nil.

  Nil for an unclaimed character AND for one whose claim is held by a server we
  no longer believe in - callers should not have to know the difference, and
  every one of them wants the same answer: is anybody actually playing this
  right now.
  """
  def character_session(%GameCharacter{active_server_id: nil}), do: nil

  def character_session(%GameCharacter{} = character) do
    case GamesRepo.get(GameServer, character.active_server_id) do
      nil -> nil
      server -> if server_stale?(server), do: nil, else: server
    end
  end

  # Servers whose heartbeat is fresh enough that a claim of theirs still counts.
  #
  # Ids of every registered server for the game are bounded by how many shards
  # exist, which is a handful - this is not a list that can grow with players.
  defp live_server_ids(game_id) do
    cutoff =
      DateTime.utc_now()
      |> DateTime.add(-server_stale_after_seconds(), :second)
      |> DateTime.truncate(:second)

    GameServer
    |> where([s], s.game_id == ^game_id and s.last_heartbeat_at >= ^cutoff)
    |> select([s], s.id)
    |> GamesRepo.all()
  end

  # The timestamps are deliberately NOT cleared - see the schema comment. What
  # makes a session dead is active_server_id going null; the times left behind
  # are the trace of the session that just ended.
  defp clear_session_fields do
    [
      active_server_id: nil,
      active_session_id: nil,
      updated_at: DateTime.utc_now() |> DateTime.truncate(:second)
    ]
  end

  # A character or session id arriving from an API request is just a string.
  # Ecto raises Ecto.Query.CastError on a malformed binary_id in a where
  # clause, which would surface as a 500 on what is really a 404, so every id
  # is checked before it reaches a query.
  defp cast_uuid(value) when is_binary(value) do
    case Ecto.UUID.cast(value) do
      {:ok, id} -> {:ok, id}
      :error -> {:error, :not_found}
    end
  end

  defp cast_uuid(_), do: {:error, :not_found}

  # ---------------------------------------------------------------------
  # Game Servers (shard registry)
  # ---------------------------------------------------------------------

  @doc """
  Upsert a dedicated server's registration from its heartbeat.

  Keyed on `{game_id, host, port}` so a server that restarts reclaims its own
  row instead of leaving a stale duplicate behind.
  """
  def register_server(attrs) do
    attrs =
      attrs
      |> Map.put("last_heartbeat_at", DateTime.utc_now() |> DateTime.truncate(:second))

    changeset = GameServer.changeset(%GameServer{}, attrs)

    # Only the volatile fields are refreshed on conflict. `inserted_at` and the
    # row id are left alone so a server keeps a stable identity across restarts.
    GamesRepo.insert(changeset,
      on_conflict:
        {:replace,
         [
           :name,
           :region,
           :status,
           :current_players,
           :max_players,
           :map_name,
           :version,
           :last_heartbeat_at,
           :metadata,
           :roster,
           :instance_id,
           :launched_by_user_id,
           :updated_at
         ]},
      conflict_target: [:game_id, :host, :port],
      returning: true
    )
  end

  # ---------------------------------------------------------------------
  # Instance servers
  # ---------------------------------------------------------------------

  @doc """
  The live server running this instance, if there is one.

  Keyed on the INSTANCE, not on a player. Many people can be in one instance
  at once, so a server belongs to the instance it is running - whoever opened
  the door first is attribution, not ownership.

  This is what lets a second player join an instance that is already running,
  and the first walk out and back in without starting a second server.

  Filters on heartbeat freshness: a crashed pod leaves its row behind and would
  otherwise make an instance permanently unlaunchable.
  """
  def get_instance_server(game_id, instance_id) do
    cutoff =
      DateTime.utc_now()
      |> DateTime.add(-server_stale_after_seconds(), :second)
      |> DateTime.truncate(:second)

    GameServer
    |> where([s], s.game_id == ^game_id and s.instance_id == ^instance_id)
    |> where([s], s.status in ["online", "draining"])
    |> where([s], s.last_heartbeat_at >= ^cutoff)
    |> order_by([s], desc: s.last_heartbeat_at)
    |> limit(1)
    |> GamesRepo.one()
  end

  @doc """
  World servers only - instances are excluded from the public browser.

  Without this an instance would show up as a joinable shard in the character
  select screen, and a player could sidestep the whole access check by picking
  someone else's pod out of a list.
  """
  def list_world_servers(game_id, opts \\ []) do
    game_id
    |> list_available_servers(opts)
    |> Enum.filter(&is_nil(&1.instance_id))
  end

  @doc """
  Servers a player may join right now.

  Filters on a recent heartbeat rather than on `status` alone, because a
  crashed server leaves its last known status as `online` forever.

  Options:
    * `:region`          - restrict to one region
    * `:version`         - restrict to a build; clients on a different build
                           must not be offered a server they cannot join
    * `:include_full`    - default false
  """
  def list_available_servers(game_id, opts \\ []) do
    cutoff =
      DateTime.utc_now()
      |> DateTime.add(-server_stale_after_seconds(), :second)
      |> DateTime.truncate(:second)

    GameServer
    |> where([s], s.game_id == ^game_id)
    |> where([s], s.status == "online")
    |> where([s], s.last_heartbeat_at >= ^cutoff)
    |> maybe_filter(:region, opts[:region])
    |> maybe_filter(:version, opts[:version])
    |> maybe_exclude_full(Keyword.get(opts, :include_full, false))
    |> order_by([s], asc: s.current_players, asc: s.name)
    |> GamesRepo.all()
  end

  @doc """
  The single best server to drop a player into — least loaded that still has
  room. Returns nil when nothing is available, which callers must handle:
  "no servers online" is a normal state during a deploy, not an error.
  """
  def get_best_server(game_id, opts \\ []) do
    game_id
    |> list_available_servers(opts)
    |> List.first()
  end

  @doc "Every registered server for a game, including stale ones. For admin views."
  def list_all_servers(game_id) do
    GameServer
    |> where([s], s.game_id == ^game_id)
    |> order_by([s], asc: s.region, asc: s.name)
    |> GamesRepo.all()
  end

  def get_server(game_id, host, port) do
    GamesRepo.get_by(GameServer, game_id: game_id, host: host, port: port)
  end

  @doc "Graceful shutdown. Marks offline rather than deleting, so history survives."
  def mark_server_offline(game_id, host, port) do
    case get_server(game_id, host, port) do
      nil ->
        {:error, :not_found}

      server ->
        # A server going down takes its character claims with it. Without this
        # a clean shutdown would leave everyone who was on it locked out of
        # their own characters until the staleness window expired - which is
        # the worst of both worlds, since the one case where we KNOW the
        # session ended is the one where we could react instantly.
        {:ok, _released} = release_server_sessions(server)

        server
        |> GameServer.changeset(%{
          "status" => "offline",
          "current_players" => 0,
          "last_heartbeat_at" => DateTime.utc_now() |> DateTime.truncate(:second)
        })
        |> GamesRepo.update()
    end
  end

  @doc """
  Delete rows that have not reported in for a long time.

  Not required for correctness — `list_available_servers` already ignores
  them — but keeps an admin listing readable. Safe to run from a cron/scheduler.
  """
  def prune_stale_servers(older_than_seconds \\ 86_400) do
    cutoff =
      DateTime.utc_now()
      |> DateTime.add(-older_than_seconds, :second)
      |> DateTime.truncate(:second)

    {count, _} =
      GameServer
      |> where([s], s.last_heartbeat_at < ^cutoff)
      |> GamesRepo.delete_all()

    {:ok, count}
  end

  @doc """
  Delete instance server rows that are dead (2026-10-10).

  An instance is a process that lives minutes, and every launch can take a new
  port - so its `game_servers` row is worthless once it stops heartbeating, and
  leaving them made the admin list fill with "Stale" copies of every instance.
  Worse, a game that deletes an instance may NILIFY `instance_id` on its rows
  (with an ON DELETE SET NULL foreign key), which turns a dead instance server into
  what looks like a stale WORLD server.

  So: a row is an instance if it has an instance id OR sits in the instance port range,
  and an instance row that is offline or stale is deleted. World servers are
  untouched - for them, "stale" is information an admin wants to see.
  """
  def prune_dead_instances(game_id, {port_min, port_max}) do
    cutoff =
      DateTime.utc_now()
      |> DateTime.add(-server_stale_after_seconds(), :second)
      |> DateTime.truncate(:second)

    {count, _} =
      GameServer
      |> where([s], s.game_id == ^game_id)
      |> where([s], not is_nil(s.instance_id) or (s.port >= ^port_min and s.port <= ^port_max))
      |> where([s], s.status == "offline" or s.last_heartbeat_at < ^cutoff or is_nil(s.last_heartbeat_at))
      |> GamesRepo.delete_all()

    {:ok, count}
  end

  @doc "Delete every server row belonging to one instance - live or not. Used when the instance is deleted."
  def delete_instance_rows(instance_id) do
    {count, _} =
      GameServer
      |> where([s], s.instance_id == ^instance_id)
      |> GamesRepo.delete_all()

    {:ok, count}
  end

  @doc """
  Flip stale `online` rows to `offline`.

  The softer half of `prune_stale_servers/1`, and the one an admin screen wants:
  deleting a crashed instance makes it vanish with no explanation, which is
  indistinguishable from it never having existed. Marking it offline leaves the
  row, its last heartbeat and its final roster visible until pruning eventually
  clears it.

  Returns the number of rows changed.
  """
  def mark_stale_servers_offline(stale_after_seconds \\ nil) do
    seconds = stale_after_seconds || server_stale_after_seconds()

    cutoff =
      DateTime.utc_now()
      |> DateTime.add(-seconds, :second)
      |> DateTime.truncate(:second)

    {count, _} =
      GameServer
      |> where([s], s.status in ["online", "draining"])
      |> where([s], s.last_heartbeat_at < ^cutoff)
      |> GamesRepo.update_all(set: [status: "offline", current_players: 0])

    {:ok, count}
  end

  # ---------------------------------------------------------------------
  # Admin operations
  #
  # Everything below is read or written by the /admin section, never by a
  # player. The command functions are the exception that proves it: they are
  # written by an admin and READ by a server, on its own heartbeat.
  # ---------------------------------------------------------------------

  @doc """
  Every server for a game, freshest first, regardless of status.

  Deliberately unfiltered - the whole point of the admin view is to see the
  offline and stale ones, which every player-facing query hides.
  """
  def list_servers_for_admin(game_id) do
    GameServer
    |> where([s], s.game_id == ^game_id)
    |> order_by([s], desc: s.last_heartbeat_at)
    |> GamesRepo.all()
  end

  @doc """
  True if this server's last heartbeat is too old to believe.

  The single place that judgement is made, so the admin list, the reaper and
  the instance lookup cannot disagree about what "alive" means.
  """
  def server_stale?(%GameServer{last_heartbeat_at: nil}), do: true

  def server_stale?(%GameServer{last_heartbeat_at: at}) do
    DateTime.diff(DateTime.utc_now(), at, :second) > server_stale_after_seconds()
  end

  @doc """
  The players a server reported on its last heartbeat.

  Returns `[]` for a server that has never reported one, so callers do not have
  to distinguish "empty" from "old build that does not send a roster".
  """
  def server_players(%GameServer{roster: %{"players" => players}}) when is_list(players), do: players
  def server_players(%GameServer{}), do: []

  @doc """
  Which server a user is currently on, if any.

  Answers "where is this player right now" - the question a count cannot.
  Containment against the jsonb roster, which the GIN index on that column
  turns into a lookup rather than a scan across every instance.

  Stale servers are excluded: a roster from a pod that died is a memory, not a
  location.
  """
  def find_player_server(game_id, user_id) when is_binary(user_id) do
    cutoff =
      DateTime.utc_now()
      |> DateTime.add(-server_stale_after_seconds(), :second)
      |> DateTime.truncate(:second)

    GameServer
    |> where([s], s.game_id == ^game_id)
    |> where([s], s.last_heartbeat_at >= ^cutoff)
    |> where(
      [s],
      fragment("? @> ?", s.roster, ^%{"players" => [%{"user_id" => user_id}]})
    )
    |> limit(1)
    |> GamesRepo.one()
  end

  @doc """
  Queue a command for a server. It is delivered on that server's next heartbeat.

  Not delivered here, and deliberately not awaited: the hub cannot reach into an
  instance, so "issued" is the strongest thing this can honestly report. The
  caller should surface `delivered_at` rather than implying the button worked.
  """
  def queue_server_command(server_id, command, payload \\ %{}, issued_by_user_id \\ nil) do
    %ServerCommand{}
    |> ServerCommand.changeset(%{
      "server_id" => server_id,
      "command" => command,
      "payload" => payload,
      "issued_by_user_id" => issued_by_user_id,
      "issued_at" => DateTime.utc_now() |> DateTime.truncate(:second)
    })
    |> GamesRepo.insert()
  end

  @doc """
  Hand a server its undelivered commands and mark them delivered.

  AT-MOST-ONCE, on purpose. The alternative is holding them until the server
  acknowledges, which turns a missed response into a command that runs twice -
  and "kick" and "shutdown" are both considerably worse when repeated than when
  dropped. An admin can press the button again; they cannot un-kick anyone.

  Read and mark happen in one transaction so two overlapping heartbeats from a
  restarting server cannot both collect the same instruction.
  """
  def take_pending_commands(server_id) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    GamesRepo.transaction(fn ->
      commands =
        ServerCommand
        |> where([c], c.server_id == ^server_id and is_nil(c.delivered_at))
        |> order_by([c], asc: c.issued_at)
        |> lock("FOR UPDATE SKIP LOCKED")
        |> GamesRepo.all()

      ids = Enum.map(commands, & &1.id)

      if ids != [] do
        ServerCommand
        |> where([c], c.id in ^ids)
        |> GamesRepo.update_all(set: [delivered_at: now, updated_at: now])
      end

      commands
    end)
  end

  @doc "Commands issued to a server, newest first. For the admin detail view."
  def list_server_commands(server_id, limit \\ 25) do
    ServerCommand
    |> where([c], c.server_id == ^server_id)
    |> order_by([c], desc: c.issued_at)
    |> limit(^limit)
    |> GamesRepo.all()
  end

  @doc "Record a privileged action. Never fails the operation it describes."
  def log_admin_action(attrs) do
    %AdminAction{}
    |> AdminAction.changeset(attrs)
    |> GamesRepo.insert()
  end

  @doc "Recent admin actions, newest first."
  def list_admin_actions(limit \\ 50) do
    AdminAction
    |> order_by([a], desc: a.inserted_at)
    |> limit(^limit)
    |> GamesRepo.all()
  end

  defp maybe_filter(query, _field, nil), do: query
  defp maybe_filter(query, :region, region), do: where(query, [s], s.region == ^region)
  defp maybe_filter(query, :version, version), do: where(query, [s], s.version == ^version)

  defp maybe_exclude_full(query, true), do: query
  defp maybe_exclude_full(query, false), do: where(query, [s], s.current_players < s.max_players)
end

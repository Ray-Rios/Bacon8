defmodule Bacon8Web.Api.PixelStreamingController do
  use Bacon8Web, :controller
  
  def status(conn, _params) do
    json(conn, %{
      streamerConnected: true,
      viewerCount: get_viewer_count(),
      timestamp: DateTime.utc_now(),
      gameStatus: "running",
      message: "Game server is running",
      serverStats: get_server_stats(),
      activePlayers: get_active_players_summary()
    })
  end

  def players(conn, _params) do
    json(conn, %{
      total: get_player_count(),
      online: get_online_players(),
      recent_events: get_recent_player_events()
    })
  end

  def game_data(conn, _params) do
    json(conn, %{
      world: %{
        name: "Infinite World",
        zones: [
          %{name: "Darkwood Forest", players: 23, difficulty: "medium"},
          %{name: "Crystal Caves", players: 15, difficulty: "hard"},
          %{name: "Ancient Ruins", players: 8, difficulty: "expert"},
          %{name: "Temple District", players: 31, difficulty: "easy"},
          %{name: "Northern Territories", players: 12, difficulty: "hard"}
        ]
      },
      economy: %{
        total_gold: 15_420_000,
        items_traded_today: 1_247,
        auction_house_listings: 892
      },
      guilds: get_guild_summary(),
      events: get_current_events()
    })
  end

  def admin_stats(conn, _params) do
    # This should be protected by admin auth in production
    json(conn, %{
      system: %{
        uptime_seconds: :erlang.statistics(:wall_clock) |> elem(0) |> div(1000),
        memory_usage: :erlang.memory(:total),
        process_count: :erlang.system_info(:process_count),
        connected_nodes: Node.list()
      },
      database: %{
        active_connections: get_db_connection_count(),
        query_performance: get_db_performance_stats()
      },
      game_servers: get_detailed_server_stats()
    })
  end

  def broadcast_message(conn, %{"message" => message, "type" => type}) do
    # Broadcast to all connected players
    Phoenix.PubSub.broadcast(Bacon8.PubSub, "game:global", {
      :system_message, 
      %{message: message, type: type, timestamp: DateTime.utc_now()}
    })
    # Also publish to Redis so other pods receive it
    Bacon8.RedisPubSub.publish("game:global", {:system_message, %{message: message, type: type, timestamp: DateTime.utc_now()}})
    
    json(conn, %{success: true, message: "Message broadcasted"})
  end

  def kick_player(conn, %{"player_id" => player_id}) do
    # Implement player kick logic
    case kick_player_from_game(player_id) do
      :ok ->
        json(conn, %{success: true, message: "Player kicked successfully"})
    end
  end

  # Helper functions
  defp get_viewer_count, do: :rand.uniform(5) + 1
  
  defp get_server_stats do
    %{
      cpu_usage: :rand.uniform(30) + 10,
      memory_mb: :rand.uniform(500) + 1000,
      network_in: :rand.uniform(1000) + 500,
      network_out: :rand.uniform(800) + 400,
      active_connections: :rand.uniform(100) + 200
    }
  end

  defp get_active_players_summary do
    [
      %{username: "DragonSlayer", level: 45, zone: "Darkwood Forest"},
      %{username: "MysticMage", level: 38, zone: "Crystal Caves"},
      %{username: "ShadowRogue", level: 52, zone: "Ancient Ruins"},
      %{username: "HolyPriest", level: 41, zone: "Temple District"}
    ]
  end

  defp get_player_count, do: :rand.uniform(50) + 200

  defp get_online_players do
    Enum.map(1..(:rand.uniform(10) + 5), fn i ->
      %{
        id: i,
        username: "Player#{i}",
        level: :rand.uniform(60) + 1,
        class: Enum.random(["Warrior", "Mage", "Rogue", "Priest", "Archer"]),
        zone: Enum.random(["Darkwood Forest", "Crystal Caves", "Ancient Ruins", "Temple District"]),
        online_time: "#{:rand.uniform(4)}h #{:rand.uniform(60)}m"
      }
    end)
  end

  defp get_recent_player_events do
    [
      %{type: "player_join", message: "DragonSlayer joined the server", timestamp: DateTime.utc_now()},
      %{type: "level_up", message: "MysticMage reached level 39", timestamp: DateTime.utc_now()},
      %{type: "quest_complete", message: "ShadowRogue completed 'The Lost Artifact'", timestamp: DateTime.utc_now()},
      %{type: "pvp_kill", message: "WarriorX defeated GoblinSlayer in PvP", timestamp: DateTime.utc_now()}
    ]
  end

  defp get_guild_summary do
    [
      %{name: "Dragon Hunters", members: 35, level: 12},
      %{name: "Shadow Legion", members: 28, level: 8},
      %{name: "Crystal Guardians", members: 42, level: 15},
      %{name: "Fire Warriors", members: 19, level: 6}
    ]
  end

  defp get_current_events do
    [
      %{name: "Double XP Weekend", active: true, ends_at: DateTime.add(DateTime.utc_now(), 2 * 24 * 3600)},
      %{name: "Dragon Raid Event", active: true, ends_at: DateTime.add(DateTime.utc_now(), 7 * 24 * 3600)},
      %{name: "Guild Wars", active: false, starts_at: DateTime.add(DateTime.utc_now(), 3 * 24 * 3600)}
    ]
  end

  defp get_db_connection_count, do: :rand.uniform(20) + 5
  
  defp get_db_performance_stats do
    %{
      avg_query_time_ms: :rand.uniform(50) + 10,
      slow_queries: :rand.uniform(5),
      total_queries_today: :rand.uniform(10000) + 50000
    }
  end

  defp get_detailed_server_stats do
    [
      %{
        id: 1,
        name: "Main Server",
        status: "online",
        players: :rand.uniform(80) + 20,
        cpu_usage: :rand.uniform(25) + 10,
        memory_mb: :rand.uniform(400) + 800,
        uptime_hours: :rand.uniform(100) + 50
      },
      %{
        id: 2,
        name: "PvP Server", 
        status: "online",
        players: :rand.uniform(40) + 10,
        cpu_usage: :rand.uniform(20) + 8,
        memory_mb: :rand.uniform(300) + 600,
        uptime_hours: :rand.uniform(80) + 30
      }
    ]
  end

  defp kick_player_from_game(_player_id) do
    # Simulate player kick - in real implementation this would:
    # 1. Find the player's active session
    # 2. Send disconnect message to game server
    # 3. Update player status in database
    # 4. Broadcast event to other players
    :ok
  end
end
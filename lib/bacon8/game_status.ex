defmodule Bacon8.GameStatus do
  @moduledoc """
  The games' live status for the front page's corner (2026-10-29, `Bacon8Web.Components.GameTicker`):
  for every active plugin game with a card, its name, the card's first picture, whether it is up,
  its zones or servers, how many play now and how many ever have.

  Where the numbers come from:

    * the plugin's `game_stats/0` when it has one (Bacon World: its zones, Presence in each, the
      creatures' zone process);
    * otherwise the hub's own records: world servers with a recent heartbeat (`game_servers`;
      editor-run dev shards left out) are the zones, running instances add up as one line
      ("Holo-sims"), and `current_players` is what their heartbeats report.

  `total_players` is the number of accounts with a character in the game, unless the plugin says
  otherwise.

  `snapshot/0` is cached for `@ttl_ms` in an ETS table this process owns, so a crowd on the front
  page costs one computation every 15 seconds, not one per visitor. The caller computes (so the
  database sandbox in tests sees the caller); the process only owns the table.
  """
  use GenServer
  require Logger
  import Ecto.Query

  alias Bacon8.{GameCards, Games, GamesRepo, Plugins}
  alias Bacon8.Games.GameCharacter

  @table :bacon8_game_status
  @ttl_ms 15_000

  def start_link(_opts), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @impl true
  def init(nil) do
    :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
    {:ok, nil}
  end

  @doc "How often the corner refreshes, in milliseconds."
  def ttl_ms, do: @ttl_ms

  @doc """
  Every active game's status, in the order of /games. `fresh: true` skips the cache.

      %{slug:, name:, image:, href:, online:, zones: [%{name:, online:, players:}],
        current_players:, total_players:}
  """
  def snapshot(opts \\ []) do
    now = System.monotonic_time(:millisecond)

    case !opts[:fresh] && cached() do
      {at, list} when now - at < @ttl_ms ->
        list

      _ ->
        list = compute()
        if :ets.whereis(@table) != :undefined, do: :ets.insert(@table, {:snapshot, now, list})
        list
    end
  end

  defp cached do
    if :ets.whereis(@table) != :undefined do
      case :ets.lookup(@table, :snapshot) do
        [{:snapshot, at, list}] -> {at, list}
        _ -> nil
      end
    end
  end

  defp compute do
    Plugins.active()
    |> Enum.flat_map(fn mod ->
      case Plugins.game_info(mod) do
        nil -> []
        info -> [entry(mod, info)]
      end
    end)
  end

  defp entry(mod, info) do
    card = safe(fn -> GameCards.get(mod.slug()) end, nil)
    stats = plugin_stats(mod) || hub_stats(info.slug)

    total =
      case stats do
        %{total_players: n} when is_integer(n) -> n
        _ -> total_players(info.slug)
      end

    %{
      slug: mod.slug(),
      name: info[:name] || mod.name(),
      image: card && (List.first(card.fronts) || card.back),
      href: (card && card.play_path) || info[:path] || "/games",
      online: stats[:online] == true,
      zones: stats[:zones] || [],
      current_players: stats[:current_players] || 0,
      total_players: total
    }
  end

  defp plugin_stats(mod) do
    safe(
      fn ->
        case mod.game_stats() do
          %{} = s -> s
          _ -> nil
        end
      end,
      nil
    )
  end

  # The hub's records: world servers with a recent heartbeat are the zones; instances add up.
  defp hub_stats(game_slug) do
    safe(
      fn ->
        case Games.get_game_by_slug(game_slug) do
          nil ->
            %{online: false, zones: [], current_players: 0}

          game ->
            servers = game.id |> Games.list_available_servers(include_full: true) |> Enum.reject(&match?(%{metadata: %{"dev" => true}}, &1))
            {worlds, instances} = Enum.split_with(servers, &is_nil(&1.instance_id))
            players = fn list -> Enum.sum(Enum.map(list, &(&1.current_players || 0))) end

            zones =
              case worlds do
                [] -> [%{name: "World server", online: false, players: 0}]
                _ -> Enum.map(worlds, &%{name: &1.name || &1.map_name || "World", online: true, players: &1.current_players || 0})
              end

            zones = if instances == [], do: zones, else: zones ++ [%{name: "Holo-sims (#{length(instances)})", online: true, players: players.(instances)}]
            %{online: worlds != [], zones: zones, current_players: players.(servers)}
        end
      end,
      %{online: false, zones: [], current_players: 0}
    )
  end

  defp total_players(game_slug) do
    safe(
      fn ->
        case Games.get_game_by_slug(game_slug) do
          nil -> 0
          game -> GamesRepo.one(from c in GameCharacter, where: c.game_id == ^game.id, select: count(c.user_id, :distinct)) || 0
        end
      end,
      0
    )
  end

  # A plugin's stats (or a database blip) must never take the front page down.
  defp safe(fun, fallback) do
    fun.()
  rescue
    e ->
      Logger.warning("GameStatus: #{Exception.message(e)}")
      fallback
  catch
    :exit, reason ->
      Logger.warning("GameStatus: #{inspect(reason)}")
      fallback
  end
end

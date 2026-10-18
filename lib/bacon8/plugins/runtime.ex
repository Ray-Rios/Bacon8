defmodule Bacon8.Plugins.Runtime do
  @moduledoc """
  Keeps this node in step with the active plugin set: loads it into the cache
  at boot, starts each active plugin's `children/0` under
  `Bacon8.PluginSupervisor`, and on `:plugins_changed` (broadcast by
  `Bacon8.Plugins.activate/2` / `deactivate/2` from any node) refreshes the
  cache and starts or stops processes to match.
  """
  use GenServer
  require Logger

  alias Bacon8.Plugins

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    if Keyword.get(Application.get_env(:bacon8, __MODULE__, []), :enabled, true) do
      Phoenix.PubSub.subscribe(Bacon8.PubSub, Plugins.topic())
      ensure_games()
      {:ok, reconcile(%{})}
    else
      :ignore
    end
  end

  @impl true
  def handle_info(:plugins_changed, running) do
    Plugins.refresh_cache()
    {:noreply, reconcile(running)}
  end

  def handle_info(_msg, running), do: {:noreply, running}

  # Plugins active by default have never been through activate/2, so their
  # game rows may not exist yet. A database that is down must not stop boot.
  defp ensure_games do
    for mod <- Plugins.active(), mod.game() != nil do
      case Plugins.ensure_game(mod.slug()) do
        {:ok, _} -> :ok
        error -> Logger.warning("Plugin #{mod.slug()}: could not register its game: #{inspect(error)}")
      end
    end
  rescue
    e -> Logger.warning("Plugins: could not register games at boot: #{Exception.message(e)}")
  end

  # running: %{slug => supervisor pid}
  defp reconcile(running) do
    wanted = Map.new(Plugins.active(), &{&1.slug(), &1})

    stopped =
      Enum.reduce(running, running, fn {slug, pid}, acc ->
        if Map.has_key?(wanted, slug) do
          acc
        else
          DynamicSupervisor.terminate_child(Bacon8.PluginSupervisor, pid)
          Logger.info("Plugin #{slug}: processes stopped")
          Map.delete(acc, slug)
        end
      end)

    Enum.reduce(wanted, stopped, fn {slug, mod}, acc ->
      if Map.has_key?(acc, slug), do: acc, else: start_plugin(acc, slug, mod)
    end)
  end

  defp start_plugin(acc, slug, mod) do
    case mod.children() do
      [] ->
        acc

      children ->
        spec = %{
          id: {:plugin, slug},
          start: {Supervisor, :start_link, [children, [strategy: :one_for_one]]},
          type: :supervisor
        }

        case DynamicSupervisor.start_child(Bacon8.PluginSupervisor, spec) do
          {:ok, pid} ->
            Logger.info("Plugin #{slug}: processes started")
            Map.put(acc, slug, pid)

          {:error, reason} ->
            # A broken plugin must not take the hub down; it stays inactive in
            # practice until fixed, and the error is in the log.
            Logger.error("Plugin #{slug}: could not start processes: #{inspect(reason)}")
            acc
        end
    end
  end
end

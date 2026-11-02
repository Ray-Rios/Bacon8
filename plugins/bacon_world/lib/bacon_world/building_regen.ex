defmodule BaconWorld.BuildingRegen do
  @moduledoc """
  Periodically ticks natural HP regeneration (10% per tick) on damaged placed objects across all zones.
  Runs at the world's natural regen interval (`Tuning.get("regen_interval_ms")`).
  """
  use GenServer

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent,
      shutdown: 500
    }
  end

  @impl true
  def init(_opts) do
    # this long-lived process owns the placement caches (Building.ensure_tables/0)
    BaconWorld.Building.ensure_tables()
    schedule_tick()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:tick, state) do
    BaconWorld.Building.tick_regen()
    schedule_tick()
    {:noreply, state}
  end

  defp schedule_tick do
    interval =
      try do
        max(1000, round(BaconWorld.Tuning.get("regen_interval_ms") || 5000))
      rescue
        _ -> 5000
      end

    Process.send_after(self(), :tick, interval)
  end
end

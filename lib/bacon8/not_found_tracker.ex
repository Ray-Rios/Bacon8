defmodule Bacon8.NotFoundTracker do
  @moduledoc """
  Tracks 404 (Not Found) errors for security monitoring.
  Uses ETS for fast in-memory storage with periodic cleanup.
  """
  
  use GenServer
  require Logger

  @table_name :not_found_tracker
  @cleanup_interval_ms 60 * 60 * 1000  # Cleanup every hour
  @max_age_seconds 24 * 60 * 60        # Keep entries for 24 hours
  @max_entries 10_000                   # Maximum entries to prevent memory issues

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Records a 404 error.
  """
  def record_404(path, ip_address, user_agent \\ nil) do
    GenServer.cast(__MODULE__, {:record, path, ip_address, user_agent})
  end

  @doc """
  Gets statistics about 404 errors.
  """
  def get_stats do
    GenServer.call(__MODULE__, :get_stats)
  end

  @doc """
  Gets top 404 paths.
  """
  def get_top_paths(limit \\ 10) do
    GenServer.call(__MODULE__, {:get_top_paths, limit})
  end

  @doc """
  Gets top offending IPs (most 404s).
  """
  def get_top_ips(limit \\ 10) do
    GenServer.call(__MODULE__, {:get_top_ips, limit})
  end

  @doc """
  Gets recent 404 entries.
  """
  def get_recent(limit \\ 50) do
    GenServer.call(__MODULE__, {:get_recent, limit})
  end

  @doc """
  Clears all 404 records.
  """
  def clear do
    GenServer.cast(__MODULE__, :clear)
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    # Create ETS table
    :ets.new(@table_name, [:ordered_set, :public, :named_table])
    
    # Schedule periodic cleanup
    Process.send_after(self(), :cleanup, @cleanup_interval_ms)
    
    {:ok, %{}}
  end

  @impl true
  def handle_cast({:record, path, ip_address, user_agent}, state) do
    now = System.system_time(:second)
    key = {now, :erlang.unique_integer([:monotonic])}
    
    # Check entry count before inserting
    count = :ets.info(@table_name, :size)
    if count >= @max_entries do
      # Remove oldest entries
      remove_oldest(100)
    end
    
    :ets.insert(@table_name, {key, path, ip_address, user_agent, now})
    
    {:noreply, state}
  end

  @impl true
  def handle_cast(:clear, state) do
    :ets.delete_all_objects(@table_name)
    {:noreply, state}
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    now = System.system_time(:second)
    one_hour_ago = now - 3600
    one_day_ago = now - 86400
    
    all_entries = :ets.tab2list(@table_name)
    
    stats = %{
      total_count: length(all_entries),
      last_hour: Enum.count(all_entries, fn {_key, _path, _ip, _ua, time} -> time > one_hour_ago end),
      last_day: Enum.count(all_entries, fn {_key, _path, _ip, _ua, time} -> time > one_day_ago end),
      unique_ips: all_entries |> Enum.map(fn {_key, _path, ip, _ua, _time} -> ip end) |> Enum.uniq() |> length(),
      unique_paths: all_entries |> Enum.map(fn {_key, path, _ip, _ua, _time} -> path end) |> Enum.uniq() |> length()
    }
    
    {:reply, stats, state}
  end

  @impl true
  def handle_call({:get_top_paths, limit}, _from, state) do
    top_paths = :ets.tab2list(@table_name)
    |> Enum.group_by(fn {_key, path, _ip, _ua, _time} -> path end)
    |> Enum.map(fn {path, entries} -> 
      %{path: path, count: length(entries), last_seen: entries |> Enum.map(fn {_key, _p, _ip, _ua, time} -> time end) |> Enum.max()}
    end)
    |> Enum.sort_by(fn %{count: count} -> count end, :desc)
    |> Enum.take(limit)
    
    {:reply, top_paths, state}
  end

  @impl true
  def handle_call({:get_top_ips, limit}, _from, state) do
    top_ips = :ets.tab2list(@table_name)
    |> Enum.group_by(fn {_key, _path, ip, _ua, _time} -> ip end)
    |> Enum.map(fn {ip, entries} -> 
      paths = entries |> Enum.map(fn {_key, path, _ip, _ua, _time} -> path end) |> Enum.uniq()
      %{ip: ip, count: length(entries), unique_paths: length(paths), last_seen: entries |> Enum.map(fn {_key, _p, _ip, _ua, time} -> time end) |> Enum.max()}
    end)
    |> Enum.sort_by(fn %{count: count} -> count end, :desc)
    |> Enum.take(limit)
    
    {:reply, top_ips, state}
  end

  @impl true
  def handle_call({:get_recent, limit}, _from, state) do
    recent = :ets.tab2list(@table_name)
    |> Enum.sort_by(fn {{time, _}, _path, _ip, _ua, _t} -> time end, :desc)
    |> Enum.take(limit)
    |> Enum.map(fn {_key, path, ip, user_agent, time} -> 
      %{path: path, ip: ip, user_agent: user_agent, timestamp: DateTime.from_unix!(time)}
    end)
    
    {:reply, recent, state}
  end

  @impl true
  def handle_info(:cleanup, state) do
    cleanup_old_entries()
    Process.send_after(self(), :cleanup, @cleanup_interval_ms)
    {:noreply, state}
  end

  # Private Functions

  defp cleanup_old_entries do
    cutoff = System.system_time(:second) - @max_age_seconds
    
    :ets.foldl(fn {{time, _} = key, _path, _ip, _ua, _t}, acc ->
      if time < cutoff do
        :ets.delete(@table_name, key)
      end
      acc
    end, nil, @table_name)
    
    Logger.debug("NotFoundTracker: Cleaned up old entries")
  end

  defp remove_oldest(count) do
    :ets.tab2list(@table_name)
    |> Enum.sort_by(fn {{time, _}, _path, _ip, _ua, _t} -> time end)
    |> Enum.take(count)
    |> Enum.each(fn {key, _path, _ip, _ua, _t} -> :ets.delete(@table_name, key) end)
  end
end

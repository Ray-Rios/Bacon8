defmodule Bacon8.LogBuffer do
  @moduledoc """
  An in-memory ring buffer for storing recent log entries.
  Allows viewing the last N log lines from the admin interface.
  """
  use GenServer

  @max_entries 500
  @table_name :log_buffer

  # Client API

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc """
  Add a log entry to the buffer.
  """
  def add_entry(level, message, metadata \\ %{}) do
    GenServer.cast(__MODULE__, {:add_entry, level, message, metadata})
  end

  @doc """
  Get the last N log entries.
  """
  def get_entries(count \\ 100) do
    GenServer.call(__MODULE__, {:get_entries, count})
  end

  @doc """
  Clear all log entries.
  """
  def clear do
    GenServer.call(__MODULE__, :clear)
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    # Create ETS table for fast access
    :ets.new(@table_name, [:named_table, :ordered_set, :public])
    {:ok, %{counter: 0}}
  end

  @impl true
  def handle_cast({:add_entry, level, message, metadata}, %{counter: counter} = state) do
    timestamp = DateTime.utc_now()
    entry = %{
      id: counter,
      timestamp: timestamp,
      level: level,
      message: message,
      metadata: metadata
    }
    
    :ets.insert(@table_name, {counter, entry})
    
    # Remove old entries if we exceed max
    if counter >= @max_entries do
      cleanup_old_entries(counter - @max_entries)
    end
    
    {:noreply, %{state | counter: counter + 1}}
  end

  @impl true
  def handle_call({:get_entries, count}, _from, state) do
    entries = 
      :ets.tab2list(@table_name)
      |> Enum.sort_by(fn {id, _} -> id end, :desc)
      |> Enum.take(count)
      |> Enum.map(fn {_, entry} -> entry end)
    
    {:reply, entries, state}
  end

  @impl true
  def handle_call(:clear, _from, _state) do
    :ets.delete_all_objects(@table_name)
    {:reply, :ok, %{counter: 0}}
  end

  defp cleanup_old_entries(threshold) do
    :ets.select_delete(@table_name, [{{:"$1", :_}, [{:<, :"$1", threshold}], [true]}])
  end
end

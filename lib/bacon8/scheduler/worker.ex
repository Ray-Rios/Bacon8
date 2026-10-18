defmodule Bacon8.Scheduler.Worker do
  @moduledoc """
  GenServer worker that polls for due scheduled events and executes them.
  
  This runs as a background process and checks every minute for events
  that are ready to execute based on their next_run_at timestamp.
  """
  use GenServer
  require Logger
  alias Bacon8.Scheduler

  @poll_interval :timer.seconds(60)  # Check every minute

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    Logger.info("Scheduler Worker started")
    # Schedule the first check
    schedule_check()
    {:ok, %{last_run: nil, runs_executed: 0}}
  end

  @impl true
  def handle_info(:check_events, state) do
    new_state = execute_due_events(state)
    schedule_check()
    {:noreply, new_state}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.warning("Scheduler Worker received unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  defp schedule_check do
    Process.send_after(self(), :check_events, @poll_interval)
  end

  defp execute_due_events(state) do
    now = DateTime.utc_now()
    events = Scheduler.list_events_due_for_execution()
    
    if length(events) > 0 do
      Logger.info("Scheduler Worker: Found #{length(events)} event(s) due for execution")
    end
    
    executed = Enum.reduce(events, 0, fn event, count ->
      case Scheduler.execute_scheduled_event(event) do
        {:ok, _result} ->
          Logger.info("Scheduler Worker: Successfully executed event '#{event.title}' (#{event.id})")
          count + 1
          
        {:error, reason} ->
          Logger.error("Scheduler Worker: Failed to execute event '#{event.title}' (#{event.id}): #{inspect(reason)}")
          count
      end
    end)
    
    %{state | 
      last_run: now, 
      runs_executed: state.runs_executed + executed
    }
  end

  # Manual trigger for testing
  def run_now do
    GenServer.cast(__MODULE__, :run_now)
  end

  @impl true
  def handle_cast(:run_now, state) do
    new_state = execute_due_events(state)
    {:noreply, new_state}
  end

  # Get worker status
  def status do
    GenServer.call(__MODULE__, :status)
  end

  @impl true
  def handle_call(:status, _from, state) do
    {:reply, state, state}
  end
end

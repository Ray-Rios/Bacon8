defmodule Bacon8.RateLimiter do
  @moduledoc """
  Progressive rate limiter for login attempts.
  Tracks failed attempts and enforces increasing delays.
  """
  use GenServer
  require Logger

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Check if an identifier (IP or device fingerprint) is allowed to attempt login.
  Returns {:ok, :allowed} or {:error, seconds_to_wait}
  """
  def check_attempt(identifier) do
    GenServer.call(__MODULE__, {:check_attempt, identifier})
  end

  @doc """
  Record a failed login attempt
  """
  def record_failure(identifier) do
    GenServer.cast(__MODULE__, {:record_failure, identifier})
  end

  @doc """
  Record a successful login (clears the failure count)
  """
  def record_success(identifier) do
    GenServer.cast(__MODULE__, {:record_success, identifier})
  end

  @doc """
  Manually block an identifier
  """
  def block(identifier, reason \\ "Manual block") do
    GenServer.cast(__MODULE__, {:block, identifier, reason})
  end

  @doc """
  Unblock an identifier
  """
  def unblock(identifier) do
    GenServer.cast(__MODULE__, {:unblock, identifier})
  end

  @doc """
  Get current stats for an identifier
  """
  def get_stats(identifier) do
    GenServer.call(__MODULE__, {:get_stats, identifier})
  end

  @doc """
  Get all blocked identifiers
  """
  def list_blocked do
    GenServer.call(__MODULE__, :list_blocked)
  end

  @doc "Check and increment a sliding-window counter stored in ETS for a given key. Returns :ok or {:error, :rate_limited, reset_time_ms}."
  def check_and_increment_rate(key, max_attempts, window_ms) do
    now = System.system_time(:millisecond)
    case :ets.lookup(:rate_limit_table, key) do
      [] ->
        :ets.insert(:rate_limit_table, {key, [now]})
        :ok
      [{^key, timestamps}] ->
        cutoff = now - window_ms
        recent = Enum.filter(timestamps, &(&1 > cutoff))

        if length(recent) >= max_attempts do
          oldest = Enum.min(recent)
          reset_time = oldest + window_ms
          {:error, :rate_limited, reset_time}
        else
          :ets.insert(:rate_limit_table, {key, [now | recent]})
          :ok
        end
    end
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    # State structure:
    # %{
    #   attempts: %{identifier => {count, last_attempt_time}},
    #   blocked: %{identifier => {reason, blocked_at}}
    # }
    schedule_cleanup()
    {:ok, %{attempts: %{}, blocked: %{}}}
  end

  @impl true
  def handle_call({:check_attempt, identifier}, _from, state) do
    cond do
      # Check if manually blocked
      Map.has_key?(state.blocked, identifier) ->
        {:reply, {:error, :blocked}, state}

      # Check rate limiting
      true ->
        case Map.get(state.attempts, identifier) do
          nil ->
            {:reply, {:ok, :allowed}, state}

          {count, last_attempt} ->
            wait_time = calculate_wait_time(count, last_attempt)

            if wait_time <= 0 do
              {:reply, {:ok, :allowed}, state}
            else
              {:reply, {:error, wait_time}, state}
            end
        end
    end
  end

  @impl true
  def handle_call({:get_stats, identifier}, _from, state) do
    stats = %{
      failed_attempts: get_attempt_count(state.attempts, identifier),
      last_attempt: get_last_attempt(state.attempts, identifier),
      blocked: Map.has_key?(state.blocked, identifier),
      block_reason: get_in(state.blocked, [identifier, :reason])
    }

    {:reply, stats, state}
  end

  @impl true
  def handle_call(:list_blocked, _from, state) do
    blocked_list =
      state.blocked
      |> Enum.map(fn {identifier, {reason, blocked_at}} ->
        %{
          identifier: identifier,
          reason: reason,
          blocked_at: blocked_at
        }
      end)

    {:reply, blocked_list, state}
  end

  @impl true
  def handle_cast({:record_failure, identifier}, state) do
    now = System.system_time(:second)
    {count, _} = Map.get(state.attempts, identifier, {0, now})

    new_attempts = Map.put(state.attempts, identifier, {count + 1, now})
    new_state = %{state | attempts: new_attempts}

    # Auto-block after 10 failed attempts
    new_state =
      if count + 1 >= 10 do
        Logger.warning("Auto-blocking #{identifier} after 10 failed attempts")
        block_identifier(new_state, identifier, "Too many failed attempts")
      else
        new_state
      end

    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:record_success, identifier}, state) do
    # Clear attempts on successful login
    new_attempts = Map.delete(state.attempts, identifier)
    {:noreply, %{state | attempts: new_attempts}}
  end

  @impl true
  def handle_cast({:block, identifier, reason}, state) do
    new_state = block_identifier(state, identifier, reason)
    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:unblock, identifier}, state) do
    new_blocked = Map.delete(state.blocked, identifier)
    new_attempts = Map.delete(state.attempts, identifier)
    {:noreply, %{state | blocked: new_blocked, attempts: new_attempts}}
  end

  @impl true
  def handle_info(:cleanup, state) do
    # Clean up old entries (older than 1 hour)
    now = System.system_time(:second)
    one_hour_ago = now - 3600

    new_attempts =
      state.attempts
      |> Enum.reject(fn {_id, {_count, last_attempt}} ->
        last_attempt < one_hour_ago
      end)
      |> Map.new()

    schedule_cleanup()
    {:noreply, %{state | attempts: new_attempts}}
  end

  # Private Functions

  defp calculate_wait_time(count, last_attempt) do
    now = System.system_time(:second)
    elapsed = now - last_attempt

    wait_duration =
      cond do
        count >= 7 -> 300 # 5 minutes after 7 attempts
        count >= 5 -> 30  # 30 seconds after 5 attempts
        count >= 3 -> 5   # 5 seconds after 3 attempts
        true -> 0
      end

    max(0, wait_duration - elapsed)
  end

  defp block_identifier(state, identifier, reason) do
    now = System.system_time(:second)
    new_blocked = Map.put(state.blocked, identifier, {reason, now})
    %{state | blocked: new_blocked}
  end

  defp get_attempt_count(attempts, identifier) do
    case Map.get(attempts, identifier) do
      nil -> 0
      {count, _} -> count
    end
  end

  defp get_last_attempt(attempts, identifier) do
    case Map.get(attempts, identifier) do
      nil -> nil
      {_, last_attempt} -> DateTime.from_unix!(last_attempt)
    end
  end

  defp schedule_cleanup do
    # Clean up every 10 minutes
    Process.send_after(self(), :cleanup, :timer.minutes(10))
  end
end

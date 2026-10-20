defmodule Bacon8Web.Plugs.RateLimitPlug do
  @moduledoc """
  Rate limiting plug using ETS for in-memory storage.
  Implements sliding window rate limiting with configurable limits per endpoint.
  """
  
  import Plug.Conn
  require Logger

  @default_limits %{
    # Authentication endpoints - strict limits
    "auth_login" => %{attempts: 5, window_ms: 300_000},      # 5 attempts per 5 minutes
    "auth_register" => %{attempts: 3, window_ms: 600_000},   # 3 attempts per 10 minutes
    "auth_verify" => %{attempts: 10, window_ms: 300_000},    # 10 verification attempts per 5 minutes
    
    # General API - lenient limits
    "api_general" => %{attempts: 200, window_ms: 60_000}     # 200 requests per minute
  }

  def init(opts) do
    endpoint = Keyword.get(opts, :endpoint, "api_general")
    custom_limits = Keyword.get(opts, :limits, %{})
    
    limits = Map.merge(@default_limits, custom_limits)
    
    %{
      endpoint: endpoint,
      limits: Map.get(limits, endpoint, @default_limits["api_general"])
    }
  end

  def call(conn, %{endpoint: endpoint, limits: %{attempts: max_attempts, window_ms: window_ms}}) do
    # ETS table created at application startup
    
    ip = get_client_ip(conn)
    key = "#{endpoint}:#{ip}"
    now = System.system_time(:millisecond)
    
    case check_rate_limit(key, max_attempts, window_ms, now) do
      :ok ->
        conn
      {:error, :rate_limited, reset_time} ->
        Logger.warning("Rate limit exceeded for #{endpoint} from IP: #{ip}")
        
        conn
        |> put_resp_header("x-ratelimit-limit", to_string(max_attempts))
        |> put_resp_header("x-ratelimit-remaining", "0")
        |> put_resp_header("x-ratelimit-reset", to_string(reset_time))
        |> send_resp(429, Jason.encode!(%{
          error: "Rate limit exceeded",
          message: "Too many requests. Please try again later.",
          retry_after: div(reset_time - now, 1000)
        }))
        |> halt()
    end
  end

  # Private functions

  defp get_client_ip(conn) do
    # Check for forwarded headers first (for load balancers/proxies)
    case get_req_header(conn, "x-forwarded-for") do
      [forwarded | _] -> 
        forwarded |> String.split(",") |> List.first() |> String.trim()
      [] ->
        case get_req_header(conn, "x-real-ip") do
          [real_ip | _] -> real_ip
          [] -> conn.remote_ip |> :inet.ntoa() |> to_string()
        end
    end
  end

  defp check_rate_limit(key, max_attempts, window_ms, now) do
    case :ets.lookup(:rate_limit_table, key) do
      [] ->
        # First request
        :ets.insert(:rate_limit_table, {key, [now]})
        :ok
      [{^key, timestamps}] ->
        # Filter out old timestamps outside the window
        cutoff = now - window_ms
        recent_timestamps = Enum.filter(timestamps, &(&1 > cutoff))
        
        if length(recent_timestamps) >= max_attempts do
          # Rate limited - calculate reset time
          oldest_in_window = Enum.min(recent_timestamps)
          reset_time = oldest_in_window + window_ms
          {:error, :rate_limited, reset_time}
        else
          # Within limits - add current timestamp
          new_timestamps = [now | recent_timestamps]
          :ets.insert(:rate_limit_table, {key, new_timestamps})
          :ok
        end
    end
  end

  @doc """
  Cleanup function to remove old entries from the rate limit table.
  Should be called periodically (e.g., via a GenServer or cron job).
  """
  def cleanup_old_entries do
    now = System.system_time(:millisecond)
    # Remove entries older than 1 hour
    cutoff = now - 3_600_000
    
    :ets.foldl(fn {key, timestamps}, acc ->
      recent_timestamps = Enum.filter(timestamps, &(&1 > cutoff))
      if Enum.empty?(recent_timestamps) do
        :ets.delete(:rate_limit_table, key)
      else
        :ets.insert(:rate_limit_table, {key, recent_timestamps})
      end
      acc
    end, [], :rate_limit_table)
  end
end
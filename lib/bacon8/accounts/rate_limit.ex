defmodule Bacon8.Accounts.RateLimit do
  @moduledoc """
  Rate limiting functionality for authentication actions to prevent abuse.
  
  Tracks and limits:
  - Registration attempts per IP
  - Login attempts per IP  
  - Password reset attempts per email
  """
  
  use GenServer
  require Logger

  # Rate limits (per hour)
  @max_registrations_per_ip 5
  @max_login_attempts_per_ip 20
  @max_password_resets_per_email 3
  
  # Cleanup interval (remove old entries every hour)
  @cleanup_interval_ms 60 * 60 * 1000

  # ETS table names
  @registration_table :rate_limit_registrations
  @login_table :rate_limit_logins  
  @password_reset_table :rate_limit_password_resets

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    # Create ETS tables for in-memory rate limiting
    :ets.new(@registration_table, [:set, :public, :named_table])
    :ets.new(@login_table, [:set, :public, :named_table])
    :ets.new(@password_reset_table, [:set, :public, :named_table])
    
    # Schedule periodic cleanup
    Process.send_after(self(), :cleanup, @cleanup_interval_ms)
    
    {:ok, %{}}
  end

  def handle_info(:cleanup, state) do
    cleanup_expired_entries()
    Process.send_after(self(), :cleanup, @cleanup_interval_ms)
    {:noreply, state}
  end

  # Public API

  def check_registration_limit(ip_address) do
    check_rate_limit(@registration_table, ip_address, @max_registrations_per_ip, "registration")
  end

  def record_registration_attempt(ip_address) do
    record_attempt(@registration_table, ip_address)
  end

  def check_login_limit(ip_address) do
    check_rate_limit(@login_table, ip_address, @max_login_attempts_per_ip, "login")
  end

  def record_login_attempt(ip_address) do
    record_attempt(@login_table, ip_address)
  end

  def check_password_reset_limit(email) do
    check_rate_limit(@password_reset_table, email, @max_password_resets_per_email, "password reset")
  end

  def record_password_reset_attempt(email) do
    record_attempt(@password_reset_table, email)
  end

  # Get current attempt counts (for admin monitoring)
  def get_attempt_counts(identifier) do
    tables = [@registration_table, @login_table, @password_reset_table]
    
    Enum.map(tables, fn table ->
      case :ets.lookup(table, identifier) do
        [{^identifier, attempts}] -> {table, length(attempts)}
        [] -> {table, 0}
      end
    end)
  end

  # Private functions

  defp check_rate_limit(table, identifier, max_attempts, action_type) do
    case :ets.lookup(table, identifier) do
      [{^identifier, attempts}] ->
        recent_attempts = filter_recent_attempts(attempts)
        
        if length(recent_attempts) >= max_attempts do
          Logger.warning("Rate limit exceeded for #{action_type}: #{identifier}")
          {:error, "Too many #{action_type} attempts. Please try again later."}
        else
          :ok
        end
      
      [] ->
        :ok
    end
  end

  defp record_attempt(table, identifier) do
    now = DateTime.utc_now()
    
    case :ets.lookup(table, identifier) do
      [{^identifier, attempts}] ->
        recent_attempts = filter_recent_attempts(attempts)
        updated_attempts = [now | recent_attempts]
        :ets.insert(table, {identifier, updated_attempts})
      
      [] ->
        :ets.insert(table, {identifier, [now]})
    end
    
    :ok
  end

  defp filter_recent_attempts(attempts) do
    one_hour_ago = DateTime.utc_now() |> DateTime.add(-1, :hour)
    Enum.filter(attempts, &DateTime.after?(&1, one_hour_ago))
  end

  defp cleanup_expired_entries do
    tables = [@registration_table, @login_table, @password_reset_table]
    
    Enum.each(tables, fn table ->
      :ets.foldl(fn {identifier, attempts}, acc ->
        recent_attempts = filter_recent_attempts(attempts)
        
        if length(recent_attempts) > 0 do
          :ets.insert(table, {identifier, recent_attempts})
        else
          :ets.delete(table, identifier)
        end
        
        acc
      end, [], table)
    end)
    
    Logger.debug("Rate limit cleanup completed")
  end

  # Utility function to get client IP from conn
  def get_client_ip(conn) do
    case Plug.Conn.get_req_header(conn, "x-forwarded-for") do
      [ip | _] -> ip |> String.split(",") |> List.first() |> String.trim()
      [] -> 
        case conn.remote_ip do
          {a, b, c, d} -> "#{a}.#{b}.#{c}.#{d}"
          ip when is_binary(ip) -> ip
          _ -> "unknown"
        end
    end
  end

  # For testing - reset all rate limits
  def reset_all_limits do
    :ets.delete_all_objects(@registration_table)
    :ets.delete_all_objects(@login_table)
    :ets.delete_all_objects(@password_reset_table)
    :ok
  end
end
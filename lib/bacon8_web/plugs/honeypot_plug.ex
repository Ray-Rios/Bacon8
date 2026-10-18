defmodule Bacon8Web.Plugs.HoneypotPlug do
  @moduledoc """
  Detects and blocks automated scanners and bots by tracking suspicious patterns:
  - Multiple 404s in short time
  - Requests to common attack vectors
  - Known malicious patterns
  """
  
  import Plug.Conn
  require Logger

  @honeypot_paths [
    "/wp-admin", "/wp-login.php", "/wp-content", "/wp-includes", "wp-config.php",
    "/admin.php", "/phpmyadmin", "/.env",
    "/config.php", 
    "/.git/config", "/composer.json",
    "/package.json", # Expose detection
    "wlwmanifest.xml", # Windows Live Writer manifest - classic scanner indicator
    "/xmlrpc.php" # WordPress XML-RPC - often exploited
  ]

  @suspicious_threshold 5  # 5 suspicious requests in window = block
  @window_ms 60_000        # 1 minute window

  def init(opts), do: opts

  def call(conn, _opts) do
    path = conn.request_path
    ip = get_client_ip(conn)

    if is_honeypot_path?(path) do
      record_suspicious_activity(ip, path)
      
      Logger.warning("🍯 Honeypot triggered: #{path} from #{ip}")
      
      # Return fake 200 to waste scanner's time
      conn
      |> send_resp(200, "OK")
      |> halt()
    else
      conn
    end
  end

  defp is_honeypot_path?(path) do
    # Check if path contains any honeypot patterns (not just starts with)
    Enum.any?(@honeypot_paths, fn pattern ->
      String.starts_with?(path, pattern) or String.contains?(path, pattern)
    end)
  end

  defp record_suspicious_activity(ip, path) do
    # ETS tables created at application startup
    now = System.system_time(:millisecond)
    key = "suspicious:#{ip}"

    case :ets.lookup(:honeypot_tracker, key) do
      [{^key, attempts}] ->
        recent = Enum.filter(attempts, fn {timestamp, _} -> 
          now - timestamp < @window_ms 
        end)
        
        updated = [{now, path} | recent]
        :ets.insert(:honeypot_tracker, {key, updated})

        if length(updated) >= @suspicious_threshold do
          block_ip(ip)
        end

      [] ->
        :ets.insert(:honeypot_tracker, {key, [{now, path}]})
    end
  end

  defp block_ip(ip) do
    Logger.error("🚫 Auto-blocking suspicious IP: #{ip}")
    # Add to blocked IPs table
    :ets.insert(:blocked_ips, {ip, System.system_time(:second)})
  end

  defp get_client_ip(conn) do
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
end

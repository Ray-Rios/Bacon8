defmodule Bacon8Web.Plugs.SuspiciousRequestPlug do
  @moduledoc """
  Detects and tracks suspicious requests like vulnerability scans,
  WordPress probes, PHP backdoor attempts, etc.
  
  Auto-blocks IPs that make too many suspicious requests.
  """

  require Logger

  @suspicious_patterns [
    # WordPress patterns
    {~r{^/wp-}, "wordpress_scan"},
    {~r{^/wordpress}, "wordpress_scan"},
    {~r{/wp-admin}, "wordpress_scan"},
    {~r{/wp-content}, "wordpress_scan"},
    {~r{/wp-includes}, "wordpress_scan"},
    {~r{/xmlrpc\.php}, "wordpress_scan"},
    
    # PHP backdoors/shells
    {~r{\.php$}, "php_probe"},
    {~r{/shell}, "shell_probe"},
    {~r{/backdoor}, "backdoor_probe"},
    {~r{/c99}, "shell_probe"},
    {~r{/r57}, "shell_probe"},
    
    # Config file probes
    {~r{/config\.php}, "config_probe"},
    {~r{/\.env}, "env_probe"},
    {~r{/\.git}, "git_probe"},
    {~r{/\.htaccess}, "htaccess_probe"},
    {~r{/web\.config}, "config_probe"},
    
    # Admin panels
    {~r{^/phpmyadmin}i, "phpmyadmin_probe"},
    {~r{^/pma}i, "phpmyadmin_probe"},
    {~r{^/mysql}i, "mysql_probe"},
    {~r{^/adminer}i, "adminer_probe"},
    
    # Common exploits
    {~r{/cgi-bin/}, "cgi_probe"},
    {~r{/\.well-known/security\.txt}, "security_txt"},  # Not really suspicious but tracked
    {~r{/api/v1.*\?.*=.*'}, "sql_injection"},
    {~r{<script}, "xss_attempt"},
    {~r{%3Cscript}i, "xss_attempt"},
    {~r{union.*select}i, "sql_injection"},
    {~r{etc/passwd}, "lfi_attempt"},
    {~r{\.\.\/}, "path_traversal"}
  ]

  # Number of suspicious requests before auto-blocking
  @block_threshold 10
  # Time window in seconds for counting requests
  @time_window 3600

  def init(opts), do: opts

  def call(conn, _opts) do
    path = conn.request_path
    
    case detect_suspicious(path) do
      nil ->
        conn
        
      request_type ->
        ip = get_client_ip(conn)
        user_agent = get_user_agent(conn)
        
        # Track the suspicious request asynchronously
        Task.start(fn ->
          track_suspicious_request(ip, path, conn.method, user_agent, request_type)
        end)
        
        # Check if should auto-block
        if should_auto_block?(ip) do
          auto_block_ip(ip)
          Logger.warning("🚫 Auto-blocked scanner IP: #{ip} for #{request_type}")
        end
        
        conn
    end
  end

  defp detect_suspicious(path) do
    Enum.find_value(@suspicious_patterns, fn {pattern, type} ->
      if Regex.match?(pattern, path), do: type
    end)
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

  defp get_user_agent(conn) do
    case Plug.Conn.get_req_header(conn, "user-agent") do
      [ua | _] -> ua
      [] -> "Unknown"
    end
  end

  defp track_suspicious_request(ip, path, method, user_agent, request_type) do
    alias Bacon8.Security

    Security.record_suspicious_request(%{
      ip_address: ip,
      path: String.slice(path, 0, 500),  # Truncate long paths
      method: method,
      user_agent: String.slice(user_agent || "Unknown", 0, 500),
      request_type: request_type,
      status_code: nil,  # Will be filled in later if needed
      blocked: false
    })

    Logger.info("🔍 Suspicious request: #{request_type} from #{ip} -> #{path}")
  end

  defp should_auto_block?(ip) do
    # Don't auto-block if on allowlist
    if Bacon8.Security.allowed?(ip, "ip") do
      false
    else
      count = get_recent_suspicious_count(ip)
      count >= @block_threshold
    end
  end

  defp get_recent_suspicious_count(ip) do
    alias Bacon8.Security
    Security.count_suspicious_requests(ip, @time_window)
  end

  defp auto_block_ip(ip) do
    # Add to ETS for immediate blocking
    ensure_ets_table()
    :ets.insert(:blocked_ips, {ip, System.system_time(:second)})
    
    # Also persist to database
    Task.start(fn ->
      Bacon8.Security.block_identifier(%{
        identifier: ip,
        identifier_type: "ip",
        reason: "Auto-blocked: Excessive vulnerability scanning",
        expires_at: DateTime.add(DateTime.utc_now(), 24 * 3600, :second)  # 24 hour block
      })
    end)
  end

  defp ensure_ets_table do
    case :ets.whereis(:blocked_ips) do
      :undefined ->
        :ets.new(:blocked_ips, [:set, :public, :named_table])
      _ ->
        :ok
    end
  end
end

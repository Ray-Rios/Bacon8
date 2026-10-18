defmodule Bacon8Web.Plugs.IpBlockerPlug do
  @moduledoc """
  Blocks requests from known malicious IPs.
  Checks against both manual blocks and auto-detected scanner IPs.
  """
  
  import Plug.Conn
  require Logger

  def init(opts), do: opts

  def call(conn, _opts) do
    ip = get_client_ip(conn)

    if is_blocked?(ip) do
      Logger.warning("🚫 Blocked request from: #{ip}")
      
      conn
      |> send_resp(403, "Forbidden")
      |> halt()
    else
      conn
    end
  end

  defp is_blocked?(ip) do
    case :ets.whereis(:blocked_ips) do
      :undefined -> false
      _ ->
        case :ets.lookup(:blocked_ips, ip) do
          [{^ip, blocked_at}] ->
            # Keep blocks for 24 hours
            now = System.system_time(:second)
            age = now - blocked_at
            
            if age < 86_400 do
              true
            else
              # Remove expired block
              :ets.delete(:blocked_ips, ip)
              false
            end
          
          [] -> false
        end
    end
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

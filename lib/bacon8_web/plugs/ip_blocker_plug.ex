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
    # (an address that isn't one visitor's is never blocked, whatever an old entry says)
    case Bacon8.Security.blockable_ip?(ip) && :ets.whereis(:blocked_ips) do
      false -> false
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

  # the visitor's address, already worked out by Bacon8Web.ClientIP in the endpoint
  defp get_client_ip(conn), do: Bacon8Web.ClientIP.format(conn.remote_ip)
end

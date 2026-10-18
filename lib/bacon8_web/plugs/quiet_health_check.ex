defmodule Bacon8Web.Plugs.QuietHealthCheck do
  @moduledoc """
  Disables request logging for health check endpoints to prevent log spam.
  Logs only the first successful health check after app startup.
  """
  require Logger

  @behaviour Plug

  def init(opts), do: opts

  def call(%{path_info: ["health"]} = conn, _opts) do
    # Disable Phoenix logger for this request
    Logger.metadata(plug_skip_log: true)
    Plug.Conn.put_private(conn, :phoenix_endpoint, false)
    
    # Log first successful health check after startup (stored in persistent term)
    unless :persistent_term.get(:health_check_logged, false) do
      Logger.info("✅ Initial health check passed - future health checks will not be logged")
      :persistent_term.put(:health_check_logged, true)
    end
    
    conn
  end

  def call(conn, _opts), do: conn
end

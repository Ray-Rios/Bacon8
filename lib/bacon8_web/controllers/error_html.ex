defmodule Bacon8Web.ErrorHTML do
  use Bacon8Web, :html

  # Track 404 errors for security monitoring
  def render("404.html", assigns) do
    # Record the 404 error
    try do
      conn = assigns[:conn]
      if conn do
        ip = get_client_ip(conn)
        path = conn.request_path
        user_agent = Plug.Conn.get_req_header(conn, "user-agent") |> List.first()
        Bacon8.NotFoundTracker.record_404(path, ip, user_agent)
      end
    rescue
      _ -> :ok
    end
    
    ~H"""
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <title>404 - Not Found</title>
      <style>
        body {
          font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
          background: linear-gradient(135deg, #1a1a2e 0%, #16213e 50%, #0f3460 100%);
          min-height: 100vh;
          display: flex;
          align-items: center;
          justify-content: center;
          margin: 0;
          color: white;
        }
        .container {
          text-align: center;
          padding: 2rem;
        }
        h1 {
          font-size: 8rem;
          margin: 0;
          background: linear-gradient(to right, #e94560, #0f3460);
          -webkit-background-clip: text;
          -webkit-text-fill-color: transparent;
        }
        p {
          font-size: 1.5rem;
          color: #94a3b8;
          margin: 1rem 0;
        }
        a {
          display: inline-block;
          margin-top: 2rem;
          padding: 0.75rem 2rem;
          background: #3b82f6;
          color: white;
          text-decoration: none;
          border-radius: 0.5rem;
          transition: background 0.2s;
        }
        a:hover {
          background: #2563eb;
        }
      </style>
    </head>
    <body>
      <div class="container">
        <h1>404</h1>
        <p>Oops! The page you're looking for doesn't exist.</p>
        <a href="/">← Back to Home</a>
      </div>
    </body>
    </html>
    """
  end

  # By default, Phoenix returns the status message from
  # the template name. For example, "500.html" becomes
  # "Internal Server Error".
  def render(template, _assigns) do
    Phoenix.Controller.status_message_from_template(template)
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
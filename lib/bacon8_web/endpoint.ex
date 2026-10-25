defmodule Bacon8Web.Endpoint do
  use Phoenix.Endpoint, otp_app: :bacon8

  @session_options [
    store: :cookie,
    key: "_bacon8_key",
    signing_salt: "bacon8_session",
    same_site: "Lax"
  ]

  socket "/live", Phoenix.LiveView.Socket, 
    websocket: [
      connect_info: [:x_headers, :peer_data, :user_agent, session: @session_options],
      timeout: 45_000,  # 45 second timeout (default is 60s)
      compress: true    # Enable compression for faster data transfer
    ],
    longpoll: [
      connect_info: [:x_headers, :peer_data, :user_agent, session: @session_options],
      timeout: 45_000
    ]
  socket "/socket", Bacon8Web.UserSocket,
    websocket: [
      timeout: 45_000,
      compress: true
    ],
    longpoll: false

  # Serve user uploads from mounted PVC (/app/uploads) or local uploads folder
  @uploads_root if(File.exists?("/app/uploads"), do: "/app/uploads", else: "uploads")

  # Must stay directly before the /uploads Plug.Static: adds nosniff/sandbox headers
  # to every upload and authorises private trees (users/<id>/, <id>/files/) itself
  # so Plug.Static never serves them publicly.
  plug Bacon8Web.Plugs.UploadsGuard, root: @uploads_root, session: @session_options

  plug Plug.Static,
    at: "/uploads",
    from: @uploads_root,
    gzip: false,
    cache_control_for_etags: "public, max-age=31536000"

  # Serve 3D models from PVC mount (populated by sync-models-to-k8s.sh).
  # The release priv/static does not embed models; they live on the PVC at /app/priv/static/models.
  # ModelsGuard keeps the source files on that volume (.blend, .zip, ...) private.
  plug Bacon8Web.Plugs.ModelsGuard, root: "/app/priv/static/models"

  # gzip: a `.glb.gz` beside a `.glb` is sent instead when the browser accepts gzip
  # (meshopt-compressed GLBs shrink about 8x more). ModelsGuard checks the requested
  # name (`.glb`), so a direct request for the `.gz` stays 404. Clients version model
  # URLs (`?vsn=`), which Plug.Static caches as immutable for a year.
  plug Plug.Static,
    at: "/models",
    from: "/app/priv/static/models",
    gzip: true,
    cache_control_for_etags: "public, max-age=86400"

  # Installed plugins' own files: /plugins/<slug>/... from plugins/<slug>/priv/static/
  # (pictures and the like only; game cards' pictures live there). BACON8.md §9.
  plug Bacon8Web.Plugs.PluginStatic

  # Serve additional static asset folders for 3D world (terrain heightmaps, etc.)
  plug Plug.Static,
    at: "/",
    from: :bacon8,
    gzip: true,
    brotli: true,
    cache_control_for_etags: "public, max-age=31536000",
    only: ~w(assets audio css js fonts images favicon.ico robots.txt sitemap.xml site.webmanifest .well-known terrain heightmaps)

  if code_reloading? do
    socket "/phoenix/live_reload/socket", Phoenix.LiveReloader.Socket
    plug Phoenix.LiveReloader
    plug Phoenix.CodeReloader
    plug Phoenix.Ecto.CheckRepoStatus, otp_app: :bacon8
  end

  plug Phoenix.LiveDashboard.RequestLogger,
    param_key: "request_logger",
    cookie_key: "request_logger"

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library(),
    # Keeps the raw body of payment webhooks for signature checks.
    body_reader: {Bacon8Web.RawBodyReader, :read_body, []}

  plug Plug.MethodOverride
  plug Plug.Head
  plug Plug.Session, @session_options
  plug Bacon8Web.Router
end

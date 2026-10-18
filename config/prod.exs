import Config

# ----------------------------
# Endpoint
# ----------------------------
config :bacon8, Bacon8Web.Endpoint,
  http: [ip: {0, 0, 0, 0}, port: String.to_integer(System.get_env("PORT") || "4000")],
  url: [host: System.get_env("BACON8_HOST") || "bacon8.net", port: 443, scheme: "https"],
  # Allow all origins to support local network access (e.g. 192.168.x.x)
  check_origin: false,
  # check_origin: [
  #   "https://bacon8.net",
  #   "https://www.bacon8.net",
  #   "//localhost",
  #   "//127.0.0.1"
  # ],
  # THIS IS THE ONLY force_ssl THAT DOES ANYTHING. IT MUST LIVE HERE.
  #
  # `:force_ssl` is a COMPILE-TIME endpoint option: Phoenix injects `plug
  # Plug.SSL, <these opts>` into the endpoint's pipeline in __before_compile__,
  # so the options are frozen into the compiled module. Setting `force_ssl` in
  # runtime.exs looks reasonable, is accepted without complaint, and is inert -
  # see the note left at that spot. Changing it here requires a rebuild, not
  # just a restart.
  #
  # WHY THE EXCLUDE LIST. Public traffic arrives through the nginx ingress,
  # which terminates TLS and sets X-Forwarded-Proto: https, so `rewrite_on` lets
  # it through. A pod calling the Service directly sets no such header, so
  # Plug.SSL answers 301 to https://bacon8.net (the redirect target is the
  # endpoint's :url host, which is why it is not the request host).
  #
  # For a browser that is invisible. For the game server's heartbeat POST it is
  # fatal, and the failure names neither TLS nor a redirect:
  #
  #   Connected to bacon8-web.bacon8.svc.cluster.local (10.96.162.255) port 80
  #   upload completely sent off: 194 bytes
  #   Clear auth, redirects to port from 80 to 443
  #   necessary data rewind was not possible
  #   libcurl error: 65 (Send failed since rewinding of the data stream failed)
  #
  # libcurl has already streamed the body and cannot rewind it to replay at the
  # new URL. Note "Clear auth" too: a cross-host redirect STRIPS the
  # Authorization header, so even a request that survived the rewind would
  # arrive with no server API key and be refused. Two failures, one redirect.
  #
  # Excluding these names is not a hole. The redirect protects a client that
  # would otherwise send credentials in plaintext across the internet; these
  # names resolve only inside the cluster, where the traffic never leaves the
  # node. "health" is pre-existing and inert (Plug.SSL matches on HOST, and no
  # request arrives with a Host of "health") - kept only so removing it is a
  # separate, deliberate decision.
  force_ssl: [
    rewrite_on: [:x_forwarded_proto],
    log: false,
    exclude: [
      "localhost",
      "health",
      "bacon8-web",
      "bacon8-web.bacon8",
      "bacon8-web.bacon8.svc",
      "bacon8-web.bacon8.svc.cluster.local",
      "bacon8-web.bacon8-dev",
      "bacon8-web.bacon8-dev.svc",
      "bacon8-web.bacon8-dev.svc.cluster.local"
    ]
  ],
  server: true,
  secret_key_base: (System.get_env("SECRET_KEY_BASE") ||
    raise("SECRET_KEY_BASE is missing. Generate with `mix phx.gen.secret`")),
  live_view: [signing_salt: (System.get_env("LIVE_VIEW_SIGNING_SALT") ||
    raise("LIVE_VIEW_SIGNING_SALT is missing"))],
  cache_static_manifest: "priv/static/cache_manifest.json"

# ----------------------------
# Arc (file storage) - local storage for production
# Files will be stored in the local filesystem under priv/static/uploads
# Arc will write to priv/static/{storage_dir} and generate URLs as /{storage_dir}
# Make sure your k8s deployment has a PVC or hostPath for /app/priv/static/uploads
config :arc,
  storage: Arc.Storage.Local,
  storage_dir: "priv/static"

# CORS origins for production
config :cors_plug,
  origin: [
    "https://bacon8.net",
    "https://www.bacon8.net"
  ],
  max_age: 86400,
  methods: ["GET", "POST", "PUT", "DELETE", "OPTIONS"],
  headers: ["Authorization", "Content-Type", "Accept", "Origin", "User-Agent", "DNT", "Cache-Control", "X-Mx-ReqToken", "Keep-Alive", "X-Requested-With", "If-Modified-Since"]
# ----------------------------
# Guardian (prod)
# ----------------------------
config :bacon8, Bacon8.Auth.Guardian,
  secret_key: (System.get_env("GUARDIAN_SECRET_KEY") ||
    raise("GUARDIAN_SECRET_KEY is missing. Generate with `mix guardian.gen.secret`"))

# ----------------------------
# Redis & Mail
# ----------------------------
config :bacon8, :redis_url,
  System.get_env("REDIS_URL") || "redis://redis:6379/0"

config :bacon8, :enable_redis, 
  System.get_env("ENABLE_REDIS", "true") == "true"

# For now, use Logger adapter to log emails (until SMTP is configured via env vars)
# Note: Swoosh.Adapters.Local causes global process conflicts in clustered deployments
# The actual adapter is configured in runtime.exs based on SMTP_HOST env var
# config :bacon8, Bacon8.Mailer,
#   adapter: Swoosh.Adapters.Logger

# SMTP alternative (uncomment and configure if you prefer SMTP over SendGrid):
# config :bacon8, Bacon8.Mailer,
#   adapter: Swoosh.Adapters.SMTP,
#   relay: System.get_env("SMTP_HOST") || "smtp.yourprovider.com",
#   port: String.to_integer(System.get_env("SMTP_PORT") || "587"),
#   username: System.get_env("SMTP_USER"),
#   password: System.get_env("SMTP_PASS"),
#   tls: :if_available,
#   retries: 3

# ----------------------------
# Logger - ensure we see errors in production
# ----------------------------
config :logger, level: :info
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id, :user_id]

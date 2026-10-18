import Config

# -------------------------------------------------
# Swoosh API Client - MUST be disabled in production to prevent
# global process conflicts in clustered/multi-pod deployments
# -------------------------------------------------
config :swoosh, :api_client, false

# Optional Projects API key used by Taskbar calendar to fetch project items
config :bacon8, projects_api_key: System.get_env("PROJECTS_API_KEY") || ""

# API key used by trusted dedicated game servers to act on behalf of players
# Drive storage (BACON8.md §7). Defaults to <uploads volume>/_drive, which
# UploadsGuard keeps from ever being served by /uploads.
if drive_root = System.get_env("DRIVE_STORAGE_ROOT") do
  config :bacon8, Bacon8.Storage, root: drive_root
end

config :bacon8, games_server_api_key: System.get_env("GAMES_SERVER_API_KEY") || ""

# Stripe (BACON8.md §8). Test keys (sk_test_..., whsec_...) in development,
# live keys in production, always from the environment / k8s secret, never
# from a file in the repo. With a key set, Stripe is the default provider;
# PAYMENTS_PROVIDER=fake switches back to the pretend one in development.
# Ignored in tests, which set their own (a key in your shell mustn't change them).
case config_env() != :test && System.get_env("STRIPE_SECRET_KEY") do
  key when is_binary(key) and key != "" ->
    config :bacon8, Bacon8.Payments.Stripe,
      secret_key: key,
      webhook_secret: System.get_env("STRIPE_WEBHOOK_SECRET")

    config :bacon8, Bacon8.Payments, default_provider: System.get_env("PAYMENTS_PROVIDER") || "stripe"

  _ ->
    :ok
end

# -------------------------------------------------
# SECRET_KEY_BASE
# -------------------------------------------------
secret_key_base =
  System.get_env("SECRET_KEY_BASE") ||
    if config_env() in [:dev, :test] do
      # Dev default - fixed key for development
      "sX9/Rn5BIxDT+OD20jOYEYImGrN9SR7F9NLC1av9z+aip2mySJdALjSICoNOX5Hc"
    else
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by running `mix phx.gen.secret`
      """
    end

# -------------------------------------------------
# LIVE_VIEW_SIGNING_SALT
# -------------------------------------------------
live_view_salt =
  System.get_env("LIVE_VIEW_SIGNING_SALT") ||
    if config_env() in [:dev, :test] do
      "dev_live_view_salt_#{:crypto.strong_rand_bytes(8) |> Base.encode64()}"
    else
      raise """
      environment variable LIVE_VIEW_SIGNING_SALT is missing.
      You can generate one by running `mix phx.gen.secret`
      """
    end

# -------------------------------------------------
# GUARDIAN SECRET KEY
# -------------------------------------------------
guardian_secret =
  System.get_env("GUARDIAN_SECRET_KEY") ||
    if config_env() in [:dev, :test] do
      "dev_guardian_secret_#{:crypto.strong_rand_bytes(16) |> Base.encode64()}"
    else
      raise """
      environment variable GUARDIAN_SECRET_KEY is missing.
      You can generate one by running `mix guardian.gen.secret`
      """
    end

# -------------------------------------------------
# PostgreSQL Database URL
# -------------------------------------------------
db_username = System.get_env("DB_USERNAME") || "postgres"
db_password = System.get_env("DB_PASSWORD") || "postgres"
db_host = System.get_env("DB_HOST") || if(config_env() in [:dev, :test], do: "localhost", else: "db")
db_port = String.to_integer(System.get_env("DB_PORT") || if(config_env() == :dev, do: "5432", else: "5432"))
# test.exs names the test databases; this URL would otherwise point tests at dev.
db_name = System.get_env("DB_NAME") || if(config_env() == :test, do: "bacon8_test", else: "bacon8_dev")
db_pool = String.to_integer(System.get_env("POOL_SIZE") || "10")

database_url = 
  System.get_env("DATABASE_URL") || 
  "postgresql://#{db_username}:#{db_password}@#{db_host}:#{db_port}/#{db_name}"

config :bacon8, Bacon8.Repo,
  adapter: Ecto.Adapters.Postgres,
  url: database_url,
  pool_size: db_pool,
  timeout: 60_000,
  ownership_timeout: 60_000,
  queue_target: 5000,
  queue_interval: 1000,
  migration_primary_key: [type: :bigserial],
  migration_lock: nil,
  parameters: [
    application_name: "bacon8"
  ]

# -------------------------------------------------
# Games Repo Database URL (isolated multiplayer game data)
# -------------------------------------------------
games_db_name = System.get_env("GAMES_DB_NAME") || if(config_env() == :test, do: "bacon8_games_test", else: "bacon8_games_dev")

games_database_url =
  System.get_env("GAMES_DATABASE_URL") ||
    "postgresql://#{db_username}:#{db_password}@#{db_host}:#{db_port}/#{games_db_name}"

# -------------------------------------------------
# Plugins (BACON8.md §9)
#
# BACON8_ACTIVE_PLUGINS (comma-separated slugs) replaces
# :default_active_plugins: which plugins are active until an admin toggles
# them on /admin/plugins. Lets a deploy switch on a private plugin from its
# first boot without the hub's config naming it. A plugin's own settings are
# read by the plugin.
# -------------------------------------------------
case System.get_env("BACON8_ACTIVE_PLUGINS") do
  nil ->
    :ok

  csv ->
    config :bacon8, :default_active_plugins,
      csv |> String.split(",", trim: true) |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))
end

config :bacon8, Bacon8.GamesRepo,
  adapter: Ecto.Adapters.Postgres,
  url: games_database_url,
  pool_size: db_pool,
  timeout: 60_000,
  ownership_timeout: 60_000,
  queue_target: 5000,
  queue_interval: 1000,
  priv: "priv/games_repo",
  migration_primary_key: [type: :binary_id],
  migration_lock: nil,
  parameters: [
    application_name: "bacon8_games"
  ]

# -------------------------------------------------
# Endpoint config
# -------------------------------------------------
http_port = String.to_integer(System.get_env("PORT") || "4000")


config :bacon8, Bacon8Web.Endpoint,
  http: [ip: {0, 0, 0, 0}, port: http_port],
  secret_key_base: secret_key_base,
  live_view: [signing_salt: live_view_salt],
  url: [
    host: System.get_env("BACON8_HOST") || "localhost", 
    port: if(config_env() == :prod, do: 443, else: http_port),
    scheme: if(config_env() == :prod, do: "https", else: "http")
  ]

  # NO force_ssl HERE. IT WOULD BE SILENTLY IGNORED.
  #
  # `:force_ssl` is a COMPILE-TIME endpoint option - Phoenix injects
  # `plug Plug.SSL, <opts>` in __before_compile__, so the options are baked into
  # the compiled endpoint and runtime.exs is far too late to change them. This
  # block used to carry a force_ssl line; it did nothing, and looked like it did
  # something, which is worse than not being here at all.
  #
  # The real one is in config/prod.exs. Changing it needs a REBUILD, not just a
  # restart.

# -------------------------------------------------
# Guardian runtime config
# -------------------------------------------------
config :bacon8, Bacon8.Auth.Guardian,
  secret_key: guardian_secret

# -------------------------------------------------
# Redis
# -------------------------------------------------
config :bacon8, :redis_url,
  System.get_env("REDIS_URL") || if(config_env() == :dev, do: "redis://localhost:6379/0", else: "redis://redis:6379/0")

config :bacon8, :enable_redis,
  System.get_env("ENABLE_REDIS", "false") == "true"

# -------------------------------------------------
# Swoosh / Mailer (dynamic runtime config)
# If SMTP_HOST is provided, use authenticated SMTP (recommended for prod).
# Otherwise, fall back to Local adapter (preview emails without sending).
#
# For Namecheap Private Email, use these settings:
#   SMTP_HOST=mail.privateemail.com
#   SMTP_PORT=587 (for STARTTLS) or 465 (for SSL/TLS)
#   SMTP_USER=your-email@yourdomain.com (full email address)
#   SMTP_PASS=your-password
#   FROM_EMAIL=your-email@yourdomain.com (same as SMTP_USER)
#   FROM_NAME=Bacon8 (or your preferred sender name)
#
# Note: Namecheap requires authentication and the FROM_EMAIL must match
# an email address configured in your Namecheap Private Email account.
# -------------------------------------------------
smtp_host = System.get_env("SMTP_HOST") || ""
smtp_port = System.get_env("SMTP_PORT")
smtp_user = System.get_env("SMTP_USER")
smtp_pass = System.get_env("SMTP_PASS")
smtp_verify = System.get_env("SMTP_VERIFY", "true") == "true"

if smtp_host != "" do
  # Use SMTP relay; defaults target STARTTLS on 587. Set SMTP_PORT if different.
  parsed_port = (smtp_port && String.to_integer(smtp_port)) || 587
  {ssl?, tls_mode} =
    case parsed_port do
      465 -> {true, :never}   # Implicit SSL
      _ -> {false, :always}   # Require STARTTLS on submission port
    end

  tls_options_base =
    if smtp_verify do
      [
        verify: :verify_peer,
        cacertfile: "/etc/ssl/certs/ca-certificates.crt",
        server_name_indication: to_charlist(smtp_host),
        depth: 10
      ]
    else
      [verify: :verify_none]
    end

  config :bacon8, Bacon8.Mailer,
    adapter: Swoosh.Adapters.SMTP,
    relay: smtp_host,
    port: parsed_port,
    username: smtp_user,
    password: smtp_pass,
    auth: :always,
    tls: tls_mode,
    ssl: ssl?,
  retries: 2,
  no_mx_lookups: false,
  tls_options: tls_options_base
else
  # No SMTP configured: use Logger adapter (cluster-safe, just logs emails)
  # Note: Swoosh.Adapters.Local uses global processes which cause conflicts in clustered deployments
  config :bacon8, Bacon8.Mailer,
    adapter: Swoosh.Adapters.Logger,
    level: :info
end

# -------------------------------------------------
# CORS
# -------------------------------------------------
config :cors_plug,
  origin:
    String.split(
      System.get_env("CORS_ALLOWED_ORIGINS") || "http://localhost:3000,http://localhost:4000",
      ","
    ),
  max_age: 86400,
  methods: ["GET", "POST", "PUT", "DELETE", "OPTIONS"]

# -------------------------------------------------
# Clustering (libcluster)
# -------------------------------------------------
if System.get_env("KUBERNETES_SERVICE_HOST") do
  config :libcluster,
    topologies: [
      k8s: [
        strategy: Cluster.Strategy.Kubernetes,
        config: [
          mode: :ip,
          kubernetes_node_basename: "bacon8",
          kubernetes_selector: "app=bacon8-web",
          kubernetes_namespace: System.get_env("POD_NAMESPACE") || "default",
          polling_interval: 3_000
        ]
      ]
    ]
end

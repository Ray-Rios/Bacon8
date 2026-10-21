import Config

# ----------------------------
# MIME Types
# ----------------------------
# Add custom MIME types for file uploads
config :mime, :types, %{
  "audio/mpeg" => ["mp3"],
  "audio/wav" => ["wav"],
  "audio/ogg" => ["ogg"],
  "video/ogg" => ["ogv"],
  "audio/flac" => ["flac"],
  "audio/x-m4a" => ["m4a"],
  "video/webm" => ["webm"],
  "video/quicktime" => ["mov"],
  "video/x-msvideo" => ["avi"]
}

# ----------------------------
# Global Bacon8 app Config
# ----------------------------
config :elixir, :time_zone_database, Tz.TimeZoneDatabase

# ----------------------------
# Ecto Repos
# ----------------------------
config :bacon8,
  ecto_repos: [Bacon8.Repo, Bacon8.GamesRepo], # Bacon8.Repo = main app, GamesRepo = isolated multiplayer game data
  generators: [timestamp_type: :utc_datetime]

# ----------------------------
# Phoenix Endpoint
# ----------------------------
config :bacon8, Bacon8Web.Endpoint,
  url: [host: "localhost"],
  adapter: Phoenix.Endpoint.Cowboy2Adapter,
  render_errors: [
    formats: [html: Bacon8Web.ErrorHTML, json: Bacon8Web.ErrorJSON],
    layout: false
  ],
  pubsub_server: Bacon8.PubSub

# ----------------------------
# Mailer (default - overridden by runtime.exs in prod)
# Using Logger adapter as default since Local adapter causes global process conflicts in clusters
# ----------------------------
config :bacon8, Bacon8.Mailer,
  adapter: Swoosh.Adapters.Logger,
  level: :info

# ----------------------------
# Esbuild (JS bundler)
# ----------------------------
config :esbuild,
  version: "0.17.11",
  default: [
    args:
      ~w(js/app.js --bundle --target=es2020 --outdir=../priv/static/assets --external:/fonts/* --external:/images/* --format=iife --minify --tree-shaking=true),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__), "NODE_ENV" => "production"}
  ]

# ----------------------------
# Logger
# ----------------------------
config :logger,
  backends: [:console, Bacon8.LogBufferBackend]

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

config :logger, Bacon8.LogBufferBackend,
  level: :info

# ----------------------------
# JSON library
# ----------------------------
config :phoenix, :json_library, Jason

# Request logs show "[FILTERED]" for any parameter whose name contains one of
# these (verification codes, reset tokens, webhook secrets in the path).
config :phoenix, :filter_parameters, ["password", "secret", "token", "code"]

# ----------------------------
# CORS defaults (can override per environment)
# ----------------------------
config :cors_plug,
  origin: ["http://localhost:3000", "http://localhost:4000"],
  max_age: 86400,
  methods: ["GET", "POST", "PUT", "DELETE", "OPTIONS"]

# ----------------------------
# Ecto Repo defaults
# ----------------------------
# Plugins active until an admin saves a choice on /admin/plugins (BACON8.md §9).
config :bacon8, :default_active_plugins, ["bacon_world"]

# Payments (BACON8.md §8). "fake" is a pretend provider for development and
# tests; it refuses to work unless fake_enabled is true (dev.exs, test.exs).
# "stripe" works once STRIPE_SECRET_KEY is set (runtime.exs), which also makes
# it the default.
config :bacon8, Bacon8.Payments,
  default_provider: "fake",
  providers: %{"fake" => Bacon8.Payments.Fake, "stripe" => Bacon8.Payments.Stripe},
  fake_enabled: false

config :bacon8, Bacon8.Repo,
  username: System.get_env("DB_USERNAME") || "root",
  password: System.get_env("DB_PASSWORD") || "postgres",
  database: System.get_env("DB_NAME") || "bacon8_dev",
  hostname: System.get_env("DB_HOST") || "db",
  port: String.to_integer(System.get_env("DB_PORT") || "26257"),
  show_sensitive_data_on_connection_error: true,
  pool_size: 10,
  migration_primary_key: [type: :bigserial],
  migration_lock: false

# ----------------------------
# Games Repo defaults (isolated database for multiplayer game data)
# ----------------------------
config :bacon8, Bacon8.GamesRepo,
  username: System.get_env("DB_USERNAME") || "root",
  password: System.get_env("DB_PASSWORD") || "postgres",
  database: System.get_env("GAMES_DB_NAME") || "bacon8_games_dev",
  hostname: System.get_env("DB_HOST") || "db",
  port: String.to_integer(System.get_env("DB_PORT") || "26257"),
  show_sensitive_data_on_connection_error: true,
  pool_size: 10,
  priv: "priv/games_repo",
  migration_primary_key: [type: :binary_id],
  migration_lock: false



# ----------------------------
# Import environment-specific configs
# ----------------------------
import_config "#{config_env()}.exs"

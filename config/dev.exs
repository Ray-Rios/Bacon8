import Config

# ----------------------------
# Guardian (dev)
# ----------------------------
config :bacon8, Bacon8.Auth.Guardian,
  issuer: "bacon8",
  # Secret picked up from runtime.exs
  secret_key: System.get_env("GUARDIAN_SECRET_KEY") || "dev_guardian_secret_placeholder"

# ----------------------------
# Endpoint
# ----------------------------

config :bacon8, Bacon8Web.Endpoint,
  http: [ip: {0, 0, 0, 0}, port: 4000],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "sX9/Rn5BIxDT+OD20jOYEYImGrN9SR7F9NLC1av9z+aip2mySJdALjSICoNOX5Hc",
  # No asset watchers: CSS and JS are built inside the container image
  # (Dockerfile), never on the development machine.
  watchers: [],
  live_reload: [
    patterns: [
      ~r"priv/static/.*(js|css|png|jpeg|jpg|gif|svg)$",
      ~r"priv/gettext/.*(po)$",
      ~r"lib/bacon8_web/(controllers|live|components)/.*(ex|heex)$"
    ]
  ]

# ----------------------------
# Dev routes & logging
# ----------------------------
config :bacon8, dev_routes: true

# The store's pretend payment provider (/store/fake-checkout/...).
config :bacon8, BaconStore.Payments, fake_enabled: true
config :logger, :console, format: "[$level] $message\n"
config :phoenix, :stacktrace_depth, 20
config :phoenix, :plug_init_mode, :runtime
config :swoosh, :api_client, false

# ----------------------------
# Redis & Mail (dev)
# ----------------------------
config :bacon8, :redis_url,
  System.get_env("REDIS_URL") || "redis://redis:6379/0"

config :bacon8, :enable_redis, true

config :bacon8, Bacon8.Mailer,
  adapter: Swoosh.Adapters.SMTP,
  relay: System.get_env("SMTP_HOST") || "mailhog",
  port: String.to_integer(System.get_env("SMTP_PORT") || "1025"),
  username: System.get_env("SMTP_USER"),
  password: System.get_env("SMTP_PASS"),
  tls: :never,
  retries: 1

# ----------------------------
# Password hashing (dev - PBKDF2)
# ----------------------------
config :pbkdf2_elixir, :rounds, 1  # Fast for development (default is 160000)

# ----------------------------
# Development-only auth shortcuts
# ----------------------------
# Enables POST /api/auth/dev-verify, which marks any account's email verified
# without the code. Needed because `authenticate_user_secure/3` refuses a login
# until `email_verified_at` is set, so an account registered from the game client
# could never log in a second time without a working mailbox.
#
# Set ONLY here. In prod the endpoint 404s, which is what you want - it takes an
# unauthenticated email and grants it exactly what verification exists to prove.
config :bacon8, :allow_dev_verify, true

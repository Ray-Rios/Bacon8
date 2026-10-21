import Config

# Minimal test configuration to allow unit tests that don't boot the DB
config :bacon8, Bacon8.Repo,
  username: System.get_env("DB_USERNAME") || "postgres",
  password: System.get_env("DB_PASSWORD") || "postgres",
  database: System.get_env("DB_NAME") || "bacon8_test",
  hostname: System.get_env("DB_HOST") || "localhost",
  port: String.to_integer(System.get_env("DB_PORT") || "5432"),
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10

config :bacon8, Bacon8.GamesRepo,
  username: System.get_env("DB_USERNAME") || "postgres",
  password: System.get_env("DB_PASSWORD") || "postgres",
  database: System.get_env("GAMES_DB_NAME") || "bacon8_games_test",
  hostname: System.get_env("DB_HOST") || "localhost",
  port: String.to_integer(System.get_env("DB_PORT") || "5432"),
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10

config :bacon8, Bacon8Web.Endpoint,
  server: false

config :logger, level: :warning

# Drive: no background janitor in tests; bodies go to a throwaway directory.
config :bacon8, Bacon8.Drive.Janitor, enabled: false
config :bacon8, BaconStore.Store.Sweeper, enabled: false

# Plugins: tests drive activation themselves; no background runtime, a fixture
# plugin, and nothing active by default.
config :bacon8, Bacon8.Plugins.Runtime, enabled: false
config :bacon8, :extra_plugins, [Bacon8.Test.FixturePlugin]
config :bacon8, :default_active_plugins, []
# The store plugin's payments: the fake provider on, and no keys from the shell.
config :bacon8, BaconStore.Payments, fake_enabled: true, read_env: false
config :bacon8, Bacon8.Storage, root: Path.join(System.tmp_dir!(), "bacon8_test_drive")

# Tests register accounts and then log in as them; without this the login gate
# on email_verified_at makes that a two-step dance in every fixture.
config :bacon8, :allow_dev_verify, true

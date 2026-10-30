#!/bin/bash
set -e

# ----------------------------
# Environment variables are loaded by docker-compose
# ----------------------------
echo "Current MIX_ENV: $MIX_ENV"
echo "DATABASE_URL: ${DATABASE_URL:0:30}..."

# ----------------------------
# Generate secrets (dev only)
# ----------------------------
if [ "$MIX_ENV" = "dev" ]; then
  if [ -z "$SECRET_KEY_BASE" ] || [[ "$SECRET_KEY_BASE" == GENERATE_WITH_mix_phx.gen.secret* ]]; then
    echo "Generating SECRET_KEY_BASE for dev..."
    export SECRET_KEY_BASE=$(mix phx.gen.secret 64)
  fi

  if [ -z "$LIVE_VIEW_SIGNING_SALT" ] || [[ "$LIVE_VIEW_SIGNING_SALT" == GENERATE_WITH_mix_phx.gen.secret* ]]; then
    echo "Generating LIVE_VIEW_SIGNING_SALT for dev..."
    export LIVE_VIEW_SIGNING_SALT=$(mix phx.gen.secret 32)
  fi
  
  if [ -z "$GUARDIAN_SECRET_KEY" ] || [ "$GUARDIAN_SECRET_KEY" == "GENERATE_WITH_mix_guardian.gen.secret" ]; then
    echo "Generating GUARDIAN_SECRET_KEY for dev..."
    export GUARDIAN_SECRET_KEY=$(mix guardian.gen.secret)
  fi
else
  # ----------------------------
  # Fail fast in prod if secrets are missing
  # ----------------------------
  if [ -z "$SECRET_KEY_BASE" ]; then
    echo "❌ ERROR: SECRET_KEY_BASE is not set in prod!"
    exit 1
  fi
  if [ -z "$LIVE_VIEW_SIGNING_SALT" ]; then
    echo "❌ ERROR: LIVE_VIEW_SIGNING_SALT is not set in prod!"
    exit 1
  fi
  if [ -z "$DATABASE_URL" ]; then
    echo "❌ ERROR: DATABASE_URL is not set in prod!"
    exit 1
  fi
fi

echo "SECRET_KEY_BASE: ${SECRET_KEY_BASE:0:8}..."
echo "LIVE_VIEW_SIGNING_SALT: ${LIVE_VIEW_SIGNING_SALT:0:8}..."

# ----------------------------
# Wait for database
# ----------------------------
echo "Waiting for PostgreSQL to be ready..."
until pg_isready -h db -p 5432 -U postgres &> /dev/null; do
  echo "Waiting for database..."
  sleep 2
done
echo "PostgreSQL is ready!"

# ----------------------------
# Database setup (production-safe)
# ----------------------------
if [ "$MIX_ENV" = "prod" ]; then
  echo "Production mode: Skipping database creation (should be handled by init job)"
  echo "Production mode: Skipping migrations (should be handled by init job)"
else
  # ----------------------------
  # Create database using Ecto (dev only)
  # ----------------------------
  echo "Creating database..."
  mix ecto.create --quiet || echo "Either the Database already exists or the creation failed continuing..."

  # ----------------------------
  # Run Ecto migrations with retry (dev only)
  # ----------------------------
  echo "Running migrations..."
  for i in {1..3}; do
    if mix ecto.migrate; then
      echo "Migrations completed successfully"
      break
    else
      echo "Migration attempt $i failed, retrying in 5 seconds..."
      sleep 5
    fi
  done
fi

# ----------------------------
# Wait for Redis
# ----------------------------
REDIS_HOST="${REDIS_HOST:-redis}"
REDIS_PORT="${REDIS_PORT:-6379}"

# Speaks RESP over bash's own /dev/tcp rather than shelling out to redis-cli.
#
# The runtime image has no redis-tools, so the old check printed
# "redis-cli: command not found" three times on every single boot and then
# carried on regardless. It was not testing Redis at all - it was testing
# whether a binary existed, always getting "no", and reporting that as a failed
# Redis check. Three lines of noise in every log, on a container that was fine.
#
# This actually connects and looks for +PONG, and needs nothing installed.
redis_ready() {
  exec 3<>"/dev/tcp/${REDIS_HOST}/${REDIS_PORT}" 2>/dev/null || return 1
  printf 'PING\r\n' >&3
  local reply=""
  read -r -t 2 reply <&3
  exec 3<&- 2>/dev/null
  exec 3>&- 2>/dev/null
  [[ "$reply" == "+PONG"* ]]
}

echo "Waiting for Redis at ${REDIS_HOST}:${REDIS_PORT}..."
redis_up=0
for i in 1 2 3; do
  if redis_ready; then
    echo "Redis is ready!"
    redis_up=1
    break
  fi
  echo "Redis not answering (attempt $i/3), retrying in 5 seconds..."
  sleep 5
done

# Deliberately NOT fatal. The app opens its own Redis connections lazily and
# retries, so a slow-starting Redis should not stop the web tier from booting -
# but an unreachable one should say so once, clearly, instead of scrolling three
# identical errors past whoever is reading the log for a different reason.
if [ "$redis_up" -ne 1 ]; then
  echo "WARNING: Redis at ${REDIS_HOST}:${REDIS_PORT} did not answer. Starting anyway;"
  echo "         anything backed by Redis (caching, presence) will fail until it does."
fi

# ----------------------------
# Start Phoenix server
# ----------------------------
echo "Starting Phoenix server..."

if [ "$MIX_ENV" = "prod" ]; then
  echo "Production mode: Starting Bacon8 application..."
  
  # Use the compiled release (multi-stage build copies to /app/)
  if [ -f "/app/bin/bacon8" ]; then
    echo "Using Elixir release (multi-stage build)..."
    exec /app/bin/bacon8 start
  elif [ -f "/app/_build/prod/rel/bacon8/bin/bacon8" ]; then
    echo "Using Elixir release (single-stage build)..."
    exec /app/_build/prod/rel/bacon8/bin/bacon8 start
  else
    echo "Starting with compiled application..."
    cd /app
    # Start the application directly without Mix's file watching
    exec elixir --erl "-detached" -pa _build/prod/lib/*/ebin -e "Application.ensure_all_started(:bacon8)" --no-halt
  fi
else
  # Development mode
  exec mix phx.server
fi
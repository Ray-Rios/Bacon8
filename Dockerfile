# -------------------------------
    # Base image
    
    # -------------------------------
        FROM elixir:1.19
    # -------------------------------
        # System deps
        # -------------------------------
            RUN apt-get update && apt-get install -y \
            curl \
            git \
            build-essential \
            postgresql-client \
            inotify-tools \
            redis-tools \
            ca-certificates \
            nodejs \
            npm \
            && rm -rf /var/lib/apt/lists/*
            
            # Ensure CA certificates are up to date for TLS verification
            RUN update-ca-certificates || true
            
        # -------------------------------
        # Set workdir & env
        # -------------------------------
            WORKDIR /app
            ARG MIX_ENV=dev
            ENV MIX_ENV=${MIX_ENV}

        # -------------------------------
        # Copy deps files for caching
        # -------------------------------
            COPY mix.* ./
    
        # -------------------------------
        # Install hex and rebar first
        # -------------------------------
            RUN mix local.hex --force && mix local.rebar --force
            
        # -------------------------------
        # Copy config and install deps
        # -------------------------------
            COPY config ./config

        # -------------------------------    
        # Set temporary build args and env vars for compilation
        # -------------------------------
            ARG SECRET_KEY_BASE=build_time_secret_key_base_placeholder_64_chars_long_minimum
            ARG LIVE_VIEW_SIGNING_SALT=build_time_salt_32_chars_long_min
            ARG GUARDIAN_SECRET_KEY=build_time_guardian_secret_key_placeholder_64_chars_long_minimum
            
            # Set environment variables from build args for compilation only
            ENV SECRET_KEY_BASE=${SECRET_KEY_BASE}
            ENV LIVE_VIEW_SIGNING_SALT=${LIVE_VIEW_SIGNING_SALT}
            ENV GUARDIAN_SECRET_KEY=${GUARDIAN_SECRET_KEY}
            
            RUN mix deps.get && mix deps.compile
            
        # -------------------------------
        # Copy source code and compile
        # -------------------------------
            COPY lib ./lib
            # Installed plugins (BACON8.md §9)
            COPY plugins ./plugins
            
        # -------------------------------
        # Copy assets and build them - FORCE REBUILD 2025-11-19
        # -------------------------------
            COPY assets ./assets
            # Create priv directory structure but DON'T copy old static assets
            RUN mkdir -p priv/static/assets priv/static/fonts priv/repo priv/games_repo priv/gettext
            # Copy only non-static priv files
            COPY priv/repo ./priv/repo
            # THE GAMES REPO'S MIGRATIONS. Adding a repo to :ecto_repos is not
            # enough on its own when priv is copied SELECTIVELY: without this
            # line the image contains no migration files for GamesRepo, so
            # Ecto.Migrator finds an empty directory, runs nothing, and returns
            # success. The deploy goes green, the database is created, and the
            # app boots with no schema - which surfaces much later as
            # `relation "games" does not exist` and looks nothing like a
            # packaging problem.
            COPY priv/games_repo ./priv/games_repo
            COPY priv/gettext ./priv/gettext
            # Copy static files that don't get regenerated (tri.gif, favicon.ico, robots.txt, etc.)
            COPY priv/static/tri.gif ./priv/static/
            COPY priv/static/favicon.ico ./priv/static/
            COPY priv/static/robots.txt ./priv/static/
            COPY priv/static/sitemap.xml ./priv/static/
            COPY priv/static/.well-known ./priv/static/.well-known
            COPY priv/static/maps ./priv/static/maps
            COPY priv/static/models ./priv/static/models
            RUN cd assets && \
                npm config set fetch-retry-mintimeout 20000 && \
                npm config set fetch-retry-maxtimeout 120000 && \
                npm config set fetch-retries 10 && \
                npm config set fetch-timeout 300000 && \
                npm config set registry https://registry.npmjs.org/ && \
                (npm install --prefer-offline --no-audit --no-fund || \
                 npm install --no-audit --no-fund || \
                 npm install --no-audit --no-fund)
            
            # Build assets based on environment
            RUN if [ "$MIX_ENV" = "prod" ]; then \
                echo "=== Cleaning any old assets ===" && \
                rm -rf priv/static/assets/* priv/static/cache_manifest.json && \
                echo "=== Running npm deploy only (no phx.digest yet) ===" && \
                cd assets && npm run deploy && cd .. && \
                echo "=== CSS size after npm deploy ===" && \
                ls -lh priv/static/assets/app.css && \
                head -c 200 priv/static/assets/app.css && echo && \
                echo "=== Now running phx.digest ===" && \
                mix phx.digest && \
                echo "=== Final CSS size after phx.digest ===" && \
                ls -lh priv/static/assets/app*.css && \
                head -c 200 priv/static/assets/app.css; \
            else \
                mix assets.build; \
            fi
            
            RUN mix compile
            
        # -------------------------------
        # Build release for production
        # -------------------------------
            RUN if [ "$MIX_ENV" = "prod" ]; then \
                mix release; \
            fi
        
    # -------------------------------
    # Expose port & start script
    # -------------------------------
    EXPOSE 4000
    
    # Create uploads directory with proper permissions
    RUN mkdir -p /app/uploads && \
        chmod 777 /app/uploads
    
    COPY bacon8-start.sh /usr/local/bin/bacon8-start.sh
    RUN chmod +x /usr/local/bin/bacon8-start.sh
    
    CMD ["/usr/local/bin/bacon8-start.sh"]
                    
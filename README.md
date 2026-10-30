# Bacon8

A batteries-included Phoenix 1.7 / LiveView 1.0 application: authentication and
account security, a CMS, a storefront, real-time chat, a windowed
"desktop" UI, a job scheduler, and a multiplayer **games
platform API** — deployed to Kubernetes with kustomize overlays.

It is a working application (it runs bacon8.net), published so it can be read,
forked and stripped for parts. **It is a monolith, not a generator.** There is no
`mix phx.new.batteries` here — you clone it, delete the contexts you do not want,
and keep the ones you do. The sections below are organised to make that
practical: each subsystem says what it is and roughly what removing it costs.

---

## Contents

- [What's in the box](#whats-in-the-box)
- [Requirements](#requirements)
- [Quick start](#quick-start)
- [Configuration](#configuration)
- [Architecture](#architecture)
- [HTTP API](#http-api)
- [Assets](#assets)
- [Testing and linting](#testing-and-linting)
- [Deployment](#deployment)
- [Operations](#operations)
- [Security notes](#security-notes)
- [Using this as a starting point](#using-this-as-a-starting-point)
- [License](#license)

---

## What's in the box

| Subsystem | What it gives you | Where |
|---|---|---|
| **Accounts & auth** | Registration, email verification by 6-digit code, login by email *or* username, password reset, Guardian JWT sessions, 2FA scaffolding | `lib/bacon8/accounts`, `auth` |
| **Account security** | Login-attempt tracking, lockout after repeated failures, device fingerprinting, block/allow identifier lists, behavioural bot signals, IP rate limiting | `lib/bacon8/security`, `rate_limiter.ex` |
| **Content / CMS** | Posts, pages, comments, media library with tags, plus a WordPress-shaped `cms_*` set (posts, terms, taxonomies, meta) | `lib/bacon8/content` |
| **Store & Gems** | Digital products (downloads, game items, access passes, license keys) and Gem packs, bought with a card or with Gems; a double-entry Gem ledger; Stripe Checkout behind a provider behaviour with an idempotent webhook inbox; a buyer's library. A plugin (**Bacon Store**, mounted at `/store`): delete the folder for a site without a store | `plugins/bacon_store` |
| **Chat channels** | Channels, threads, reactions, attachments, invites, presence; a plugin (the old forum) | `plugins/chat_channels` |
| **Suggestions & Bugs** | Members' suggestions and bug reports with screenshots and votes; admins approve and submit them to Claude, whose runner on the development PC fixes, tests, reviews, commits and (if allowed) deploys them. A plugin, from the start menu; not for guests | `plugins/feedback` |
| **Chat** | Phoenix Channels with presence, optional Redis bridge for cross-pod delivery | `lib/bacon8_web/channels`, `redis_pubsub.ex` |
| **Desktop UI** | A taskbar-and-windows shell rendered as a global `live_component` on every authenticated page — not a route | `lib/bacon8/desktop`, `desktop_live.ex` |
| **Scheduler** | Recurring events, manual run/pause/resume, and a secret-authenticated webhook trigger | `lib/bacon8/scheduler` |
| **Files & media** | The drive (per-user storage with quotas, storage tiers and share links), uploads via Arc, image processing, avatars | `lib/bacon8/drive`, `files`, `media_processor.ex` |
| **Notifications & email** | Swoosh + SMTP, HTML templates, delivery logging | `lib/bacon8/email`, `notifications` |
| **Moderation & audit** | Audit log, moderation queue, admin LiveViews | `lib/bacon8/moderation`, `audit.ex` |
| **Games platform** | Games, characters, the game-server registry, single-session claims, client releases and launcher downloads. Game-specific features come from plugins. **Its own database.** | `lib/bacon8/games` |
| **Plugins** | WordPress-style: a game or feature is a folder under `plugins/`, compiled in and switched on or off from `/admin/plugins` without a redeploy. Four ship with the hub: **Bacon World**, a 3D multiplayer RPG in the browser (three.js; its notebook is [`BACON_WORLD.md`](plugins/bacon_world/BACON_WORLD.md)), **Bacon Store** (the shop), **Chat Channels** and **Suggestions & Bugs**. A private plugin (RaysSpaceSim) can live in the same folder as its own git repository. | `lib/bacon8/plugin.ex`, `plugins/` |

The **games platform** is the least generic and the most actively developed part.
If you are here for a web app, it is the first thing to delete — it is cleanly
separated behind its own Ecto repo and its own router scope. If you are here
*because* of it, see [Architecture](#architecture).

---

## Requirements

| | |
|---|---|
| Elixir | `~> 1.19.0` |
| Erlang/OTP | matching your Elixir build |
| Database | PostgreSQL-compatible. Defaults point at host `db`, port `26257` — override for a stock local Postgres (see [Configuration](#configuration)) |
| Node | only inside the assets container — see [Assets](#assets) |
| Redis | optional; enables cross-pod pubsub |
| Docker | recommended for assets; required for the deploy scripts |
| Kubernetes | optional; k3s manifests provided |

---

## Quick start

```bash
git clone https://github.com/Ray-Rios/Bacon8
cd Bacon8

# Point at your database before the first run (see Configuration).
export DB_HOST=localhost DB_PORT=5432 DB_USERNAME=postgres DB_PASSWORD=postgres

mix deps.get
mix ecto.setup     # both databases: create, migrate (plugins' migrations too), seed
mix phx.server
```

CSS and JavaScript are built inside the container image, not on your machine (see
[Assets](#assets)), so a bare `mix phx.server` serves pages without them.

Then:

| | |
|---|---|
| App | http://localhost:4000 |
| Health check | http://localhost:4000/health |
| MailHog, if you run one | http://localhost:8025 |

`mix ecto.setup` runs migrations for **both** repos and every installed plugin, and seeds the main one.

### Creating a verified user without a mail server

```bash
curl -X POST http://localhost:4000/api/auth/register \
  -H "Content-Type: application/json" \
  -d '{"email":"test@example.com","name":"TestUser","password":"SecurePass123!"}'

curl -X POST http://localhost:4000/api/auth/dev-verify \
  -H "Content-Type: application/json" \
  -d '{"email":"test@example.com"}'

curl -X POST http://localhost:4000/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"test@example.com","password":"SecurePass123!"}'
```

> **`dev-verify` marks any address verified, without authentication.** It is gated
> on `:allow_dev_verify`, which is set only in `config/dev.exs` and
> `config/test.exs`; in production the route 404s. **Do not "fix" that 404 by
> enabling the flag** — register with someone else's address, call this, log in as
> them is the entire attack.

---

## Configuration

Everything is environment variables. Nothing secret is committed.

### Database

Two independent Ecto repos, two databases.

| Variable | Default | Applies to |
|---|---|---|
| `DB_HOST` | `db` | both |
| `DB_PORT` | `26257` | both |
| `DB_USERNAME` | `root` | both |
| `DB_PASSWORD` | `postgres` | both |
| `DB_NAME` | `bacon8_dev` | main repo |
| `GAMES_DB_NAME` | `bacon8_games_dev` | games repo |
| `DATABASE_URL` / `GAMES_DATABASE_URL` | — | production; override the pieces above |
| `POOL_SIZE` | | production pool sizing |

The defaults assume a container named `db` on port 26257. **For a stock local
Postgres set `DB_HOST=localhost` and `DB_PORT=5432`.**

### Secrets — generate these before deploying

```bash
mix phx.gen.secret 64   # SECRET_KEY_BASE
mix phx.gen.secret 32   # LIVE_VIEW_SIGNING_SALT
mix phx.gen.secret      # GUARDIAN_SECRET_KEY
```

| Variable | Purpose |
|---|---|
| `SECRET_KEY_BASE` | Phoenix session/cookie signing |
| `LIVE_VIEW_SIGNING_SALT` | LiveView session signing |
| `GUARDIAN_SECRET_KEY` | JWT signing |
| `GAMES_SERVER_API_KEY` | **Master credential.** Lets its holder act on behalf of *any* user through the games API. Server-side only |
| `PROJECTS_API_KEY` | Read-only access to the calendar/projects endpoint |

### Web, mail, cache

| Variable | Notes |
|---|---|
| `BACON8_HOST`, `PORT` | public host and bind port |
| `CORS_ALLOWED_ORIGINS` | comma-separated |
| `SMTP_HOST`, `SMTP_PORT`, `SMTP_USER`, `SMTP_PASS`, `SMTP_VERIFY` | dev defaults to port 1025 (MailHog) |
| `FROM_EMAIL`, `FROM_NAME`, `REPLY_TO_EMAIL` | sender of the site's mail (default `no-reply@bacon8.net`, "Bacon8") and, optionally, where replies go. With Namecheap Private Email the sender can be an alias of the mailbox in `SMTP_USER` |
| `ENABLE_REDIS`, `REDIS_URL` | set both to bridge pubsub across pods |

### Plugins

| Variable | Notes |
|---|---|
| `BACON8_ACTIVE_PLUGINS` | comma-separated plugin slugs active until an admin toggles them on /admin/plugins (default: `bacon_world`, `bacon_store`, `chat_channels`) |

A plugin's own settings are documented in its README.

---

## Architecture

### Two databases, on purpose

```
Bacon8.Repo          bacon8_dev           site: users, content, store, wallet, chat, …
                                          priv/repo/migrations
Bacon8.GamesRepo     bacon8_games_dev     games: games, characters, servers, releases, plugins' tables
                                          priv/games_repo/migrations
```

Game data is isolated so a game can be wiped, migrated or restored without
touching the website, and so the games API can eventually move to its own service
without a data untangling exercise.

**The consequence to know about:** game tables cannot have a foreign key to
`users`, because `users` lives in the other database. Every `user_id` in
`GamesRepo` is a bare `binary_id`, and referential integrity there is the
application's job. That is a deliberate trade, and it is why the games contexts
always take a `user_id` rather than a `%User{}`.

### Redis is optional and additive

Without it, `Phoenix.PubSub` works normally within one node. With `ENABLE_REDIS`,
a small bridge subscribes to channel patterns (`channel:*`, `presence:channel:*`,
`chat:channels`) and forwards Redis messages into the local PubSub, publishing
outward as well, so several pods see each other's events. Nothing else changes.

### Plugins

A plugin is a folder under `plugins/<slug>/` with its own namespace, routes,
migrations, LiveView hooks and tests, compiled into the app. An admin activates
or deactivates it on `/admin/plugins`; an inactive plugin's routes answer 404 and
its processes stop, but its data stays. `plugins/README.md` and `plugins/bacon_world`
show the shape. A private plugin is its own git repository cloned into `plugins/`,
which the hub's `.gitignore` already ignores.

---

## HTTP API

All JSON. Authentication is a Guardian bearer token unless stated otherwise.

### Auth

```
POST /api/auth/register             POST /api/auth/verify-code
POST /api/auth/login                POST /api/auth/verify-email
POST /api/auth/logout               POST /api/auth/resend-verification
POST /api/auth/verify-bearer        POST /api/auth/verify
                                    POST /api/auth/dev-verify      (dev only)
```

### Games platform

Under `/api/games/:game_slug`. Accepts a **player bearer token**, or an
`X-API-Key` matching `GAMES_SERVER_API_KEY` for a trusted dedicated game server
acting on a player's behalf (which must also pass `user_id`).

```
GET|POST            /characters
GET|PUT|DELETE      /characters/:id
POST                /characters/:id/claim         server key only
POST                /characters/:id/release       server key only
PUT                 /characters/:id/instance_location   players may only clear
GET                 /servers
POST                /servers/heartbeat            server key only
POST                /servers/offline              server key only
GET                 /releases/latest              the launcher's update check
GET                 /releases/blobs/:sha
```

A game's own endpoints come from its plugin and mount under the same prefix
(`/api/games/<game slug>/...`, see `plugins/README.md`).

Two of these are load-bearing for security and worth copying if you build
something similar:

- **`/servers/heartbeat` and `/servers/offline` reject a player token.** If a
  player could register a server, they could advertise one they control to
  everyone browsing the server list. That is phishing, not cheating.
- **An instance server should ask the hub on every join.** With one server
  process per world, an address is all a stranger would need; an access check
  per join makes a revoked invitation take effect immediately.

Server liveness is heartbeat **age**, not deregistration — a crashed server never
gets to deregister.

### Scheduler and projects

```
GET|POST            /api/scheduler/events
GET|PUT|DELETE      /api/scheduler/events/:id
POST                /api/scheduler/events/:id/{run,pause,resume}
GET                 /api/scheduler/project-events
POST                /api/webhooks/scheduler/:secret        public, secret in path
GET                 /api/auth/projects/calendar            bearer or X-API-Key
GET                 /health
GET                 /api/status
```

---

## Assets

**Nothing is built on the development machine.** Tailwind, esbuild and the
TypeScript/three.js sources in `assets/` (plus each plugin's `assets/js`) are
built inside the container image by `Dockerfile.multistage`, and the compiled
files live only in the image. `config/dev.exs` starts no asset watchers.

This exists because host npm installs were repeatedly destructive on Windows and
non-reproducible between machines. If you are on Linux and want host npm, run it
in `assets/` directly, but keep `node_modules` and the build output out of commits.

---

## Testing and linting

Tests need only Postgres. The maintainers run them in throwaway Docker containers
(the commands are in [`BACON8.md`](BACON8.md) §14):

```bash
mix test          # creates and migrates the test databases first
```

`warnings_as_errors` is on in `:dev` and `:test` and off in `:prod`, so a
warning fails your build but never blocks a release. (`mix lint` and the `assets.*`
aliases still point at a script that was removed when asset builds moved into the
image; see BACON8.md §13.)

Bacon World's JavaScript has its own unit tests: `plugins/bacon_world/assets/js/__tests__/run.sh`.

---

## Deployment

Kustomize overlays for k3s:

```
k3s/base/               deployment, services, PVCs, ingress
k3s/overlays/dev/       development namespace
k3s/overlays/prod/      production namespace
k3s/jobs/               one-shot maintenance jobs
k3s/ssl/                TLS material
```

```bash
kubectl apply -k k3s/overlays/dev
kubectl apply -k k3s/overlays/prod
kubectl rollout restart deployment/bacon8-web -n bacon8
```

`deploy-prod.sh` wraps build, rollout and certificates, and applies each
plugin's own `k3s/` manifests. A game plugin ships its own scripts for its
dedicated-server image.

Migrations run through the release, not through mix:

```bash
kubectl exec -n bacon8 deploy/bacon8-web -- \
  /app/bin/bacon8 eval "Bacon8.Release.migrate()"
```

**`k3s/overlays/prod/secrets.yaml`, `ingress.yaml` and `mailhog-auth-secret.yaml`
are gitignored.** Copy the dev equivalents, change every value, and keep them out
of version control.

---

## Operations

```bash
./scripts/postgres-ops.sh backup|restore|list|clean|connect|size|logs
./scripts/redis-ops.sh    backup|restore|monitor|keys "chat:*"|flush
./bacon8-start.sh
```

`redis-ops.sh flush` deletes everything. It is not guarded.

---

## Security notes

Read before deploying, not after.

- **`GAMES_SERVER_API_KEY` is a master credential.** It authorises acting as any
  user. Keep it server-side, rotate it if an image leaks, and never put it in a
  config file that gets baked into a client.
- **`dev-verify` must stay 404 in production.** See the warning in
  [Quick start](#quick-start).
- **Rate limiting is per IP.** Everything behind one NAT shares a budget; in
  development every local client is `127.0.0.1`, so rapid restarts will earn you a
  `429` that reads exactly like a wrong password.
- **Never commit `k3s/overlays/prod/secrets.yaml`.** It is in `.gitignore`;
  keep it that way.
- **Backups and uploads are gitignored** (`backups/`, `uploads/`,
  `priv/static/uploads/`). Database dumps contain user records — check before you
  change those rules.
- **Sobelow runs in `mix lint`.** Take its findings seriously; it is there for a
  reason.

---

## Using this as a starting point

An honest map of what it costs to remove each piece, largest win first:

| Remove | Effort | Notes |
|---|---|---|
| Games platform | **Low** | Own repo, own router scope, own migrations. Delete `lib/bacon8/games`, `games_repo.ex`, `priv/games_repo`, the `/api/games` scope, and drop `Bacon8.GamesRepo` from `ecto_repos` |
| Store & Gems | **Low** | A plugin: delete `plugins/bacon_store` and the hub builds and runs without a store (entitlements stay in core) |
| Chat channels | **Low** | A plugin: delete `plugins/chat_channels` and the hub builds and runs without chat. RaysSpaceSim requires it |
| Suggestions & Bugs | **Low** | A plugin: delete `plugins/feedback` (and its scheduled task on the PC, if you set one up) |
| Desktop UI | Medium | It is rendered from the app layout on every authenticated page, so removal is a layout edit plus the component tree |
| CMS | Medium | The `cms_*` tables are independent of `posts`; you can drop one and keep the other |
| Accounts / auth / security | — | Load-bearing. This is the part most worth keeping |

The pieces most likely to be useful on their own: the **security stack** (device
fingerprints, identifier lists, lockout, rate limiting), the **Gem ledger and
webhook inbox**, and the **plugin system**.

**Where this is going:**
ADR 0001 (core and plugins; removed from the tree on 2026-10-24, still in git: `git show 95aba50^:docs/adr/0001-core-and-plugins.md`). The store (with
Gems and payments) became a plugin on 2026-10-21, and the games platform is next. A new
site will then start as the core plus the plugins it wants, rather than by deleting
subsystems.

Shipped media is our own or CC0. The site's Credits page (`/pages/credits`, a CMS
page) lists the sources; the 3D models' credits sit beside them on the models volume
(`Humans/CREDITS.md`), and the sounds' in `priv/static/audio/world/CREDITS.md`.

**Documentation map:**

- `README.md`: this front door.
- [`BACON8.md`](BACON8.md): engineering context, decisions, invariants and workflow. Read it
  before changing the hub.
- [`BACON_WORLD.md`](plugins/bacon_world/BACON_WORLD.md): Bacon World's state, decisions and next steps.
- [`plugins/Bacon8_Plugin_Integration.md`](plugins/Bacon8_Plugin_Integration.md): how to integrate a game or any
  software (the games API, the plugin contract, a checklist for AI agents).
- `plugins/*/README.md`: each plugin's reference.
- [`docs/pages-blog-builder.md`](docs/pages-blog-builder.md): the page and blog builder.
- [`Handy_Command_Samples.md`](Handy_Command_Samples.md): the maintainer's deploy and operations cheat sheet.
  The old architecture decision record (`docs/adr/`) is in git history only.

---

## License

MIT — see [`LICENSE`](LICENSE).

Without a license file, published code is "all rights reserved" by default and
nobody may legally fork it. The `LICENSE` file was added on 2026-08-21 to match
the intent this README had always stated; **confirm the copyright holder line
reads the way you want it to.**

# Integrating a game (or any software) into Bacon8

This is the guide for bringing an outside project into a Bacon8 hub: a Godot, Unity, Unreal or web game, a
tool, a service. It is written to be read by a developer or by an AI coding agent that has never seen this
repository. Read it top to bottom once, then use the checklists in section 12.

Facts here were checked against the code on 2026-10-29. When this file and the code disagree, the code wins:
`lib/bacon8/plugin.ex` (the plugin contract), `lib/bacon8/plugin/routes.ex` (route declarations),
`lib/bacon8_web/router.ex` (the games API) and `lib/bacon8_web/controllers/api/games_controller.ex`.
Longer background: `BACON8.md` §9 (plugins and the games platform), `plugins/README.md` (the folder shape),
`plugins/bacon_world/` (a complete game plugin) and `plugins/bacon_store/` (a complete site plugin).

---

## 1. The 60-second picture

Bacon8 is a Phoenix/LiveView web hub: accounts, sign-in, a CMS, a store, chat, a games list, a launcher
download, and a **games API**. A *plugin* is a folder in `plugins/` that adds to it.

Your project has two halves and they live in different places:

| Half | What it is | Where it lives | Language |
|---|---|---|---|
| **The game** | Your client (and optional dedicated server) | Your own repository. Never inside the hub. | Anything (Godot/GDScript, C#, C++, JS...) |
| **The plugin** | Your game's presence in the hub: its card on `/games`, its page, its admin screen, the items it sells, its extra API routes and tables | `plugins/<your_slug>/` in the hub | Elixir |

The game talks to the hub over **HTTPS + JSON** using the games API (section 6). It does not need to know
Elixir, and nothing of the hub is linked into it. The plugin is optional extras on top of that API: the
smallest useful plugin is about 25 lines (section 4).

Everything is public-API driven, so *any* software that can make HTTP requests can integrate: a Godot game,
a bot, a mobile app, a CLI.

### What you get for free once you are in

- **Accounts and sign-in** for your players (email or username, email verification, lockouts, rate limits).
- **Characters** per player per game, stored by the hub (`stats` and `settings` JSON that you define).
- **A server registry** with heartbeats, player rosters, "who is online", and a control channel back to your
  servers.
- **Single-session claims** (one live session per character).
- **Client releases** for a self-updating launcher (content-addressed, ranged downloads) if you ship a download.
- **A card on `/games`** (pictures, text, Play button), a **live status** corner on the front page (online,
  players), and an **admin page** you can extend.
- **A store**: your in-game items and passes become products (card or Gems), and a purchase becomes an
  **entitlement** your game checks (section 8).
- **Chat channels**, **the CMS** (a download page for your game, patch notes), **the drive**, and **the audit
  log**, all reachable from your plugin's code.

---

## 2. Requirements

### For the hub operator (who installs the plugin)

- A running Bacon8 hub (Elixir 1.19, Phoenix 1.7, PostgreSQL; Kubernetes in production). You need access to
  the hub's repository because the plugin is compiled into it. **A plugin runs inside the hub with full
  access to its data and no sandbox. Only install plugins whose code you have read.**
- Your game's slug (section 3).
- A deploy (`scripts/deploy-prod.sh` for production) after adding or changing plugin code. Activating or
  deactivating a plugin afterwards needs no deploy.

### For the game developer

- The ability to make HTTPS requests with JSON bodies and an `Authorization: Bearer <token>` header. In Godot 4:
  `HTTPRequest`, `JSON`, and `HTTPClient` (for streaming downloads).
- The hub's base URL (supplied by the operator; it is configuration, never hard-coded in a public repository).
- For a dedicated server: the operator-issued **server API key**, held server-side only (section 9).
- For the plugin: Elixir 1.19 only if you want to build or test the plugin yourself. A
  game developer can hand the operator a plugin folder, or the operator can write the small one in section 4.

---

## 3. Names and rules (get these right first)

- **Plugin slug**: lowercase letters, digits and underscores, starting with a letter (`^[a-z][a-z0-9_]*$`).
  It is the folder name (`plugins/frog_quest/`), the module prefix (`FrogQuest`), the table prefix
  (`frog_quest_...`), the page address (`/games/frog_quest`) and the admin address (`/admin/frog_quest`).
- **Game slug**: used in the API (`/api/games/<game slug>/...`) and the `games` table. It defaults to the
  plugin slug. A plugin may choose another with `game()`'s `:slug` (RaysSpaceSim's plugin slug is
  `rays_space_sim`, its game slug is `rays-space-sim`, because its shipped client already used that). Decide
  it once: clients embed it.
- **Namespaces**: your own (`FrogQuest`, `FrogQuestWeb`). Never `Bacon8.*`.
- **Tables**: prefixed with the plugin slug, created by the plugin's own migrations.
- **Talk to the hub through its public context functions** (`Bacon8.Games`, `Bacon8.Entitlements`,
  `Bacon8.Drive`, `Bacon8.Content`...). The hub never references a plugin module, so the hub must still
  build without your folder.
- **Renaming later** changes stored names; return the old slug from `previous_slugs/0` and migrate the
  tables, the `games` row and the `plugin_states` row (BACON8.md §5). Avoid it: pick the slug carefully.

---

## 4. The smallest plugin: a card, a page, a status

This is the entire hub-side work for a game that has its own client and talks to the hub only through the
games API. Replace `frog_quest` / `FrogQuest` with your slug.

```
plugins/frog_quest/
  README.md
  lib/frog_quest/plugin.ex
  priv/static/card/front-1.webp        your card art (see section 5)
  priv/static/card/card.json
  test/test_helper.exs                 required by mix; may contain just ExUnit.start()
```

`lib/frog_quest/plugin.ex`:

```elixir
defmodule FrogQuest.Plugin do
  use Bacon8.Plugin,
    slug: "frog_quest",
    name: "Frog Quest",
    version: "0.1.0",
    description: "A pond-hopping adventure made with Godot."

  @impl true
  def game do
    %{
      # slug: "frog-quest",           # only if the game slug must differ from the plugin slug
      name: "Frog Quest",
      icon: "🐸",
      description: "Download the game, sign in with your Bacon8 account, and hop.",
      path: "/games/frog_quest",
      kind: "download"                # "browser" if it is played in the browser (see section 10)
    }
  end

  # Optional: shown on the front page. Without it the hub measures your game from its servers' heartbeats
  # and its characters, which is right for a game with dedicated servers.
  # @impl true
  # def game_stats, do: %{online: true, zones: [], current_players: 0}
end
```

`test/test_helper.exs`:

```elixir
ExUnit.start()
```

That is a complete, working plugin. Nothing else is required. Deploy the hub, then in `/admin/plugins`
switch **Frog Quest** on. Activation creates the game's row in the `games` table and your game appears on
`/games`. (Plugins that should be on at first boot are listed in `BACON8_ACTIVE_PLUGINS`.)

What each callback does is in section 7. Everything not overridden has a harmless default.

### Installed vs active

A folder under `plugins/` with a `lib/<slug>/plugin.ex` is **installed** the moment it is compiled in. It does
nothing visible until an admin makes it **active** at `/admin/plugins`. Installed-but-inactive: its API and
pages answer 404, its admin pages redirect, its processes are stopped, but its data is kept and its
`hub_event/1` is still called. Deactivating never deletes data.

---

## 5. The card, and a page for downloads

### The card on `/games`

Pictures and text go in `priv/static/card/`:

```
front-1.webp, front-2.webp ...   the front's pictures, in number order (webp, png, jpg, avif)
back.webp                        the back's picture (optional: the first front, blurred)
card.json                        optional
```

```json
{
  "tagline": "Hop. Dodge. Repeat.",
  "details": "A few sentences about the game.\n\nA blank line starts a new paragraph.",
  "play_label": "Download",
  "seconds": 5
}
```

Admins can change all of it afterwards without a deploy once you put the hub's card editor on your plugin's
admin page (`Bacon8Web.GameCardAdmin`, section 7; the smallest plugin above has no admin page, so add one
with `routes/0` + `admin_nav/0` to get it). Edits are
stored in the `game_cards` table and override the folder field by field; "Reset" goes back to the folder.

Files in `priv/static/` are served at `/plugins/<slug>/...` (pictures, video, fonts and `.json` only; **never
HTML, SVG or scripts**, by design).

### `kind`: how the game is played

- `"browser"`: the card's Play button opens the game's own page (`path`).
- `"download"`: the card's Play button opens **a page you edit**: an ordinary CMS page chosen on the game's
  admin section. Use it for a download page (what it is, a Download button, system requirements, patch
  notes). RaysSpaceSim's is `/pages/rays-space-sim`; the page builder at `/pages/<slug>?edit=1` edits it.

---

## 6. The games API (what your game calls)

Base: `https://<hub>/api/games/<game slug>`. All JSON. Two ways to authenticate:

| Mode | How | Who uses it |
|---|---|---|
| **Player token** | `Authorization: Bearer <token>` from `/api/auth/login` | Your game **client**, for the signed-in player's own data |
| **Server key** | `X-API-Key: <GAMES_SERVER_API_KEY>`, and `user_id` in the request when acting for a player | Your **dedicated server**, running where the operator controls it. **Never ship this in a client.** |

### 6.1 Sign in

```
POST /api/auth/login
{ "email": "name-or-email", "password": "..." }
```

`email` accepts a username too (`username` is also accepted as the key). Success (200):

```json
{ "success": true, "token": "<jwt>", "user": { "id": "...", "email": "...", "name": "...",
  "is_admin": false, "email_verified": true } }
```

Failures: 401 bad credentials, 403 `error_code: "email_not_verified"`, 423 locked after repeated failures,
429 rate limited (the login bucket is small: about 5 attempts per 5 minutes per address; do not retry in a
loop). Other auth routes: `POST /api/auth/register`, `/verify-code` (6-digit email code), `/verify-email`,
`/resend-verification`, `/verify` (validate a token), `/logout`.

Godot 4 example:

```gdscript
extends Node
const HUB := "https://your-hub.example"     # from configuration, not committed
const GAME := "frog-quest"
var token := ""

func login(user: String, password: String) -> bool:
    var http := HTTPRequest.new(); add_child(http)
    var body := JSON.stringify({"email": user, "password": password})
    http.request(HUB + "/api/auth/login", ["Content-Type: application/json"], HTTPClient.METHOD_POST, body)
    var res = await http.request_completed          # [result, code, headers, body]
    http.queue_free()
    if res[1] != 200: return false
    token = JSON.parse_string(res[3].get_string_from_utf8()).token
    return true

func api(method: int, path: String, payload = null) -> Array:
    var http := HTTPRequest.new(); add_child(http)
    var headers := ["Authorization: Bearer " + token, "Content-Type: application/json"]
    http.request(HUB + "/api/games/" + GAME + path, headers, method,
        "" if payload == null else JSON.stringify(payload))
    var res = await http.request_completed
    http.queue_free()
    return [res[1], JSON.parse_string(res[3].get_string_from_utf8())]
```

Keep the token in memory (or the OS keychain); treat it like a password. Always use `https://`.

### 6.2 Characters

A character belongs to one player in one game. The hub stores `stats` and `settings` as JSON maps **you
define**; it does not interpret them. Typical split: `stats` = numbers that change often (level, HP, coins),
`settings` = choices and last-known state (appearance, zone, position).

| Method | Path | Auth |
|---|---|---|
| GET | `/characters` | player (own) or server (+`user_id`) |
| POST | `/characters` | `{ "name": "...", "stats": {...}, "settings": {...} }` |
| GET / PUT / DELETE | `/characters/:id` | PUT takes any of `name`, `stats`, `settings` |
| PUT | `/characters/:id/instance_location` | the server sets `{instance_id, location}`; a player token may only clear it |

Responses wrap the record: `{ "success": true, "character": { "id", "name", "stats", "settings",
"instance_id", "instance_location", "last_played_at", ... } }`.

**Trust.** A player token may `PUT` its own character's `stats` and `settings`. Anything a client can write, a
cheater can write. For values that matter (currency, rank, anything competitive), write them from a
server using the server key, and treat client-written data as untrusted. Otherwise keep authoritative data in
your own plugin tables.

### 6.3 Server registry (for dedicated servers) and status

Your dedicated server registers itself and keeps reporting. **Server key only.**

```
POST /servers/heartbeat        every 20-30 seconds
{ "host": "203.0.113.5", "port": 7777, "name": "Pond EU 1", "region": "eu",
  "status": "online", "current_players": 3, "max_players": 64,
  "map_name": "pond", "version": "0.1.0",
  "roster": { "players": [ { "user_id": "...", "character_id": "...", "name": "...", "joined_at": "..." } ] },
  "metadata": { "dev": true } }
```

- A server not heard from for **90 seconds** counts as offline. A crashed server never deregisters; that is
  what the heartbeat age is for. Send `POST /servers/offline {host, port}` on a clean shutdown.
- `roster` is who is actually on the server. The hub uses it to release the session claims of anyone who left
  without a clean logout, so send it every time.
- `"metadata": {"dev": true}` marks an editor-run development server. Players never see dev servers; an
  admin client asking `GET /servers?dev=1` sees them first.
- The response carries `commands`: instructions an admin queued for the server (`shutdown`, `drain`, `kick`; each has a `payload`). **The
  heartbeat is the only way the hub reaches a running server**, so poll by heartbeating and act on
  `commands`.
- Players list servers with `GET /servers` (optional `region`, `version`, `include_full=true`). Response:
  `{ servers: [...], recommended: {...} }`, each with `address` ("host:port"), `current_players`,
  `max_players`, `region`, `version`, `status`.

### 6.4 Session claims (one live session per character)

When a player joins your server, the **server** claims the character; when they leave it releases.
**Server key only**, because a player who could claim their own character is how someone signs in twice.

```
POST /characters/:id/claim      { "user_id": "...", "host": "203.0.113.5", "port": 7777 }
  200 { success: true, session_id: "...", character: {...} }
  409 { success: false, message: "...", server: {...} }       already in use elsewhere: refuse the join
POST /characters/:id/release    { "user_id": "...", "host": "...", "port": 7777, "session_id": "..." }
```

The server must have heartbeated first (a claim from an unregistered address is a 409). Stale claims free
themselves when the holding server's heartbeat stops or its roster no longer lists the player.

### 6.5 Items and passes the player owns

```
GET /entitlements                         → { success, entitlements: [ { kind, key, quantity, starts_at, ends_at, source } ] }
GET /entitlements/check?kind=K&key=ITEM   → { success, kind, key, active: true|false }
```

A player token reads its own; a server passes `user_id`. A grant with `key: "*"` means "everything of that
kind". Check when the item is **used**, not only at login: timed passes expire and chargebacks revoke.
See section 8 for how an item gets here.

### 6.6 Releases (download games)

If you ship a downloadable client the hub can host it: client builds are stored as SHA-256 manifests over a
content-addressed blob store, with ranged downloads, and a launcher (`/games/<game slug>/launcher`)
installs and self-updates it.

| Method | Path | Auth |
|---|---|---|
| GET | `/releases/latest` | player (the launcher's update check) |
| GET | `/releases/blobs/:sha` | player (supports `Range`) |
| POST | `/releases/missing`, `/releases`, `/releases/:build_id/live` | **server key** (your build pipeline) |

The publishing side is automated by a deploy script (RaysSpaceSim's is
`plugins/rays_space_sim/deploy-game.sh` plus `scripts/publish_client_release.py`, a worked example you can
copy). A launcher is game-specific (RaysSpaceSim's is a small C# program; the hub only serves its executable
at `/games/<game slug>/launcher`). **You do not need releases or a launcher to integrate**: a download page with a
link to wherever you host the build (itch.io, GitHub Releases, your own site) is fully supported.

---

## 7. Everything a plugin can add (the contract)

All callbacks are optional except the four set by `use Bacon8.Plugin` (`slug`, `name`, `version`,
`description`). Override only what you use. Full list with docs: `lib/bacon8/plugin.ex`.

| Callback | Returns | What it does |
|---|---|---|
| `game/0` | `%{name, path, description, icon, slug?, kind?}` or nil | Registers a game: its row, its card on `/games`. Set `kind: "download"` for a CMS download page |
| `routes/0` | a module using `Bacon8.Plugin.Routes` | Your own HTTP routes (below) |
| `children/0` | child specs | Processes supervised while the plugin is active (a GenServer, a poller) |
| `requires/0` | `["chat_channels"]` | Plugins that must be active; the hub refuses to activate without them and to deactivate them under you |
| `mount/0` | `"store"` | Site plugins only: where `site` routes mount (`/store`, `/api/store`) |
| `admin_nav/0` | `[%{label, path, icon}]` | Links in the admin sidebar |
| `admin_dashboard/0` | `%{stats: [...], panels: [...]}` | Cards and lists on `/admin` |
| `admin_tools/0` | action maps | Entries in `/admin/api-toolbox` |
| `nav_links/1`, `profile_tabs/1`, `desktop_apps/1` | link lists | Site navigation, the profile page, the start menu (all take the user, nil when signed out) |
| `entitlement_kinds/0` | `["frog_quest_item"]` | The kinds of items/passes your game grants or checks (section 8) |
| `game_stats/0` | `%{online, zones: [%{name, online, players}], current_players, total_players?}` or nil | Live numbers for the front page; keep it cheap, it is called every few seconds |
| `retains_user_data?/1` | boolean | True if you keep records that must outlive an account (orders, a ledger): the hub then anonymises instead of deleting |
| `storage_refs/0` | blob SHA-256 list | Files you store outside the drive that its garbage collector must keep |
| `raw_body_paths/0` | path prefixes | Paths whose raw request body you need (signed webhooks) |
| `hub_event/1` | `:ok` | Hub events (below) |
| `on_activate/0`, `on_deactivate/0` | `:ok` / `{:error, term}` | Run once when an admin toggles you; may refuse |
| `previous_slugs/0` | slugs | Old slugs whose links redirect (301) after a rename |

### Routes

A routes module declares blocks; the hub compiles them into its router and checks activation per request.

```elixir
defmodule FrogQuestWeb.Routes do
  use Bacon8.Plugin.Routes

  # /api/games/<game slug>/...  Player token or server key (the :games_api pipeline).
  api do
    get "/leaderboard", LeaderboardController, :index
    post "/runs", RunController, :create
  end

  # /games/<plugin slug>/...  Signed-in browser pages (LiveView).
  browser do
    live "/", HomeLive, :index
  end

  # /admin/<plugin slug>/...  Admins only.
  admin do
    live "/", AdminLive, :index
  end
end
```

Then `def routes, do: FrogQuestWeb.Routes` in the plugin. A **site** feature rather than a game uses
`mount/0` plus `site do ... end` (pages at `/<mount>`), `site_api do ... end` (`/api/<mount>`) and
`fixed reason: "...", pipe_through: ... do ... end` (absolute paths an outside party already calls).
Controllers read `params["game_slug"]`. The router refuses at compile time a mount that is a core path or
used twice.

### Data

- Tables go in the **games database** by default: `plugins/<slug>/priv/games_repo/migrations/`. Prefix every
  table with the slug. Use real timestamps for migration versions (they share one table with the hub's).
- Site-database tables (rare) go in `priv/repo/migrations/`.
- A character is a hub `game_characters` row; your tables may reference `game_characters.id`. They cannot
  have a foreign key to `users` (that table is in the other database): store `user_id` as a plain
  `:binary_id` and let your code keep it consistent.
- Run migrations with `mix bacon8.migrate` (development) or let the deploy do it. Plain `mix ecto.migrate`
  only sees the core `priv/`.

### Hub events

`hub_event/1` is called on every installed plugin, active or not, synchronously. **Ignore events you do not
know**; the hub adds more.

| Event | Meaning |
|---|---|
| `{:user_content_removed, user_id}` | The user was banned or deleted: remove what they wrote. Runs inside the account's transaction |
| `{:entitlement_granted, %Entitlement{}}` | A store purchase granted something of a kind you declared |
| `{:entitlement_revoked, %Entitlement{}}` | A timed grant expired or a chargeback took it back. Still check when the item is used |
| `{:channel_updated, new, old}`, `{:channel_deleted, id}`, `{:channel_member_removed, channel_id, user_id}` | From Chat Channels, if you build on channels |

### The card editor on your admin page

```elixir
<.live_component module={Bacon8Web.GameCardAdmin} id="game-card" plugin="frog_quest" current_user={@current_user} />
```

### Front-end hooks (LiveView pages only)

`plugins/<slug>/assets/js/index.ts` exports `export const hooks = {...}`; the build picks it up
automatically. Hook names are global, so make them distinctive. Import shared npm libraries through
`assets/js/vendor/` shims (never directly). A pure API game needs none of this.

### Settings

Read your own environment variables at runtime in a small `Config` module (`System.get_env/1`). The hub's
`config/runtime.exs` does not know about your plugin. Never put secrets in the plugin folder.

---

## 8. Selling things: items, passes, and entitlements

The Bacon Store (`plugins/bacon_store`) sells digital products for a card or for Gems (the hub's currency).
A purchase of an **item** product becomes an **entitlement**: a row `(user, kind, key, quantity, optional
end date)`. Your game reads them with section 6.5.

To sell your game's items:

1. Return your kinds from `entitlement_kinds/0`, for example `["frog_quest_item"]`. Any kind that starts with
   the game's slug is also treated as the game's.
2. In the store admin (`/admin/bacon_store/products`) create an **item** product. Its *grant kind* is one of
   the kinds you declared and its *item id* (`grant_key`) is the item's id in your game, for example
   `top_hat`; `"*"` grants every item of the kind. Set a card and/or Gem price. Or create products from code the way Bacon World does (`BaconWorld.Mounts.ensure_store_products/0`
   creates them switched off, for the owner to publish).
3. In the game, call `/entitlements/check?kind=frog_quest_item&key=top_hat` before honouring the item.
   Optionally react to `{:entitlement_granted, e}` in `hub_event/1` (to push a message to a live server).

Sales are final in this hub (no refunds; disputes and chargebacks are handled by admins, and a chargeback
revokes the entitlement). Prices, Stripe and the ledger are the operator's concern, not yours.

---

## 9. Security model: read before you write code

1. **The server API key (`GAMES_SERVER_API_KEY`) is a master credential.** Its holder can act as *any* user
   in the games API. It belongs only in processes the operator controls (dedicated servers, build pipelines),
   supplied through environment variables or a secret manager. **Never** embed it in a game client, an
   export template, a public repository, a log, or a screenshot. Rotate it if an image leaks. If a friend
   hosts their own servers, the operator should discuss whether to hand over the key at all: it is the key to
   every game on the hub.
2. **Players authenticate; servers vouch.** Anything a server tells the hub about a player (stats, claims) is
   trusted. Anything a client says is not.
3. **A plugin is trusted code.** It compiles into the hub with access to the databases. Review every line
   that will run, as you would a dependency with root access. No plugin may reach into another's tables.
4. **File uploads** from players or your code go through `Bacon8.Drive` / `Bacon8.Content.InlineMedia` and
   `Bacon8.SafePath`; never join a user-supplied name onto a path yourself. HTML, SVG and scripts are never
   served from uploads or plugin static files.
5. **Webhooks and signatures**: declare `raw_body_paths/0` and verify the signature on the raw body.
6. **Rate limits are per IP.** A game behind one NAT shares a budget; back off on 429.
7. **Public repository hygiene**: no hostnames, IPs, keys or cluster details in committed files.

---

## 10. Hosting the game itself

| Your game is... | Do this |
|---|---|
| A **desktop client** (Godot/Unity/Unreal export) | `kind: "download"`. Host the build anywhere (or publish it as a hub release, section 6.6). Put the link on the game's CMS page. The client signs in with `/api/auth/login` |
| A client **plus dedicated servers** | As above, and the servers heartbeat (6.3), claim characters (6.4) and check entitlements (6.5) with the server key. The hub can run servers for you (RaysSpaceSim launches them as Kubernetes jobs from its own plugin code); for most games, run them yourself and register them |
| **Played in the browser** (for example a Godot HTML5 export) | **Not hosted by the hub today.** `kind: "browser"` opens the game's own page, which is a Phoenix page. Plugin static files may not be HTML, JS or WASM, so a Godot web export cannot be served from `priv/static`. Host the export on a static host you control, then give the plugin's `browser` route a LiveView page (or the CMS page) that links or embeds it. If you need first-class hosting, that is a hub feature to add, not something a plugin can work around |
| A **web app / tool** rather than a game | Make it a *site plugin* (`mount/0`, `site do ... end`), or link out from a nav link (`nav_links/1`) and use `/api/auth/verify-bearer` (below) to recognise hub users |

To recognise a hub user from another service: the user signs in at the hub, your service receives their
bearer token, and calls `POST /api/auth/verify-bearer` with `Authorization: Bearer <token>` (or
`/api/auth/verify {token}`); a valid answer is `{success: true, user: {id, email, name, is_admin, email_verified}, claims: {exp, iat, sub}}`.

---

## 11. Testing, installing, deploying

1. **Layout check**: the folder is `plugins/<slug>/` and `lib/<slug>/plugin.ex` defines `<Camelized>.Plugin`.
   A folder that does not meet this is skipped with a warning, not a build failure.
2. **Compile** with warnings as errors, in Docker if you have no local Elixir:

   ```sh
   docker run --rm -v "$PWD:/app" -v bacon8_deps:/app/deps -v bacon8_build:/app/_build -w /app \
     -e MIX_ENV=dev elixir:1.19 \
     sh -c 'mix local.hex --force && mix local.rebar --force && mix deps.get && mix compile --warnings-as-errors'
   ```

   (On Windows Git Bash prefix with `MSYS_NO_PATHCONV=1`.) Plugin tests in `plugins/<slug>/test/` run with
   the hub's `mix test` (it needs only PostgreSQL). Give the folder a `test/test_helper.exs`.
3. **Try the API** before the plugin is even involved: register a test account, `login`, `POST
   /characters`, `GET /servers`. The games API needs the game to exist and be active, so activate the plugin
   first (it creates the game row), or use the slug of a game that already exists.
4. **Commit** the plugin folder. Public hub: ship only plugins you intend to be public (the hub's
   `.gitignore` ignores every plugin folder except the ones it lists). A **private plugin** is its own git
   repository cloned into `plugins/`; the hub's `.dockerignore` already keeps its `.git`, `k3s/` and
   `scripts/` out of images.
5. **Deploy** the hub, then **activate** at `/admin/plugins`. For a plugin that should be on from first boot,
   add its slug to `BACON8_ACTIVE_PLUGINS`.
6. **Verify**: the card shows on `/games`, `GET /api/games/<slug>/servers` answers 200 (empty list is fine),
   and the front page's status corner lists the game.

---

## 12. Checklists

### For an AI agent tailoring a project to this architecture

1. Read sections 1, 3 and 6 of this file, then `lib/bacon8/plugin.ex` and one example plugin
   (`plugins/bacon_world/lib/bacon_world/plugin.ex`).
2. Decide the **plugin slug** and **game slug** (section 3) and state them to the user before writing files.
3. Decide the integration level with the user:
   - *Client only*: write the plugin in section 4 plus client code for sign-in, characters and entitlement
     checks (section 6). No Elixir routes.
   - *Client + dedicated servers*: add server code for heartbeat, roster, claim/release (6.3, 6.4), using
     the server key from the environment.
   - *Hub-side features* (leaderboards, an admin screen, a custom API, your own tables): add `routes/0`,
     migrations in `priv/games_repo/migrations/`, and contexts in your own namespace (section 7).
4. Put game-side code in the **game's repository**; put hub-side code only under `plugins/<slug>/`. Do not
   edit hub core files (`lib/`, `config/`, `mix.exs`) to add a game: if something seems to require it, the
   plugin contract is missing a hook; say so instead.
5. Never write the server key into any file that is committed or shipped to players.
6. Compile with `--warnings-as-errors` and run the tests (section 11). Report what you ran and what you did
   not.
7. Record decisions in the plugin's `README.md`: what it adds, its slug, its tables, its env variables, how
   to enable it.

### For the operator

- [ ] Read the plugin's code (section 9, point 3).
- [ ] Add the folder under `plugins/`, compile, run the hub's tests.
- [ ] Deploy, then activate at `/admin/plugins`.
- [ ] Give the game developer the base URL; give the **server key** only to servers you control.
- [ ] Create store products for any items (section 8) and publish them.
- [ ] Edit the card and the download page (`/admin/<slug>`, `/pages/<slug>?edit=1`).

### Common mistakes

- Slug with a hyphen or capital in the plugin slug (only the **game** slug may contain hyphens).
- Forgetting `test/test_helper.exs`: `mix test` fails for the whole hub.
- Putting the server key in a Godot project, an export preset or a `project.godot`.
- Calling `heartbeat` without `host`/`port`, or `claim` before the first heartbeat (409).
- Trusting `stats` a client wrote.
- Checking an entitlement only at login.
- Expecting the hub to serve an HTML5 export (section 10).
- Naming a table without the slug prefix, or adding a foreign key to `users`.
- Matching a `hub_event/1` event exhaustively: unknown events must fall through to `:ok`.
- Editing the hub's core to special-case one game.

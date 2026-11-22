Moved word for word from BACON8.md (§9) on 2026-11-19; BACON8.md keeps a short summary and links here.

## 9. Games platform and plugins

### Core (stays in the hub)

| Module | Purpose |
|---|---|
| `Games.Game` | registered titles (`slug`) |
| `Games.GameCharacter` | per-user characters; game-specific data in the `stats` / `settings` JSON columns |
| `Games.GameServer`, heartbeat API | dedicated-server registry; servers write their own rows. `instance_id` set = an instance server (running one game-defined instance, e.g. a player world); nil = a world server, the only kind listed to players |
| `Games.ServerCommand` | instructions queued for a server, delivered on its next heartbeat |
| `Games.AdminAction` | audit trail of privileged actions on live game state |
| `Games.GameRelease`, `Games.Releases` | client builds as SHA-256 manifests over a content-addressed blob store; launcher self-update; ranged downloads |
| `Games` session claims | one live session per character (`claim` / `release`, server key) |
| `GameCharacter.instance_id` / `instance_location` | resume-in-instance: where to put a character on next login, opaque to the hub |
| launcher download controller | `/games/:game_slug/launcher`; filename from the manifest's `launcher.filename` or the game's name |
| items and passes (2026-10-29) | `GET /api/games/:game_slug/entitlements`: the player's active entitlements in that game (the kinds its plugin declares in `entitlement_kinds/0`, or named after its slug, like `bacon_world_mount`); `.../entitlements/check?kind=&key=` answers `{active}`. A player token reads its own; the server key passes `user_id` |

### Moved to the game's own plugin (2026-10-16)

Into the private `plugins/rays_space_sim` (namespace `RaysSpaceSim` / `RaysSpaceSimWeb`):
Holo-sims (`HoloSim*`, `SimAccess`, the controller and its `/holosims` routes, paths
unchanged), `InstanceLauncher`, `WorldServerLauncher` (a candidate to generalise back into
core later), the Kubernetes client, `CodeMap` and the codebase page, the game's admin
section (now `/admin/rays_space_sim`), the launcher card (now its page
`/games/rays_space_sim`), `mix rss.dev_users`, the deploy/build scripts, the k8s manifests
and namespace secret, the `HOLOSIM_*` / `WORLD_*` settings (read by `RaysSpaceSim.Config`;
the values still sit in the prod configmap), and the `holo_sims*` tables (now the plugin's
baseline migration). The plugin owns the foreign keys
from the hub's `instance_id` columns to `holo_sims`. Chat channels are Holo-sims' access
lists (the plugin `requires/0` `chat_channels`); the plugin follows channel changes through `hub_event/1`.

The hub's games baseline (`20260809100000_games_baseline`) creates `instance_id` /
`instance_location` with no foreign keys, so a fresh install without the plugin works; the
plugin's baseline (`20260811090000_rays_space_sim_baseline`) creates `holo_sims*` and adds
the foreign keys. No game row is seeded; each plugin registers its own.

### Plugins (milestone 2, implemented 2026-10-15)

A plugin is a folder, the way WordPress plugins are:

```
plugins/
  bacon_world/                       folder name = slug = game slug = table prefix
    README.md                        what it is, how to enable it
    lib/bacon_world/plugin.ex        BaconWorld.Plugin - implements Bacon8.Plugin
    lib/bacon_world/...              contexts and schemas      (namespace: BaconWorld)
    lib/bacon_world_web/...          LiveViews, controllers    (namespace: BaconWorldWeb)
    lib/bacon_world_web/routes.ex    BaconWorldWeb.Routes - api + browser routes
    priv/games_repo/migrations/      tables prefixed bacon_world_
    priv/repo/migrations/            (optional) site-DB tables
    assets/js/index.ts               `export const hooks = {...}` (LiveView hooks)
    test/                            run with the core suite
```

**Conventions** (what makes a plugin a template other people can copy):

- One top-level namespace per plugin (`BaconWorld`, `BaconWorldWeb`), never `Bacon8.*`.
- The folder name is the slug: lowercase letters, digits, underscores. It names the main
  module (`bacon_world` -> `BaconWorld.Plugin`), prefixes every table the plugin owns
  (`bacon_world_zones`), and is the game slug unless `game/0` returns its own `:slug`.
- A plugin uses the hub only through public context functions (`Bacon8.Games`,
  `Bacon8.Drive`, `Bacon8.Entitlements`, ...). Core never references a plugin module.
- Characters are platform `GameCharacter`s. Plugin tables may reference
  `game_characters.id` (same database).

**Installed vs active.** Every folder under `plugins/` whose name is a slug and that has
`lib/<slug>/plugin.ex` is *installed* (anything else, like an empty or half-finished clone,
is skipped with a warning on stderr rather than breaking the build): `mix.exs` adds
`plugins/*/lib` to the compile paths and `plugins/*/test` to the test paths, all its
routes are compiled into the router, and its migrations run (`Bacon8.Release.migrate/0`
in production, `mix bacon8.migrate` in development; plain `mix ecto.migrate` only sees
`priv/`). A release step in `mix.exs` copies each plugin's `priv/` into the release.

A plugin is *active* when an admin activates it on **/admin/plugins** (implemented
2026-10-15). Each toggle is saved as a row in `plugin_states` (slug, active, who, when); a
plugin that has never been toggled is active if its slug is in
`config :bacon8, :default_active_plugins` (`["bacon_world"]`, or the `BACON8_ACTIVE_PLUGINS`
environment variable when set). Deliberately not stored in
`cms_options` (see §13).

| While a plugin is... | Installed only | Active |
|---|---|---|
| its API (`/api/games/<game slug>/...`) | 404 (`Bacon8Web.Plugs.PluginActive`) | served |
| its pages (`/games/<slug>/...`) | 404; open pages redirect to `/games` (`Bacon8Web.PluginGate`) | served |
| its admin pages (`/admin/<slug>/...`) | 404; open pages redirect to `/admin/plugins` | served, admins only |
| `hub_event/1` | **still called** (its data must stay consistent) | called |
| its `children/0` | stopped | supervised under `Bacon8.PluginSupervisor` |
| its game row | `is_active: false` | registered, `is_active: true` |
| admin nav, desktop apps, games list | hidden | shown |
| its tables and data | kept | kept |

Each node caches the active set in `:persistent_term`. `Bacon8.Plugins.activate/2` and
`deactivate/2` run the plugin's `on_activate/0` / `on_deactivate/0` hook (which may refuse),
save the list, and broadcast on `bacon8:plugins`; `Bacon8.Plugins.Runtime` on every node
refreshes its cache and starts or stops the plugin's processes.

**The behaviour:**

```elixir
defmodule Bacon8.Plugin do
  @callback slug() :: String.t()                       # "bacon_world"
  @callback name() :: String.t()
  @callback version() :: String.t()
  @callback description() :: String.t()
  @callback game() :: %{name: String.t(), path: String.t(), description: String.t(), icon: String.t()} | nil
  @callback routes() :: module() | nil                 # e.g. BaconWorldWeb.Routes
  @callback previous_slugs() :: [String.t()]           # slugs before a rename; old links 301
  @callback mount() :: String.t() | nil                # site plugins: "store" -> /store, /api/store
  @callback requires() :: [String.t()]                 # plugin slugs this one needs
  @callback children() :: [Supervisor.child_spec()]    # under Bacon8.PluginSupervisor
  @callback admin_nav() :: [%{label: String.t(), path: String.t(), icon: String.t()}]
  @callback desktop_apps(user) :: [%{label, path, icon}]  # §10; start-menu apps for this user (2026-10-27)
  @callback entitlement_kinds() :: [String.t()]           # §8
  @callback game_stats() :: map() | nil                   # "Game status" below (2026-10-29)
  @callback on_activate() :: :ok | {:error, term()}
  @callback on_deactivate() :: :ok
  @callback hub_event(tuple()) :: :ok                     # see "Hub events"
  # Hooks (see "Site plugins" below): retains_user_data?/1, storage_refs/0,
  # raw_body_paths/0, nav_links/1, profile_tabs/1, admin_tools/0, admin_dashboard/0
end
```

`use Bacon8.Plugin, slug: "bacon_world", name: ..., version: ...` fills in the required
callbacks and defaults the rest, so a plugin overrides only what it uses.

**Routes.** Phoenix routes are compiled and LiveView expects one router, so a plugin's
routes module (`use Bacon8.Plugin.Routes`) declares `api`, `browser` and `admin`
blocks, and `Bacon8Web.PluginRouter` expands them for every *installed* plugin at compile
time. Activation is checked per request, so it never needs a recompile:

- API routes mount at `/api/games/<game slug>/...` with the `:games_api` pipeline (player
  bearer token or server key) plus the plugin's gate. The literal-slug scopes are expanded *before* the core
  `/api/games/:game_slug` routes, so the dynamic segment cannot capture them. The gate sets
  `params["game_slug"]` as the core routes do, so controllers work under either.
- Browser routes mount at `/games/<plugin slug>/...` in a `live_session` of their own
  (`UserAuth` + `PluginGate` on mount). Navigating between a plugin page and a core page is
  a full page load.
- Admin routes mount at `/admin/<plugin slug>/...` in their own `live_session` with
  `UserAuth :require_admin_user`; link them from `admin_nav/0`.

- **Renamed plugins.** For each slug in `previous_slugs/0`, `/games/<old>/...` and
  `/admin/<old>/...` answer **301** to the same path under the current slug, query string
  kept (`Bacon8Web.PluginRedirectController`). They don't check activation; the page they
  lead to does. Renaming the plugin's stored names (tables, game row, `plugin_states`) is
  the plugin's own migrations' job (§5); Bacon World's are the example.

**Site plugins** (implemented 2026-10-21, ADR 0001 phase 2). A plugin that is a site
feature rather than a game returns `mount/0` (e.g. "store") and declares:

- `site do ... end`: pages at `/<mount>/...`. With `:browser` (the default) they get a
  `live_session` of their own (`UserAuth` + `PluginGate`, the app layout, no game
  background); `site pipe_through: :drive_files do ... end` and the like give a plain
  scope. Several `site` blocks may be declared, one per pipeline.
- `site_api do ... end`: `/api/<mount>/...`, `:api` unless `pipe_through:` says otherwise
  (the store uses `:webhooks`: no session, no rate limit).
- `fixed reason: "...", pipe_through: ... do ... end`: absolute paths, for a URL an
  outside party already uses. The reason is required, so it's clear when it can go.

All three sit behind the plugin's gate (404 while inactive). The router refuses at
compile time a mount that is a core path, used by two plugins, or missing while site
routes exist.

**Requirements.** `requires/0` lists plugin slugs. `activate/2` refuses while one is
inactive (`{:error, {:requires, slugs}}`), `deactivate/2` refuses to turn off a plugin an
active one requires (`{:error, {:required_by, slugs}}`), and a plugin switched on by
default or by a saved row is left inactive while its requirements aren't met.
`/admin/plugins` shows requirements and mounts.

**Hooks** that replace core's direct calls into a plugin:

| Hook | Asked of | Used by |
|---|---|---|
| `retains_user_data?(user_id)` | every installed plugin; a crash counts as yes | `Accounts.delete_user/1`: anonymise instead of delete |
| `storage_refs()` | every installed plugin; a crash means delete nothing | `Drive.gc_blobs/2` keeps those blobs |
| `raw_body_paths()` | every installed plugin | `Bacon8Web.RawBodyReader` |
| `nav_links(user)` | active plugins | site navigation, taskbar |
| `profile_tabs(user)` | active plugins | `/profile` |
| `admin_tools()` | active plugins | `/admin/api-toolbox` |
| `admin_dashboard()` | active plugins | `/admin` cards and panels |

Data hooks ask installed plugins because an inactive plugin's data still exists; a plugin
that raises gets the safe answer and the error is logged (`Bacon8.Plugins`). Display hooks
skip a plugin that raises.

Adding or removing a plugin *folder* recompiles the router (it has a `__mix_recompile__?`
guard); activating or deactivating never does.

**Assets.** Before every JS build (npm `pre*` scripts), `assets/scripts/gen-plugin-hooks.js`
writes `assets/js/plugins.generated.ts` (gitignored): one import per
`plugins/*/assets/js/index.ts`, merged into `PluginHooks`, which `app.ts` hands to the
LiveSocket. Hook names are global, so pick ones unlikely to clash. Plugin files sit outside
`assets/`, where esbuild can't find `node_modules`, so they import shared libraries through
re-export shims in `assets/js/vendor/` (`three.ts`, `three-loaders.ts`), e.g.
`import * as THREE from "../../../../assets/js/vendor/three"`. A plugin needing another npm
package adds a shim there and the package to `assets/package.json`. The Dockerfiles copy
`plugins/` before building assets and compiling.

**Pages.** Plugin pages render in the app layout. The root layout gives them (and `/games`) a
plain black background instead of the user's animated one, keyed on the `:bacon8_plugin`
conn assign set by `PluginActive`.

**Hub events.** `Bacon8.Plugins.notify/1` calls `hub_event/1` on every installed plugin,
synchronously, in the caller's process; a plugin that raises is logged and skipped. Events
so far: from Chat Channels, `{:channel_updated, new, old}`, `{:channel_deleted, id}`
(before the channel's rows go, outside its transaction) and `{:channel_member_removed,
channel_id, user_id}` (kick or ban); from the hub, `{:user_content_removed, user_id}` (an
account was banned or deleted: remove what it wrote, inside the account's transaction).
Plugins must ignore events they don't know.

**Files and settings.** `Bacon8.Plugins.priv_dir/1` finds a plugin's `priv/` in a release
or the source tree. A plugin reads its own environment variables at runtime; the hub's
`config/runtime.exs` doesn't know it (the store's Stripe settings are the example). App
config keyed by a plugin module (`config :bacon8, BaconStore.Payments, ...`) is fine for
development and tests: it names an atom, so core still compiles without the plugin.

**Private plugins in deploys.** `.dockerignore` keeps every plugin's `.git`, `k3s/`,
`scripts/` and `*.sh` out of images. `deploy-prod.sh` applies each `plugins/*/k3s` (with a
`kustomization.yaml`) and then any `*secrets.yaml` beside it.

**A plugin's own files and its game card (2026-10-24).** `plugins/<slug>/priv/static/` is
served at `/plugins/<slug>/...` (`Bacon8Web.Plugs.PluginStatic`: installed plugins only; pictures,
video, `.woff2` and `.json`, never HTML, SVG or scripts). A game's card on /games is a literal
card with a front and a back (`Bacon8Web.Components.GameCard`, the `GameCard` hook, `game_card.css`):
the front cycles through pictures under the name and tagline; hovering turns it over with a glassy
shine to the back (a picture, the details, a Play button); on touch screens a tap turns it.
The plugin ships it in `priv/static/card/`:

```
priv/static/card/
  front-1.webp, front-2.webp ...   the front's pictures, in number order (webp, png, jpg, avif)
  back.webp                        the back's picture (optional: the first front, blurred)
  card.json                        optional: {"tagline", "details" (blank line = new paragraph),
                                   "play_label" (default "Play"), "seconds" (per picture, 2-60)}
```

An admin changes it on the plugin's admin page, which embeds the hub's section
`<.live_component module={Bacon8Web.GameCardAdmin} id="game-card" plugin="<slug>" current_user={@current_user} />`
(preview, add/reorder/remove pictures, back picture, texts, and since 2026-10-29 **how it's played**: in the
browser, or a download with **the game's page**, a CMS page its Play button opens; the plugin's `game/0` may say
`kind: "download"`, card.json `"kind"`/`"page"`). `Bacon8.GameCards` keeps the change in
`game_cards` (one row per plugin, overriding the folder field by field) and uploads in
`uploads/public/game_cards/<slug>/` (files no saved card uses are deleted on save); "Reset" goes
back to the folder. /games updates live. Bacon World's section is on `/admin/bacon_world`,
RaysSpaceSim's on `/admin/rays_space_sim/card`.

**Game status (2026-10-29).** The front page's lower-left corner (`Bacon8Web.Components.GameTicker`, styles
`assets/css/game_ticker.css`, hook `assets/js/game_ticker.ts`) shows every active game in turn: the card's first
picture small and alone (it links where Play goes), the name, Online/Offline, up to three zones or servers with who
is in each, "N playing now" and "N players". It turns every 6 seconds, pauses under the pointer, keeps its place when
the numbers refresh, and can be hidden for the visit (sessionStorage). Compact on phones (no zone list).
`Bacon8.GameStatus.snapshot/1` builds the list: a plugin's `game_stats/0` when it returns one
(`%{online:, zones: [%{name:, online:, players:}], current_players:}`, optionally `total_players`), otherwise the
hub's records: world servers with a fresh heartbeat are the zones (editor-run dev shards left out), running instances
add up to one line ("Holo-sims (N)"). `total_players` is the accounts with a character in the game. Cached 15 s in an
ETS table the `Bacon8.GameStatus` process owns (the caller computes, so a crowd costs one computation per 15 s);
`HomeLive` refreshes on a 15 s timer. A crashing plugin or a database blip gives that game "Offline" rather than
taking the page down. Bacon World's `game_stats/0`: each `bacon_world_zones` row, `map_size` of Presence on
`bacon_world:zone:<id>`, up while its creatures' zone process runs (zones without creatures are served by the hub).

**Game rows.** `activate/2` registers a plugin's `games` row; `Bacon8.Plugins.ensure_game/1`
creates it on demand for plugins active by default that were never toggled (plugins call it to
get their game id, and `Plugins.Runtime` calls it at boot).

**Status:** framework and admin page done 2026-10-15; site plugins, requirements and hooks
2026-10-21. Bacon World and Bacon Store are the two shipped plugins. Tests: the fixture plugin
(`test/support/fixture_plugin.ex`) and Bacon World's own `plugins/bacon_world/test`. Each plugin
test folder needs a `test_helper.exs` (mix requires one per test path; it can be empty).

**Done means:** Bacon World runs entirely as `plugins/bacon_world` with no references to it in
core (met), and a second plugin can be added by dropping in a folder, deploying and
activating it.

### Bacon World (the template plugin)

The game's own notebook is **`BACON_WORLD.md`**: its state, the owner's decisions (no
classes, mouse-button hands, EverQuest looting, CC0-only art), how the humans are built and
drawn, and what's next. Its module reference is `plugins/bacon_world/README.md`. What
matters at the hub level:

- **Renamed 2026-10-21** from Web Lobby (`web_lobby`; ADR 0001, phase 1). Its migrations
  renamed the tables, the game row and the `plugin_states` row. `/games/web_lobby/...`
  answers 301 to `/games/bacon_world/...` (`previous_slugs/0`). Its first migration keeps
  the old name (invariant 14).
- **Data.** Characters are platform `game_characters` of game `bacon_world`:
  - `stats` holds HP, MP, PvP, level, experience, skill points and coins;
  - `settings` holds the model, zone, last position and `appearance`.

  Single-key writes merge in SQL (`jsonb ||`), so a position save can't overwrite HP that
  another player's hit just changed. Its own tables are `bacon_world_zones`,
  `bacon_world_spells`, `bacon_world_character_spells` and `bacon_world_items` (games DB).

  The pre-plugin Lobby tables in the site DB were dropped without migrating (decisions log).
- **Processes.** Its first `children/0`: one creature zone process for the cluster
  (`BaconWorld.Mobs.Zone`, `:global`), and a `Keeper` on every node.
- **Topics.** PubSub and Presence topics are prefixed `bacon_world:`.
- **Models.** These are the Bacon8 humans (`Humans/Male.glb`, `Female.glb` with
  manifests, and `Humans/Wardrobe/` design textures and item icons), animation packs, hair, weapons, the skeleton creature and the village kit.

  They live on the models volume, not in git, and are built in the game repository
  (`art/pipeline/scripts`). The humans' manifests are `.json`, which `/models` refuses
  (invariant 17), so the LiveView passes them in `data-human-assets`.

  Model URLs carry a version (`?vsn=`, from size and mtime), and `/models` serves
  `.glb.gz` copies when present (`gzip: true`).

### Tears of Babylon (was Artillery) and City Planner (2026-11-03/04)

Two games started for the owner ("Godot game for a tank game"; "Unity for a City Builder sim that can take scan
in hand-drawn architectural diagrams and create the buildings in 3d and vr space"). Both are download games on
the games API (`/api/auth/login`, a bearer token, their own `/api/games/<slug>/...`), with the engine project
inside the plugin, private by default (decisions log, 2026-11-03). Each plugin's README is its notebook.

| | `tears_of_babylon` (was `artillery`) | `city_builder` (was `city_planner`, 2026-11-21) |
|---|---|---|
| Engine | ~~Godot 4.6.2, GDScript, Compatibility renderer, everything built in code~~ Being rebuilt (2026-11-07): Godot 4.7.2, Forward+, GDScript, scenes and Blender/CC0 art (`TEARS_OF_BABYLON.md`) | Unity 6.3 LTS, C#, built-in modules only; VR through `UnityEngine.XR` (OpenXR) |
| The game | ~~survive waves of light, medium and heavy tanks~~ (2026-11-07) futuristic punk soldiers against every kind of creature, in third person, on foot and in tanks and helicopters; a co-op campaign and player-hosted PvP arenas | a city of 10 m tiles that grows; hand-drawn floor plans scanned into buildings to place and walk through |
| Hub side | matches scored by the hub from what happened (`TearsOfBabylon.Rules`), a leaderboard, admin removal (to be redone for the new game) | drawings (photos from a phone, stored as drive files), scanned plans, saved cities |
| Tested | 39 headless Godot checks (rules shared with the hub's tests, simulated matches) + 5 hub tests | 128 .NET checks of the scanner, mesher and city (12 synthetic hand drawings) + 4 hub tests; **the Unity scripts are not yet compiled** |

### Shared physics: box3d in every game (plan, 2026-11-14)
One engine: box3d (Erin Catto, MIT). Its one source is the copy pinned in RaysSpaceSim
(`Plugins/Box3DPhysics/Source/Box3D`, v0.1.0); the others build from it. The owner's choices (2026-11-13):
- **RaysSpaceSim:** box3d already runs there, beside Chaos (bodies, kinematic pushers, mirrored level
  statics, Mass crowds). Unreal can't drop Chaos (character movement and traces are built on it), so it stays.
- **Bacon World:** physics in each browser: box3d built to WebAssembly (`native/box3d`,
  `assets/js/physics/box3d.ts`; BACON_WORLD.md). In order: explosion forces, then smashed builds' debris as
  bodies, then ragdolls; loose props later. Explosion forces and debris are in (2026-11-14,
  `physics/physics-world.ts`; needs the deploy); ragdolls are next.
- **Tears of Babylon:** box3d beside Jolt, as in RaysSpaceSim (owner, 2026-11-13, changed from replacing
  it): a GDExtension running a box3d world for explosion forces, debris and ragdolls, with the level's
  static collision mirrored into it; Jolt keeps character movement, triggers and queries.
  Not started: it needs a Windows build of the extension.

Ragdolls (2026-11-14, the owner: "Dead characters should ragdoll, unless the character has been
killed by something that has damaged them, in a single hit, for more than their total hp... that is
the shatter event"): Bacon World on box3d (`physics/ragdoll.ts`), Tears of Babylon on Jolt
(`scripts/fx/ragdoll.gd`) until box3d is beside it, RaysSpaceSim on its box3d plugin (to do).

### Shared building: one hub service (2026-11-14)
The owner: RaysSpaceSim's own build system goes, and it and Tears of Babylon get Bacon World's ("`"
button and all), on one hub service with Bacon World's catalogue.
- **`Bacon8.Building`** (`lib/bacon8/building.ex`): placements by game slug, zone and `frame` (a
  RaysSpaceSim planet, so a base rides its orbit; old RaysSpaceSim pieces are dropped), who may place
  what (Bacon World's roles), hit points and smashing, PubSub per zone and a zone revision for
  polling. **The catalogue** is `Bacon8.Building.Catalogue` (Bacon World's 254 props and kit pieces,
  moved here); Bacon World adds its creature spawns and NPCs. One set of asset rules for every game.
- **Tables** (games_repo, `20261115000000_create_game_building`): `game_placements` and
  `game_asset_rules` are Bacon World's two tables renamed (`game_slug` added, default
  `bacon_world`, and `frame`); `bacon_world_placements` and `bacon_world_asset_rules` stay as views of
  them, so Bacon World's code is unchanged. A later Bacon World migration must alter the
  `game_` tables, not the views.
- **API** (`Bacon8Web.Api.BuildingController`): `/api/games/:slug/build/catalogue`, `zones/:zone`
  (GET `?frame=&rev=`, POST), `zones/:zone/:id` (PUT, DELETE `?smash=true`), `zones/:zone/:id/damage`,
  `rules/:asset`. As the player (token) or a game server with `user_id`. Bacon World's zones aren't
  written through it (it builds in game).
- Tests: `test/bacon8/building_test.exs`, `test/bacon8_web/controllers/building_api_test.exs`;
  `tools\win\build_test.cmd` runs them with Bacon World's building tests in Docker.
- **Tears of Babylon**: `scripts/world/build_mode.gd`. **RaysSpaceSim**: `Source/RSS/B8/B8Build*` (RAYSSPACESIM.md
  7c; built 2026-11-15, the old Cosmos build system removed). Both need the hub deployed with this service.

**2026-11-15:** Bacon World's knees and elbows are hinges (`bw_joint_hinge`: box3d's revolute joint, added to
`native/box3d/bw_box3d.c`; `box3d.wasm` rebuilt in the wasi-sdk image, `tools/win/cc_wasm.cmd`), and its placed
pieces are static boxes in the physics world, so debris and bodies stop at walls and lie on floors
(BACON_WORLD.md). Tears of Babylon's weapons damage placed pieces through `Bacon8.Building`
(`BuildMode.hit`). Next there: loose props; box3d beside Jolt in Godot is still not started.

### Shared content: one hub service (2026-11-15)
The owner: "Move camps, loot and item definitions to the hub, as you did with building. Tears of Babylon's
stated next step (zones in the database and /admin) and the loot step after it are the same problem Bacon
World's Studio already solved."
- **`Bacon8.GameContent`** (`lib/bacon8/game_content.ex`): a game's definitions, a row each: a game slug, a
  `kind` (`"zone"`, `"camp"`, `"camp_template"`, `"monster"`, `"loot_table"`, `"item"`, `"merchant"`, `"event"`,
  or any other), an `id` and its `data` (JSON the game gives meaning to). Read from a cache per game and kind
  (`:persistent_term`, cleared on every node by a change) with a `revision/2` that changes whenever the kind
  does. Changed by staff (`staff?/1`: admins and GMs) with `put/5` and `delete/4`; every change is kept
  (`history/2`) and undone with `undo/3`, a deletion too, and is in the audit log. A plugin fills its kinds
  from a seed with `seed/4` (only a kind that is still empty, unless `missing: true`).
- **`Bacon8.GameContent.Loot`**: Bacon World's loot roller for every game, over the tables as stored (rolls,
  an empty weight, a weighted pool with quantities and level bands, always-drops with a chance, nested tables
  four deep, coins times the level; chance and coin multipliers; `simulate/5`).
- **Tables** (games_repo, `20261115100000_create_game_content`): `game_defs` is Bacon World's
  `bacon_world_defs` renamed, with `game_slug` (default `bacon_world`) now part of its key;
  `bacon_world_defs` stays as a view of that game's rows for a pod of the old code still serving during the
  deploy. `game_content_history` is new. A later Bacon World migration must alter `game_defs`, not the view.
- **Bacon World** reads and writes the same rows through `BaconWorld.Defs` as before (now scoped by
  `game_slug`; it tells the hub's cache when it writes), and its Studio is still where they are edited: the
  hub serves them read-only (`GameContent.read_only?/1`). **Not moved yet:** its items
  (`bacon_world_item_defs`, icons), the Studio's own history, and the Studio's pages (items, loot, monsters,
  camps: about 2,200 lines of LiveView tied to Bacon World's models and skills). They move when a second game
  needs forms and previews rather than JSON; the data layer they would move onto is this one.
- **API** (`Bacon8Web.Api.ContentController`): `/api/games/:slug/content` (the kinds), `/content/:kind`
  (`?rev=n` answers `unchanged`; any other parameter filters on the data's top level, e.g. `?zone=`),
  `/content/:kind/:id` (GET; PUT and DELETE for staff), `/content/loot_table/:id/roll` (a game server with
  the server key, or staff trying a table; never a player's own client), `/content/history` and
  `/content/history/:change/undo` (staff). As the player (token) or a game server (`X-API-Key`, with
  `user_id` to act for a staff member).
- **`/admin/content`** (`AdminLive.GameContent`; "Game content" in the admin sidebar): pick a game, a kind and
  a definition; its data as JSON; Save, Delete, New, and History with Undo. Plain on purpose, the same for
  every game.
- **Tears of Babylon** (its step 5): `TearsOfBabylon.Content` seeds its five zones, 45 camps, two creature
  types and three loot tables from `priv/seed/content.json` (`tools/export_content.py` writes it from the
  level scenes) when the plugin starts; `/admin/tears_of_babylon` links each kind; the game asks for a zone's
  camps as it loads (`scripts/world/zone_content.gd`) and changes, adds or retires camps to match
  (TEARS_OF_BABYLON.md). **RaysSpaceSim** has the same service at `/api/games/rays-space-sim/content` and
  uses none of it yet.
- Tests: `test/bacon8/game_content_test.exs`, `test/bacon8_web/controllers/content_api_test.exs`,
  `plugins/tears_of_babylon/test/tears_of_babylon/content_test.exs`.

The hub's part (2026-11-14): `PluginStatic` serves `.wasm` (Bacon World's module) and `ModelsGuard` lets
`.json` under `/models` through (the shared springs' `Humans/b8_jiggle.json`); a test for the second.


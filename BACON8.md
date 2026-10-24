# BACON8.md: engineering context for the Bacon8 hub

**What this file is.** The working reference for anyone changing this repository:
maintainers, contributors and AI coding assistants. It describes how the hub is built,
the decisions behind it, the rules that break things silently when violated, and the
roadmap. `README.md` is the front door (what Bacon8 is, how to run it). This file is
what you read before changing it.

**Rules for editing this file**

- It is public. No hostnames, IPs, credentials, cluster names or anything specific to
  one deployment. Operator notes for a particular install belong outside the repo.
- Keep facts measured and dated. "Changed 2026-10-15" is more useful than "recently".
- When a decision is reversed, strike it through in the decisions log, add the new one,
  and say why. Do not silently rewrite history.
- Code that games built on Bacon8 need does not belong here. Each game keeps its own
  notes in its own repo.

Last substantive update: **2026-10-24**.

- Bacon World: the male rebuilt on MakeHuman like the female (body, wardrobe, sliders, hair,
  animation packs); player names blue, red with PvP on. Then his posture (lower back and
  shoulders), the skeleton creatures rebuilt on his rig, and one-handed axe and hammer heads
  facing the way they swing; then his hands, his lean, the torch arm and a narrower shoulder
  slider. Details in **`BACON_WORLD.md`** §2.
- §14 now lists the assistant tooling: the Unreal, Blender and Docker MCP servers on the
  development PC and what each is for.

On 2026-10-23:

- Bacon World: underwear and clothes became items (cloth armour), the first NPC merchant,
  EverQuest coins, the female v3, PvP melee and multiplayer animation fixes; Throw Stone is
  gone. Then Black Desert-style body sliders, posture, hands and dagger grips, R to interact.
  Details in **`BACON_WORLD.md`** §2.

Before that:

- **2026-10-22**: Bacon World got its own notebook, **`BACON_WORLD.md`** (state, the owner's
  decisions, next steps); §9 here keeps only the plugin-level summary. The female human was
  rebuilt on MakeHuman's CC0 assets.

- **2026-10-21**: the store became the **Bacon Store** plugin (ADR 0001 phases 2 and 3; §8,
  §9), and Web Lobby was renamed **Bacon World** (phase 1).
- **2026-10-20**: the move to Bacon8 finished; brand assets now come from `brand/`.

---

## Contents

1. [What Bacon8 is](#1-what-bacon8-is)
2. [Decisions log](#2-decisions-log)
3. [Architecture](#3-architecture)
4. [Repository layout](#4-repository-layout)
5. [Naming: code names vs stored names](#5-naming-code-names-vs-stored-names)
6. [Invariants: break these and something fails silently](#6-invariants)
7. [Subsystem: user storage and the file explorer](#7-user-storage-and-the-file-explorer)
8. [Subsystem: store, payments, currency and entitlements](#8-store-payments-currency-and-entitlements)
9. [Subsystem: games platform and plugins](#9-games-platform-and-plugins)
10. [Subsystem: desktop shell and start menu](#10-desktop-shell-and-start-menu)
11. [Subsystem: chat channels and VIP channels](#11-chat-channels-and-vip-channels)
12. [Roadmap](#12-roadmap)
13. [Known debt](#13-known-debt)
14. [Development workflow](#14-development-workflow)

---

## 1. What Bacon8 is

A self-hostable Phoenix/LiveView server for running an online community around games:

- accounts, authentication and account security
- real-time chat channels with presence
- a windowed "desktop" UI shell
- user file storage
- a storefront with a hub-wide virtual currency, subscriptions and two payment providers
- a **games platform**: a backend that game clients and dedicated servers talk to
  (accounts, characters, server registry, client release distribution with a
  self-updating launcher)

Games plug into the hub as **plugins** (§9), WordPress-style. The repository ships one, **Bacon World**: a
small in-browser 3D multiplayer arcade that serves as both the demo and the reference
implementation of the plugin API. Larger games live in their own repositories and
depend on the hub; nothing in this repo may depend on them.

It is a monolith you fork and keep, not a generator. Subsystems are separated so that a
fork can delete the ones it doesn't want; `README.md` lists what removing each costs.

### What it is not

- Not a game engine. Game clients and servers are separate programs that use the hub's
  HTTP API.
- Not multi-tenant. One deployment is one community.

---

## 2. Decisions log

| Date | Decision | Why |
|---|---|---|
| 2026-10-15 | ~~Rebrand of the code (modules, OTP app, display name) to the project's previous working name.~~ Superseded 2026-10-17 (below). | The repo was being prepared for open source under its real name. |
| 2026-10-15 | ~~**Code renamed now; stored names (DB, cookie, release, k8s) kept** and renamed later in one planned cutover.~~ Superseded 2026-10-17: everything was renamed at once, with the move to a new domain. | Renaming stored names logs everyone out and touches live data. It needs downtime and a runbook, not a find-and-replace. |
| 2026-10-15 | **Game-specific code moves out of this repo** into per-game plugins. The hub keeps a generic games core. See §9. | Newcomers could not tell hub from game. The repo must stand alone. |
| 2026-10-15 | **Lobby becomes the in-repo example plugin.** | Proves the plugin API is sufficient, without shipping a commercial game. |
| 2026-10-15 | **Payments: Stripe and PayPal, both behind a provider behaviour.** Hosted checkout flows only. See §8. | Two providers from the start forces a clean abstraction. Hosted flows keep card data off our servers. |
| 2026-10-15 | **Store sells: in-game items, a virtual currency, subscriptions. No physical goods.** | Scope. No shipping, addresses or inventory. |
| 2026-10-15 | **Currency is hub-wide** (one balance usable by every game). | Simpler for players. The ledger records which game each spend is for. |
| 2026-10-15 | **Subscriptions grant storage tiers and access to VIP chat channels.** | The first two concrete entitlements. |
| 2026-10-15 | **User storage: one storage service behind an adapter; local volume first.** S3-compatible later by configuration. See §7. | The current two-system design is both broken and insecure. |
| 2026-10-15 | Roadmap order: storage → plugin API + Lobby → extract game code → commerce → start menu. See §12. | Storage tiers depend on storage; VIP channels and items depend on entitlements; the start menu is a view over all of it. |
| 2026-10-15 | **Storage tiers:** Free 1 GB, Small 10, Medium 25, Large 50, XL 100, Custom (whole GB, up to 1000). **$0.50/GB/month.** A paid tier **replaces** the free tier and is priced on its full size. Defined in `Bacon8.Drive.Plans` (overridable by config). | Owner's decision. |
| 2026-10-15 | **Quota by role:** Guest and Banned have 0 GB and cannot buy a tier; **admins are unlimited**; every other role (including gm/editor/moderator) gets Free and may buy tiers. The old per-role staff allowances are gone. | Owner's decision. |
| 2026-10-15 | **Becoming Guest/Banned:** the drive is locked (owner can't see or share anything; staff can still read), storage tiers are revoked, all subscriptions are cancelled, and files are **purged after 30 days** unless the role is restored first. Restoring does not restore tiers. Banning **no longer deletes files immediately**. | Owner's decision. A mistaken ban must be recoverable. |
| 2026-10-15 | **Share links:** files can be Only me / Anyone with the link / Public. | Owner's decision. |
| 2026-10-15 | **Migration scope:** only user files move to the drive now; avatars, blog, product and forum images stay where they are. | Owner's decision. Forum attachments still need guarding before VIP channels. |
| 2026-10-15 | **Banning still deletes posts, comments, chat messages and reactions immediately.** Only drive files get the 30-day hold. | Owner's decision: sensitive content must be gone at once. |
| 2026-10-15 | **Largest single upload, by role:** members 25 MB, moderators 50 MB, editors and GMs 1 GB, admins unlimited, guest/banned 0. Separate from quota; a file must fit both. `Drive.Policy.max_upload_bytes/1`, enforced in `Drive.add_file/5` as well as in the upload widget. | Owner's decision. |
| 2026-10-15 | **"My Uploads" (`/profile/uploads`) shows the drive**, not the media library. Blog/page/chat media is managed with its content. | Owner's decision. |
| 2026-10-15 | **Plugin API routes live under `/api/games/:slug/...`**, next to the platform API, using the same pipelines (player bearer token or server key). | Owner's decision. The launcher and game servers already authenticate there. |
| 2026-10-15 | **Lobby's game slug is `web_lobby`.** Its characters become ordinary platform `GameCharacter`s (games DB), retiring the site-DB `characters` table. | Owner's decision. Removes the duplicate `game_characters` model. |
| 2026-10-15 | **"Plugins", not "extensions"**, and **packaged WordPress-style: in-tree folders** under `plugins/<slug>/`, compiled into the app. A private plugin is its own git repo cloned into `plugins/` and gitignored by the public repo. | Owner's decision. A Mix-package model would be circular (plugins depend on the hub). |
| 2026-10-15 | **Web Lobby's own tables (zones, spells, character spells) move to the games DB**, next to its characters, prefixed `web_lobby_`. | Owner's decision: all game data together, so the plugin is a clean template. |
| 2026-10-15 | **Existing Lobby characters are not migrated**; the old site-DB tables are dropped. | Owner's decision: nothing worth keeping. |
| 2026-10-15 | **Plugins are activated from an admin Plugins page** (`/admin/plugins`), WordPress-style: no redeploy to turn one on or off. Installed plugins' routes are always compiled in and gated per request. | Owner's decision. |
| 2026-10-15 | **Plugin slug and game slug are separate.** The plugin slug is the folder name (underscores, maps to the module name); the game slug defaults to it but a plugin may keep an existing one (RaysSpaceSim stays `rays-space-sim`, which its clients use). Game slugs may now contain underscores. | Needed for `web_lobby`, and so existing game clients don't break. |
| 2026-10-16 | **RaysSpaceSim becomes a private plugin**: a new private repository cloned into `plugins/rays_space_sim`. The hub ignores every plugin folder it doesn't ship. The Unreal project stays its own repository at `/RaysSpaceSim/`. | Owner's decision. The hub sees it exactly as it sees Web Lobby. |
| 2026-10-16 | **The hub's game tables use game-neutral names:** `holo_sim_id` → `instance_id`, `holo_sim_location` → `instance_location` (columns, schemas, API JSON), and `PUT .../characters/:id/holo_location` → `.../instance_location`, **renamed now** with the game client updated in step. Old servers' `holo_sim_id` input and the old route are still accepted during the changeover. | Owner's decision ("rename now"). Accepting the old input keeps a running instance from re-registering as a world server mid-deploy. |
| 2026-10-16 | **`BACON8_ACTIVE_PLUGINS`** (comma-separated) sets which plugins are active until an admin toggles them. Production lists its plugins there. | Owner's decision. A private plugin is on from the first boot without the hub's config naming it. |
| 2026-10-16 | **Migrations squashed to one baseline per database** (`20250101000001_site_baseline`, `20260809100000_games_baseline`, and one per plugin), generated from production's schema. Production already records those versions, so it runs none of them. | A fresh install now builds the real schema instead of replaying a year of drift (the `cms_options` and `subscriptions` mismatches came from that). |
| 2026-10-16 | **The currency is Gems: 100 Gems = US$1.** No bundle bonuses; bonuses are for promotional events. | Owner's decision. |
| 2026-10-16 | **No refunds, ever**, for Gems, items or subscriptions. Cancelling a subscription stops the next renewal; the current period runs out. | Owner's decision. Chargebacks still happen (the bank decides those), so the ledger keeps the claw-back path. |
| 2026-10-16 | **Stripe first, in test mode**, once an account exists; PayPal after. Until then the provider interface is built and tested against a fake provider. | No Stripe account yet. |
| 2026-10-16 | **Launch Gem packs:** 500 ($5), 1,000 ($10), 2,500 ($25), 5,000 ($50), 10,000 ($100). Admins can change them. | Owner's decision. |
| 2026-10-16 | **Storage tiers and VIP access are card subscriptions** (Stripe, later PayPal), billed monthly; cancelling stops the next renewal. Gems are for in-game items. | Owner's decision. |
| 2026-10-16 | **The store is Buy buttons, no cart**: one checkout per pack or plan. The old physical-goods shop (cart, shipping statuses, download tokens) is retired. | Owner's decision. Every product is a single purchase. |
| 2026-10-16 | **Members and up may buy** (verified email, active account); Guest and Banned can't. Same rule as storage tiers. | Owner's decision. |
| 2026-10-16 | **No checkbox at checkout.** Buy starts checkout; "All sales are final" is small print beside the button. A Gem purchase gets one inline "Spend 💎 N?" confirm, because it spends at once. | Owner's decision. |
| 2026-10-16 | **Digital products:** downloads, game items, access passes (a private chat channel, or extra channel slots) and license keys. Each has a card price, a Gem price, or both; the Gem price defaults to 100 × the dollar price. Downloads are kept forever, always with the current files. Each product has its own page with images; the storefront has category tabs. | Owner's decision. |
| 2026-10-16 | **Deleting a user who has bought anything anonymizes the account** instead: personal data goes, the row and its orders and ledger stay. | Owner's decision. Sales records must outlive the account. |
| 2026-10-16 | **Nothing is built on the development PC**: no `npm`, no asset watchers in `config/dev.exs`. CSS and JS are built inside the container image. | Owner's decision. |
| 2026-10-16 | **CI's `staging-deploy` job is removed.** CI tests the public hub; production images come only from `deploy-prod.sh`, run from a working copy that has the private plugins. | Owner's decision. A CI-built image would ship without them. |
| 2026-10-16 | **GitHub Actions workflows removed** (`ci.yml`, `deploy-scheduler.yml`). CI had never passed: its test job had no database, it enforced format/Credo/Sobelow/Dialyzer checks the code has never met, and it ran browser tests needing a live server; the scheduler workflow deployed a branch that doesn't exist. Tests run in throwaway Docker containers before each commit (§14). | Owner's decision. Every push emailed a failure. |
| 2026-10-17 | **No access while a payment is disputed.** When the buyer's bank opens a dispute, everything the order delivered is taken away (downloads, items, passes and their channel membership, slots, keys, Gems); winning the dispute gives it back. | Owner's decision. |
| 2026-10-17 | **Renamed to Bacon8 everywhere, stored names included**: modules (`Bacon8`, `Bacon8Web`), OTP app and release `bacon8`, node names, the session cookie, database names, the Kubernetes namespace, objects and volumes, the container user, and the game side (the Unreal account plugin becomes `Bacon8Account`, with `-Bacon8*` flags and `BACON8_*` variables). Data moves into the new names by dump and restore; the old deployment and its domain are retired. The repository starts a fresh history. This is milestone 6 (§12), done early. | Owner's decision: a name of its own, clearly apart from the Phoenix framework it is built on. A new domain signs everyone out anyway, so renaming the cookie and the other stored names at the same time cost nothing extra. |
| 2026-10-20 | **The move is finished**: production has run under the new names since 2026-10-18, the game and launcher are rebuilt against them, and the old deployment, its volumes and the old working copy are deleted. The legacy wire names it kept alive (`holo_sim_id`, `PUT .../holo_location`) and the game's CoreRedirects for the old plugin are removed. | Every client and server in use was rebuilt, so nothing sends the old names. |
| 2026-10-20 | **Removed: the GraphQL API, `POST /api/auth/authenticate` and `GET /api/auth/users`.** Nothing used them. The GraphQL `login` and `/authenticate` checked passwords without the lockout, rate limit or banned/unverified checks the real login applies (and `/authenticate` said which of email or password was wrong); `/users` listed every account's email to anyone. | Security: they were open doors with no callers. |
| 2026-10-20 | **Brand assets come from masters in `brand/`** (and the game's `RaysSpaceSim/Brand/`), turned into every icon, favicon, manifest and splash by `scripts/brand/build_brand_assets.py`. The masters are placeholders until the real artwork exists. The Phoenix favicon and the Start button image are gone. | One drop-in point for the artwork; and the old images were other companies' marks. |
| 2026-10-20 | **Brand:** the logo is the "B8" monogram. The colours are blue `#247DF1`, cream `#E7F1FD` and near-black `#14100F`. The one-line description is "The kitchen sink." | Owner's decision. |
| 2026-10-20 | **All flagged third-party material is removed** and replaced with our own or CC0 work: synthesized sound effects and music (`scripts/audio/`), an original default avatar, no third-party fonts, and new character models (next row). The removed files wait in a gitignored holding folder until the owner deletes them. | Owner's decision; it was placeholder content. |
| 2026-10-20 | **Characters use our own skeleton, "B8 skeleton v1".** It has Unreal-style names, which Unreal's IK Retargeter, Unity's Humanoid and Godot's BoneMap all map. It has 3 spine bones, twist bones, breast and glute jiggle bones on every body, and `weapon_l`/`weapon_r` grip bones. Male and female share it. The bodies are Blender Studio's CC0 base meshes; the animations are Quaternius' CC0 Universal Animation Library, baked onto the skeleton. Built by the asset pipeline (`library/pipeline/Characters/B8Human`, originally in the game repository). | Owner's decision. Epic's skeleton and animations may only be used in Unreal, and the web, Unity and Godot versions must look the same as the Unreal game. |
| 2026-10-20 | **Legal pages are CMS pages:** `/pages/terms`, `privacy`, `refunds`, `copyright`, `contact`, `credits` and `gems`. They are seeded unpublished as placeholders to be reviewed with a lawyer, and the store's small print links to them. | Owner's decision. They can be edited in `/admin/pages` without a deploy. |
| 2026-10-20 | **Direction: a reusable core, with games and commerce as plugins** (`docs/adr/0001-core-and-plugins.md`). Web Lobby becomes **Bacon World** (`bacon_world`). The store, Gems and payments become **Bacon Store** (`bacon_store`). The games platform becomes a plugin later. The core becomes the starting point for other stand-alone sites. | Owner's decision. A site that sells nothing or runs no games shouldn't carry the code for them. |
| 2026-10-21 | **Web Lobby is renamed Bacon World** (`web_lobby` -> `bacon_world`), stored names included: the three `bacon_world_*` tables with their keys and indexes, the game row and the `plugin_states` row, by the plugin's own migrations. Plugins gain `previous_slugs/0`; old `/games/web_lobby/...` and `/admin/web_lobby/...` links answer 301. Ledger rows keep the slug they were written with. | ADR 0001, phase 1. A first-party game's name should say what it is; the redirect keeps old links and bookmarks working. |
| 2026-10-23 | **The asset pipeline moved to `library/pipeline`** (out of the RaysSpaceSim repository; not a git repository), shared by every game; the v1 humans were deleted, their sources and the copies imported into Unreal. | Owner's decision. |
| 2026-10-23 | **Asset rule (all games): ours, CC0, or licensed for commercial use, credited, with the source files never redistributed.** Licensed source files live in the gitignored shared library `library/` (one licence table per kind, e.g. `library/substance/LICENSES.md`); only baked outputs ship, credited on `/pages/credits`. | Owner's decision. Widens "ours or CC0" on purpose so curated libraries (Substance materials) can be used, without ever publishing files we may only use. |
| 2026-10-21 | **Web pods wait for migrations.** An init container in `bacon8-web` runs `Bacon8.Release.await_migrations/0` and starts the app only when no migration is pending. | A deploy starts `db-init` and the web pods together, so new code could serve the old schema for a few seconds, or write rows a stored-name migration then has to merge (found during ADR 0001 phase 1). |
| 2026-10-21 | **The store is a plugin, `bacon_store`**, mounted at `/store`, with the plugin framework it needs (site, site_api and fixed routes, `requires/0`, hooks). Its tables and migrations keep their names and versions; its admin moves to `/admin/bacon_store`; Stripe's webhook gets `/api/store/webhooks/stripe`, with the old URL kept as a `fixed` route until the dashboard is switched. Phases 2 and 3 shipped in one deploy. | ADR 0001. Core stops knowing about money; the owner chose one deploy for both phases. |
| 2026-10-21 | **Plugin data hooks ask every installed plugin and fail safe** (a crash means keep the user's data, or delete no blobs). | Switching a plugin off must not let core delete what the plugin still owns. |
| 2026-10-21 | **The old webhook URL is dropped.** `/api/webhooks/payments/:provider` is no longer routed; Stripe's endpoint was created at `/api/store/webhooks/stripe`. Supersedes the `fixed` route in the row before last. | No Stripe endpoint had ever used the old URL, so there was nothing to keep working. |

---

## 3. Architecture

```
                 ┌──────────────────────────── Bacon8Web ──────────────────────────────┐
 browser ──────▶ │ Endpoint ─ UploadsGuard ─ Plug.Static ─ Session ─ Router            │
                 │   LiveViews (pages, admin, store, forum, games)                     │
                 │   DesktopLive (global live_component on authed pages)               │
                 │   Channels (chat, presence)                                         │
 game client ──▶ │   /api/auth/*  /api/games/:slug/*  (JSON, Guardian bearer)          │
 game server ──▶ │   /api/games/:slug/*  with X-API-Key (server key)                   │
                 └───────────────────────────────┬─────────────────────────────────────┘
                                                 │
                 ┌──────────────────────────── Bacon8 (contexts) ──────────────────────┐
                 │ Accounts  Security  Content  Forum  Files  Scheduler  Settings      │
                 │ Notifications  Email  Moderation/Audit  Desktop                     │
                 │ Games (platform core)   Drive   Entitlements   Plugins              │
                 └──────────┬──────────────────────────────────────┬───────────────────┘
                            │                                      │
                  Bacon8.Repo (site DB)               Bacon8.GamesRepo (games DB)

 plugins/: Bacon Store (/store: products, Gems, payments), Bacon World (/games/bacon_world),
           and any private plugin; each reaches core only through its public contexts.
```

### Two databases

| Repo | Holds | Migrations |
|---|---|---|
| `Bacon8.Repo` | users, content, forum/chat, store and wallet, files and drive, scheduler, plugin states | `priv/repo/migrations` |
| `Bacon8.GamesRepo` | games platform: games, characters, servers, releases; plugins' tables | `priv/games_repo/migrations`, `plugins/*/priv/games_repo/migrations` |

Games tables cannot foreign-key to `users`, because that table is in the other database.
Their `user_id` columns are bare `binary_id` **by design**. Integrity is enforced in the
context functions, which always scope by the authenticated user id.

### Authentication

- **Browser:** session cookie holding a session token (`Accounts.get_user_by_session_token`),
  loaded by `Bacon8Web.Auth` (plug) and `Bacon8Web.UserAuth` (LiveView `on_mount`).
- **API / game clients:** Guardian JWT bearer tokens (`Bacon8.Auth.Guardian`).
- **Dedicated game servers:** `X-API-Key` matching `GAMES_SERVER_API_KEY`, always
  together with an explicit `user_id`. This key can act as any user, so it is read only
  from the environment and never from a file that could be shipped to a client.

**The load-bearing property of the games API: a client never asserts who it is.** It
presents a token; the server asks the hub to turn that into a user id, then asks for
records *scoped to that user id*. A forged or borrowed id returns 404 from the hub.

---

## 4. Repository layout

```
lib/
  bacon8/                 contexts (business logic, Ecto schemas)
    games/                 games platform core (game code lives in plugins, see §9)
    plugin.ex, plugins/    plugin behaviour, discovery, active state, runtime (§9)
    drive.ex, drive/       user storage (§7)
    files.ex, files/       legacy user files (Arc-based; dead code, see §13)
    safe_path.ex           path confinement, used for every client-supplied path
  bacon8_web/
    endpoint.ex            plug order matters, see §6
    router.ex
    live/                  LiveViews; admin_live/ for /admin
    live/desktop_live.ex   the desktop shell (~2k lines)
    plugs/uploads_guard.ex authorises /uploads, see §7
    controllers/api/       JSON API
priv/repo/migrations       site DB
priv/games_repo/migrations games DB
assets/                    esbuild + tailwind; three.js background scenes; vendor/ shims for plugins
plugins/                   installed plugins, one folder each (§9); bacon_world/ (a game) and bacon_store/ (a site plugin) are the examples
library/                   gitignored: licensed source assets shared by every game (Substance .sbsar...), each kind with its LICENSES.md; never committed or deployed
  pipeline/                the Bacon8 asset pipeline (Blender scripts, B8 skeleton and human blends, animation sources), moved from RaysSpaceSim 2026-10-23 (`scripts/`, `Characters/`, `Animations/`, `out/`); not in git
  makehuman/               CC0 MakeHuman sources for the humans
k3s/                       kustomize base + overlays (dev, prod)
config/runtime.exs         all deploy-time configuration via env vars
```

**Not part of the hub:** any plugin folder other than `plugins/bacon_world` and `plugins/bacon_store` (gitignored; a
private plugin is its own repository), and a game repository checked out at the root
(`/RaysSpaceSim/`, gitignored). RaysSpaceSim's deploy and build scripts, k8s manifests,
code map, mix task and admin pages moved into its private plugin on 2026-10-16.

---

## 5. Naming: code names vs stored names

Since 2026-10-17 every name is **Bacon8**, stored names included (decisions log). Code
names (modules, functions) can change in any commit. The names below are **stored**
somewhere outside the source tree, so changing one is a migration with downtime and a
runbook, not a find-and-replace:

| Name | Where | What renaming it would do |
|---|---|---|
| session cookie `_bacon8_key`, salt `bacon8_session` | `endpoint.ex` session options | Invalidates every session cookie. Everyone is logged out. |
| release `bacon8` (`bin/bacon8`, `rel/bacon8`) | `mix.exs` `releases/0`, Dockerfiles, k8s jobs, scripts | Every job and script that runs `bin/bacon8 eval ...` must change in the same deploy. |
| node name `bacon8@<pod ip>`, libcluster `kubernetes_node_basename` | deployment manifest, `runtime.exs` | Pods from old and new builds cannot cluster during a rollout. |
| database names `bacon8_*`, `bacon8_games_*` | config defaults, configmap | A dump and restore into the new names. |
| namespace `bacon8`, objects `bacon8-*`, PersistentVolumes and their host directories | `k3s/` | Volumes are bound by name; renaming one orphans its data unless the data is copied across first. |
| container user `bacon8`, uid 100 / gid 101 | Dockerfiles; the deployment's init container (`chown 100:101`) | Files already on the volumes keep their owner. The ids are pinned so a rebuilt image can still write them. |
| Postgres `application_name` labels | `runtime.exs` | Cosmetic (`pg_stat_activity`), but monitoring queries match on them. |

**Game clients and servers carry names too.** They are separate builds with their own
copies of the names they use: command-line flags, environment variables, module paths.
Renaming anything a game reads means rebuilding and shipping every client and server in
step, and an Unreal game also needs CoreRedirects for renamed modules and types, or its
Blueprints lose their parent classes.

**Ecto telemetry follows the app name.** Repo events are `[:bacon8, :repo, :query]`, so
metric names in `telemetry.ex` are `bacon8.repo.query.*`. Dashboards keyed on an earlier
app name stopped receiving data at the 2026-10-17 rename.

---

## 6. Invariants

Each of these has already cost a build, an outage, or a security hole.

1. **Every client-supplied path goes through `Bacon8.SafePath`.** `Path.join/2` does not
   resolve `..`; `Path.join(user_root, "../other_user/x")` escapes. Use `SafePath.resolve/2`
   for paths and `SafePath.filename/1` for single names (upload `client_name`, folder
   names). Before 2026-10-15 the file explorer let any signed-in user list, upload into,
   and delete files outside their folder this way.

2. **`UploadsGuard` sits directly before the `/uploads` `Plug.Static` in `endpoint.ex`.**
   It is what keeps `users/<id>/` and `<id>/files/` private and what adds
   `nosniff` / sandbox headers. Moving it after `Plug.Static`, or adding another static
   mount over the same directory, makes private files public again. Nothing will error.

3. **`Plug.Static` options are evaluated at compile time.** `@uploads_root` in
   `endpoint.ex` is decided when the release is built (`/app/uploads` if it exists in the
   build environment, else `uploads`). The guard and the static plug must use the same
   value, so both read the module attribute.

4. **Never serve active content inline from our origin.** HTML, SVG, XML and JS uploads are
   refused (`SafePath.active_content?/1`), and anything already on disk with those
   extensions is served with `Content-Security-Policy: sandbox` and
   `Content-Disposition: attachment`. A user-uploaded `.svg` rendered inline can steal
   sessions.

5. **Signed URLs carry their lifetime inside the token.** `Uploads.signed_url_for/2`
   signs `max_age` into the token, capped at one day; the controller verifies without
   passing `max_age`. Never accept a lifetime from the query string. It used to, and that
   made every signed link permanent.

6. **In HEEx and conditionals, use `&&` `||` `!`, not `and` `or` `not`, on anything that
   can be nil.** `and` raises `BadBooleanError` on nil and takes the whole page down with
   a bare 500.

7. **`POST /api/auth/dev-verify` must 404 in prod.** It marks any email verified without
   authentication. It is enabled only by `:allow_dev_verify` in `dev.exs`/`test.exs`.
   Do not "fix" the prod 404.

8. **The games server key is environment-only.** See §3. A missing key makes every game
   server join look like a broken join gate. The log says the variable is not set.

9. **Login rate limiting is per IP.** Local testing from `127.0.0.1` with rapid restarts
   produces `429`, which looks like a wrong password.

10. **Elixir version is pinned (`~> 1.19.0` in `mix.exs`).** `elixir:latest` images are
    newer and refuse to build. Pin Docker base images to `elixir:1.19*`.

11. **The drive blob store lives on the uploads volume but must never be served by path.**
    `Storage.Local` defaults to `<uploads>/_drive`, which is inside the directory
    `Plug.Static` serves at `/uploads`. `UploadsGuard` answers 404 for every
    `/uploads/_drive/...` request. Bodies are only served by `DriveController` after
    `Drive.can_read?/3`. If you move the root, keep it out of every static mount.

12. **Change roles only through `Accounts.change_role/3`.** It is what locks the drive,
    revokes tiers and cancels subscriptions. `role` is no longer cast by the profile or
    admin changesets, so `update_user/2` cannot change it.

13. **The desktop is a LiveComponent.** It never receives `handle_info`, and
    `send(self(), ...)` from it goes to whatever page LiveView is mounted, which doesn't
    handle the message. Update component state directly (see
    `refresh_file_manager/2`).

14. **Run migrations with `mix bacon8.migrate`**, not `mix ecto.migrate`: only the
    former includes installed plugins' migration folders. Releases use
    `Bacon8.Release.migrate/0`, which does too.

    Each database (and each plugin) starts from one baseline migration generated from
    production's schema; schema changes are new migrations after it. Never edit a baseline.

    In Kubernetes the `db-init` job migrates, and the web pods' `wait-for-migrations` init
    container (`Bacon8.Release.await_migrations/0`) holds the app back until nothing is
    pending, so new code never serves the old schema. A pod whose image brings migrations
    that were never run stays in `Init` while the old pods keep serving; run `db-init`.

15. **Line endings.** The repo stores LF. Windows checkouts use `core.autocrlf=true`,
    except shell scripts: `.gitattributes` keeps `*.sh` LF on every checkout, because they
    run inside Linux containers and a CRLF shebang (`/bin/bash\r`) cannot be executed.
    `bacon8-start.sh` is the web pod's entrypoint, so a CRLF copy stops the pod starting.
    Tools that rewrite files must preserve the working-tree line endings and must not leave
    a lone `\r` (a bare CR at end of file does not parse in Elixir). If a non-Windows git
    reads a Windows checkout it shows every line as changed; compare with
    `git diff --ignore-cr-at-eol`.

16. **The `:api` pipeline has no authentication.** Anything that returns account data or
    checks a password belongs in `:api_auth`, `:api_authenticated` or `:games_api`, or
    checks the caller itself. Passwords are checked only through
    `Accounts.authenticate_user_secure/3`, which applies the IP rate limit, the lockout and
    the banned/disabled/unverified checks; `authenticate_user/2` has none of them. (A user
    list and two side-door logins sat in `:api` until 2026-10-20.)

17. **`/models` serves runtime formats only.** `ModelsGuard` answers 404 for anything that
    isn't a format a 3D client loads (`.gltf`, `.glb`, `.bin`, `.fbx`, textures...). The
    volume also holds `.blend` scenes and `.zip` downloads, which many asset licences do
    not allow redistributing. Keep the guard directly before that `Plug.Static`.

---

## 7. User storage and the file explorer

### Status: deployed 2026-10-15

The legacy import found nothing to move: production's `user_files` and `user_folders`
tables were empty, so the drive started clean. (The 19 `user_media` rows are blog, page
and chat images, which stay where they are by design.)

Before this milestone there were two storage systems that didn't know about each other:
Arc `UserFile` rows and the desktop explorer writing raw files under `uploads/users/<id>/`.
Uploads to My Files never saved, because the explorer only saved uploads for the old
`user://` paths, and refreshes never happened, because of invariant 13. Both are fixed.

### Design

**The database is the only source of truth**; `Bacon8.Storage` stores bodies by SHA-256
and nothing else.

| Table | Purpose |
|---|---|
| `drive_blobs` | one row per distinct SHA-256; `last_referenced_at` protects in-flight uploads from GC |
| `drive_folders` | tree per owner (`parent_id` nil = root); sibling names unique |
| `drive_files` | name, folder, blob, size, sniffed `content_type`, `visibility` (private / link / public), `share_token`, `legacy_ref` |
| `drive_usage` | per-user `bytes_used` / `file_count` (row-locked for every change), `locked_at`, `purge_after` |
| `entitlements` | grants; storage tiers are `kind: "storage_tier"`, `quantity` = GB (§8) |

| Module | Role |
|---|---|
| `Bacon8.Drive` | folders, files, upload (`add_file/5`), sharing, `can_read?/3`, lock/unlock, purge, blob GC |
| `Bacon8.Drive.Plans` | tiers and prices (decisions log) |
| `Bacon8.Drive.Policy` | pure quota and permission rules |
| `Bacon8.Drive.Sniff` | magic-byte type detection; only recognised types are ever served inline |
| `Bacon8.Drive.Janitor` | hourly: purge expired 30-day holds, GC unreferenced blobs; one node at a time via a Postgres advisory lock |
| `Bacon8.Drive.Import` | one-off legacy import, re-runnable (`mix drive.import`, or `bin/bacon8 rpc "Bacon8.Drive.Import.run()"`) |
| `Bacon8.Storage` / `Storage.Local` | adapter behaviour; local blobs at `<root>/aa/bb/<sha>`; `DRIVE_STORAGE_ROOT` overrides the root |
| `Bacon8Web.DriveController` | `GET /files/:id` and `GET /s/:token`; nosniff, sandbox CSP (except PDF), inline only for recognised media, single-range requests |
| `Bacon8.Entitlements` | `grant/2` (refuses storage tiers for ineligible users), `active/2`, `revoke_all/3` |

**Concurrency.** Every change to a user's total locks their `drive_usage` row first, so
two uploads can't both pass the quota check. An upload upserts its blob row (taking the
row lock and bumping `last_referenced_at`) *before* making sure the body is on disk; GC
selects blobs `FOR UPDATE SKIP LOCKED` and deletes bodies inside its transaction. Either
the upload waits and rewrites the body, or GC skips that blob.

**Over quota** (after a tier lapses, or after the import): files are kept and stay
readable, and new uploads are refused until usage is back under the quota.

**Known gaps in this milestone**

- A crash between writing a body and committing can leave an unreferenced body on disk
  with no row, which GC never sees. This is rare; an occasional disk sweep can be added.
- No rename/move UI yet in the explorer (the context supports both).
- Thumbnails aren't generated for drive images; the explorer shows icons.

### Explorer

Drives: **My Files** (the user's drive, navigated by folder names: `/my-files/Photos/2026`)
and **Public** (still the legacy `uploads/public` directory, staff-writable, holding site
assets). Each My Files row has a visibility selector and, when shared, a click-to-copy
link. The old `user://` / `root://` code paths in `DesktopLive` are unreachable
from the current UI and should be deleted in milestone 5.

### Running the import (for other installs)

1. Deploy (the migration runs as usual).
2. `bin/bacon8 rpc "Bacon8.Drive.Import.run(dry_run: true)"` and check the counts.
3. `bin/bacon8 rpc "Bacon8.Drive.Import.run()"`. Users already Guest/Banned are
   locked by the import, which starts their 30-day hold.
4. Legacy files stay on disk and readable through `UploadsGuard` for one release, then
   retire them.

`rpc`, not `eval`: `rpc` runs inside the running node, where the repos are started;
`eval` boots a separate VM without them.

---

## 8. Store, payments, currency and entitlements

### Status

**A plugin since 2026-10-21** (ADR 0001, phase 3): everything below lives in
`plugins/bacon_store` (`BaconStore`, `BaconStoreWeb`; slug `bacon_store`, mounted at
`/store`). Its tables keep their names (`store_*`, `wallet_*`, `payment_events`): a
documented exception to the `<slug>_` prefix, because renaming a ledger buys nothing.
Its three migrations moved unchanged (same versions, so production ran nothing), and a
core migration (`20261022000000`) drops the old shop's leftovers on installs without the
store. Core reaches it only through plugin hooks (§9): account deletion
(`retains_user_data?/1`), blob GC (`storage_refs/0`), navigation, profile, admin
dashboard and API toolbox. Its admin pages moved to `/admin/bacon_store/...`.
Entitlements stay in core; the store registers its kinds (`store_download`,
`channel_access`, `channel_slots`).

**Milestone 4a, implemented 2026-10-16:** Gems and the store, with a fake payment provider.

| Piece | Where |
|---|---|
| Double-entry Gem ledger (`wallet_accounts`, `wallet_transactions`, `wallet_entries`) | `BaconStore.Wallet`: `balance/1`, `credit_purchase/4`, `spend/3`, `grant/3`, `clawback/3`, `history/2`. Every call has an idempotency key; user rows are locked, system accounts aren't (see its moduledoc) |
| Products and orders (`store_products`, `store_orders`) | `BaconStore.Store`: `gem_packs/0`, `can_buy/1`, `start_checkout/3`, `apply_event/1`. Packs are validated at 100 Gems/$; extra Gems only as a dated promotion (`bonus_gems`, `promo_starts_at`/`ends_at`) |
| Event inbox (`payment_events`) | `BaconStore.Payments`: `ingest/1` stores then applies; a failed event is retried on re-delivery (and its `error` cleared once it succeeds). A dispute that arrives before its order knows the PaymentIntent waits unprocessed and is replayed when the checkout completes (`replay_waiting/2`) |
| Providers | `BaconStore.Payments.Provider` (`create_checkout/2`, `parse_webhook/2`; no refund callback). `Payments.Fake` for dev/test, refused unless `fake_enabled` |
| Pages | `/store`, `/store/orders`, `/store/orders/:id` (updates live), `/store/fake-checkout/:ref` (dev/test). The "all sales are final" checkbox was removed in 4c |

**Milestone 4b:** Stripe, admin pages, and the old shop retired.

| Piece | Where |
|---|---|
| Stripe Checkout (one-time payments) | `BaconStore.Payments.Stripe`, plain HTTPS through `Bacon8.Finch` (no Stripe library). Enabled when `STRIPE_SECRET_KEY` is set; then it is the default provider unless `PAYMENTS_PROVIDER` says otherwise |
| Webhooks | `POST /api/store/webhooks/:provider` (`BaconStoreWeb.PaymentWebhookController`). `Bacon8Web.RawBodyReader` keeps the raw body for the paths the plugin names (`raw_body_paths/0`); Stripe's `Stripe-Signature` HMAC is checked against `STRIPE_WEBHOOK_SECRET` with a 5-minute tolerance. 200 = handled or ignored, 400 = bad signature/body (not retried), 500 = processing failed (Stripe retries) |
| Events used | `checkout.session.completed` (when `paid`), `checkout.session.async_payment_succeeded`/`_failed`, `checkout.session.expired`, `charge.dispute.created`, `charge.dispute.closed` (won/lost). Disputes find the order by its PaymentIntent (`store_orders.provider_payment_ref`) |
| Admin | `/admin/bacon_store/products` (Gem packs: price, Gems, dated promotion, badge, on/off sale; never deleted), `/admin/bacon_store/orders` (orders, order detail, the payment event inbox; read-only) |
| Old shop | Removed: `Commerce`, `/shop`, `/cart`, `/checkout`, the old admin products/orders/subscriptions pages, their tables and the users columns only they used (migration `20261016210000`) |

**Setting up Stripe.** Test mode first. Locally: export `STRIPE_SECRET_KEY` (an
`sk_test_` key), run `stripe listen --forward-to localhost:4000/api/store/webhooks/stripe`
and export the `whsec_` it prints as `STRIPE_WEBHOOK_SECRET`. In production both go in
the gitignored `k3s/overlays/prod/secrets.yaml`, and the webhook endpoint
`https://<host>/api/store/webhooks/stripe` is added in the Stripe dashboard with the
events above. Keys never go in the repository. The plugin reads `STRIPE_SECRET_KEY`,
`STRIPE_WEBHOOK_SECRET` and `PAYMENTS_PROVIDER` itself, at runtime (not `runtime.exs`).

**Production (2026-10-21):** Stripe is set up in **test mode**: the webhook endpoint is the
site's `/api/store/webhooks/stripe` with the six events in the Stripe row above. The
pre-plugin URL `/api/webhooks/payments/:provider` was never registered with Stripe, so it was
removed rather than kept as a `fixed` route.

**Milestone 4c:** digital products.

| Piece | Where |
|---|---|
| Kinds | `Store.Product.kind`: `gem_pack`, `download`, `item`, `access`, `license_key` (table in its moduledoc). Prices: `price_cents` and/or `price_gems` |
| Catalog | `BaconStore.Store.Catalog`: categories (`store_categories`), products, images and download files (`store_product_files`), license key pools (`store_license_keys`). File bodies use `Bacon8.Storage` like drive files; `Drive.gc_blobs/2` keeps any body a product file names |
| Delivery | `BaconStore.Store.Fulfilment`: entitlements with `source_type` "store_order" (`store_download`, a plugin's item kind, `channel_access`, `channel_slots`), keys from the pool, Gems to the wallet. An open bank dispute takes it all away at once (Gems too, even into a negative balance); a won dispute gives it back, a lost one makes it permanent. Plugins get `{:entitlement_granted, e}` / `{:entitlement_revoked, e}` hub events |
| Gems | `Store.buy_with_gems/2`: spend and deliver in one transaction |
| Card | `Store.start_checkout/3` reserves a license key until the order is paid, fails or is cancelled. Paid but undeliverable (keys ran out) stays "paid" with a reason; `/admin/bacon_store/orders` has "Retry delivery" |
| Expiry | `BaconStore.Store.Sweeper` (every 5 min, advisory lock): ends timed items and passes (a pass's channel membership goes with it), cancels card orders unpaid for 48 h |
| Pages | `/store` (category tabs, product grid, Gem packs), `/store/p/:slug` (gallery, Buy with card / Gems), `/store/library` (downloads, keys, items and passes), `GET /store/media/:id` (images), `GET /store/download/:id` (buyers only, attachment) |
| Admin | `/admin/bacon_store/products` (all products, new-product buttons per kind, categories), `/admin/bacon_store/products/new?kind=…` and `/admin/bacon_store/products/:id` (`BaconStoreWeb.Admin.ProductEditor`: text, prices, delivery, images, files, keys) |
| Accounts | `Accounts.delete_user/1` anonymizes a user with orders, ledger entries or keys instead of deleting the row |

Download size is capped by `config :bacon8, BaconStore.Store, max_download_bytes:` (default 2 GiB). Uploads go through the LiveView socket in 1 MB chunks and are staged in the pod's temp directory first, so the pod needs that much free temp space.

Next: card subscriptions for storage tiers and VIP channels (Stripe Billing), then PayPal.

### Target model (milestone 4)

**Money** is always integer minor units plus an ISO currency code. Never floats.

**Products** have a `kind`:

| kind | Bought with | Grants |
|---|---|---|
| `currency_pack` | money | Gems in the user's wallet |
| `item` | money or Gems | an entitlement (e.g. an in-game item) |
| `subscription_plan` | money, recurring | entitlements while active (storage tier, VIP channels) |

**Orders** are a state machine. Transitions happen only in `Store`, never in a
LiveView:

```
draft → awaiting_payment → paid → fulfilled
                 ↘ failed / cancelled
paid|fulfilled → disputed → (won → fulfilled | lost → charged_back)
```

Order items snapshot name, price and currency at purchase time.

**Payment providers** implement `BaconStore.Payments.Provider`:

```elixir
@callback create_checkout(order, opts) :: {:ok, %{redirect_url: String.t(), provider_ref: String.t()}} | {:error, term}
@callback verify_webhook(raw_body :: binary, headers :: list) :: {:ok, provider_event :: map} | {:error, term}
@callback normalize(provider_event :: map) :: {:ok, %BaconStore.Payments.Event{}} | :ignore
@callback create_subscription(user, plan, opts) :: {:ok, %{redirect_url: String.t(), provider_ref: String.t()}} | {:error, term}
@callback cancel_subscription(subscription) :: :ok | {:error, term}
```

`Payments.Stripe` (Checkout Sessions, Billing) and `Payments.PayPal` (Orders v2,
Subscriptions) are the two built-in implementations. Hosted flows only: card data never
touches our servers.

**Webhooks are the source of truth**, not redirects.

- `payment_events` is an inbox: `unique(provider, provider_event_id)`. Each event is
  stored first, then processed. A duplicate delivery is a no-op.
- Signature verification needs the **raw body** (Stripe), so the webhook routes use a
  `Plug.Parsers` `body_reader` that keeps it. PayPal verification calls PayPal's
  verify-signature API.
- A user returning from checkout sees "processing" until the webhook marks the order
  paid. Never fulfil from the redirect.

**Gems.** The hub-wide currency (implemented: `BaconStore.Wallet`, `BaconStore.Store`). **100 Gems = US$1**, so a pack's price is its Gems / 100
dollars; no bonus Gems except in promotional events (a promotion is a pack with extra
Gems and an active window, set by an admin). **No refunds, ever** (decisions log): there is
no refund path in the code, and the store, checkout and terms say so before payment. A
chargeback is not a refund we give; it is handled below.

**Wallet** is an append-only, double-entry ledger:

```
wallet_accounts  id, owner_type (user | system), owner_id, currency ("GEMS")
ledger_entries   id, txn_id, account_id, amount (signed integer), kind, game_slug,
                 reference_type, reference_id, idempotency_key, inserted_at
                 unique(idempotency_key)
```

Every transaction writes entries that sum to zero (e.g. user +500,
`system:gem_sales` −500). A balance is the sum of the account's entries, cached in
a row updated in the same transaction. Spends record `game_slug`, so per-game revenue is
a query. Balances may not go below zero through spending. A lost chargeback on a
Gem pack **claws back** the Gems and may leave a negative balance, which blocks
further spending until it is settled. (We never refund; a lost chargeback is the bank
taking the money back, and the Gems it paid for go with it.)

Games spend Gems through the hub, never locally: `POST /api/wallet/spend` with the
server key, user id, amount, item and an idempotency key. The hub debits and grants the
entitlement in one transaction.

**Entitlements** are how anything purchased becomes access:

```
entitlements  id, user_id, kind, key, source_type, source_id,
              starts_at, ends_at (nullable), revoked_at (nullable)
```

| kind | key | Granted by | Checked by |
|---|---|---|---|
| `storage_tier` | `basic` / `plus` / ... | subscription plan | storage quota (§7) |
| `vip_channels` | `*` | subscription plan | channel listing and join (§11) |
| `game_item` | `<game_slug>:<sku>` | item purchase | the game, via API |

`Entitlements.active?(user, kind, key)` is the single check. Plugins register their
own kinds. Subscription renewals extend `ends_at` (period end + a grace period);
cancellation lets it lapse (no refund for the rest of the period); a lost chargeback sets
`revoked_at`.

**Subscriptions:** our DB is the source of truth for state. Each plan stores one
provider plan id per provider (`stripe_price_id`, `paypal_plan_id`). Provider webhooks
move our state; we never poll for it.

**Providers, in order:** Stripe (test mode now, live after the legal pages are published),
then PayPal. The test suite and local development use `Payments.Fake`.

**Not decided yet:** tax handling (Stripe Tax vs manual), the exact no-refund wording in
the terms, and whether Gems can be gifted between users. (The launch Gem packs are in the
decisions log.)

---

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
from the hub's `instance_id` columns to `holo_sims`. Forum channels are Holo-sims' access
lists; the plugin follows channel changes through `hub_event/1`.

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
  @callback desktop_apps() :: [Bacon8.Desktop.App.t()]   # §10
  @callback entitlement_kinds() :: [String.t()]           # §8
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
so far, all from `Bacon8.Forum`: `{:channel_updated, new, old}`, `{:channel_deleted, id}`
(before the channel's rows go, outside its transaction), `{:channel_member_removed,
channel_id, user_id}` (kick or ban). Plugins must ignore events they don't know.

**Files and settings.** `Bacon8.Plugins.priv_dir/1` finds a plugin's `priv/` in a release
or the source tree. A plugin reads its own environment variables at runtime; the hub's
`config/runtime.exs` doesn't know it (the store's Stripe settings are the example). App
config keyed by a plugin module (`config :bacon8, BaconStore.Payments, ...`) is fine for
development and tests: it names an atom, so core still compiles without the plugin.

**Private plugins in deploys.** `.dockerignore` keeps every plugin's `.git`, `k3s/`,
`scripts/` and `*.sh` out of images. `deploy-prod.sh` applies each `plugins/*/k3s` (with a
`kustomization.yaml`) and then any `*secrets.yaml` beside it.

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
  (`library/pipeline/scripts`). The humans' manifests are `.json`, which `/models` refuses
  (invariant 17), so the LiveView passes them in `data-human-assets`.

  Model URLs carry a version (`?vsn=`, from size and mtime), and `/models` serves
  `.glb.gz` copies when present (`gzip: true`).

## 10. Desktop shell and start menu

`DesktopLive` is a global `live_component` rendered on every authenticated page:
a taskbar, a start menu and draggable windows. It is not a route.

**Current apps:** File Explorer, Text Editor, Terminal, Calculator, Notepad, Media
Player, Settings. Most are toys, Text Editor and Notepad overlap, and window-layout
persistence is commented out ("TEMP DISABLED").

**Target (milestone 5):** every start-menu entry opens a real hub feature.

| App | Backed by |
|---|---|
| Files | storage service (§7) |
| Chat | forum/channels, including VIP channels (§11) |
| Library | owned games, entitlements, launcher downloads |
| Store | products, one-click checkout |
| Wallet & Orders | ledger balance, order history, subscriptions |
| Friends | presence |
| Forum | threads |
| Calendar | calendar and meeting invites (exists) |
| Notifications | `Notifications` |
| Account & Security | profile, password, 2FA, sessions, devices |
| Admin (staff only) | servers, moderation queue, audit log |

Apps are data, not hardcoded `case` branches:

```elixir
%Bacon8.Desktop.App{
  id: "files", title: "Files", icon: "folder",
  component: Bacon8Web.Desktop.FilesApp,
  visible?: &Bacon8.Desktop.Visibility.signed_in?/1,   # or a role / entitlement check
  default_size: {900, 600}
}
```

Core apps come from `Bacon8.Desktop.core_apps/0`; plugins add theirs via
`desktop_apps/0` (§9). Window-layout persistence comes back, debounced.

---

## 11. Chat channels and VIP channels

Channels live in `Bacon8.Forum` (`channels`, `channel_members`, `messages`,
`message_attachments`) with Phoenix Channels for real time and presence, plus an optional
Redis bridge for cross-node delivery.

**VIP channels (milestone 4):** like public channels, except

- only admins create them;
- they are **invisible** to users without an active `vip_channels` entitlement: filtered
  in the listing query, not just hidden in the UI;
- joining, reading history and subscribing to the socket topic all check the entitlement
  on the server. A direct link or a hand-crafted socket join must fail;
- when the entitlement lapses, the user is dropped from presence on the next check and
  loses access to history;
- attachments posted in them are served through the authorising files controller (§7),
  never `/uploads/forum/...`.

Implementation: a nullable `required_entitlement` column on `channels` (e.g.
`"vip_channels"`), so the same mechanism can gate other channel types later.

---

## 12. Roadmap

| # | Milestone | Done when |
|---|---|---|
| 1 | **Storage service + file explorer** (§7) | One storage system; explorer and profile uploads show the same files; quotas enforced transactionally; all user files served through the authorising controller; old data migrated. |
| 2 | **Plugin API + the first game on it** (§9, §10) | The game (then Web Lobby, now Bacon World) works with zero references in core; a plugin can add routes, admin nav, desktop apps, migrations. *Done 2026-10-15.* |
| 3 | **Extract game-specific code** (§9) | Nothing game-specific in this repo; the game's plugin boots against an unmodified hub. *Code moved 2026-10-16; done once the private repo exists, the suite is green with and without it, and the game client is rebuilt.* |
| 4 | **Commerce** (§8, §11) | Ledger + entitlements; Stripe then PayPal; currency packs, items, subscriptions; storage tiers and VIP channels driven by entitlements; webhook inbox idempotent. |
| 5 | **Start menu redesign** (§10) | Every app maps to a real feature; apps are registered data. |
| 6 | **Stored-name cutover** (§5) | Cookie, release, node, DB and k8s names are Bacon8; runbook written and executed. *Done 2026-10-18 (decisions log).* |
| 7 | **Bacon World** (ADR 0001, phase 1) | `web_lobby` is renamed everywhere, its stored names are migrated (tables, game row, plugin state) and old links redirect. *Done 2026-10-21.* |
| 8 | **Site plugins** (phase 2) | Plugins can mount site routes (e.g. `/store`) and declare required plugins. Hooks replace core's direct calls into the store. *Done 2026-10-21.* |
| 9 | **Bacon Store** (phase 3) | Core compiles and its suite passes without `plugins/bacon_store`; with it, everything in §8 behaves as before. *Done 2026-10-21.* |
| 10 | **Games platform as a plugin** (phase 4) | The core runs with one database; Bacon World and RaysSpaceSim require `bacon_games`. |
| 11 | **Site kit** (phase 5) | A new stand-alone site from the core is a configuration change and a deploy. |

---

## 13. Known debt

Ordered roughly by how much it hurts.

- **RaysSpaceSim's settings still live in the hub's prod configmap** (`HOLOSIM_*`,
  `WORLD_*`, and `deploy-game.sh` writes `HOLOSIM_IMAGE` there), so a game deploy edits a
  hub file. Move them to a configmap the plugin's `k3s/` owns and have the hub deployment
  read it with `envFrom` (`optional: true`).
- ~~Third-party material served to players~~ (removed from the repository and replaced
  2026-10-20 with original sounds and music, an original default avatar, no third-party
  fonts and CC0-based characters). **Still to do in production:** delete the old files
  from the uploads and models volumes, and sync the new models.
- **The legal pages are unpublished drafts.** Publish them from `/admin/pages` after the
  lawyer's review, and before the store takes live payments.
- **Game releases are Development builds**: the console works for players and the window
  title carries debug info. Ship Shipping builds (`CLIENT_CONFIG=Shipping`).
- A few core comments still mention RaysSpaceSim as history. Harmless; don't add new ones.
- ~~Legacy wire names (`holo_sim_id`, `PUT .../holo_location`)~~ (removed 2026-10-20, once
  every client and server had been rebuilt).

- **The `assets.setup`, `assets.build`, `assets.deploy` and `lint` mix aliases (and so
  `mix setup`) call `scripts/dev-assets.sh`, which no longer exists.** Assets are built
  only inside the image (`Dockerfile.multistage`); nothing is built on the development PC
  (decisions log). Point the aliases at a container build, or drop them.

- ~~`mix.lock` is not committed~~ (committed 2026-10-15).
- ~~Dead quota columns on `users`~~ (`storage_quota_bytes`, `storage_used_bytes`,
  `subscription_tier`, `subscription_features`; dropped 2026-10-16, migration
  `20261016210000`). Quota comes from `Bacon8.Drive.quota_bytes/1`.
- ~~The test suite can't run~~: `test/test_helper.exs` and `test/support/data_case.ex`
  added 2026-10-15 (sandboxes both repos; `user_fixture/1`, `tmp_upload/1`).
- ~~`cms_options` schema and migration disagreed~~ (fixed 2026-10-15): fresh databases got a
  table `Settings.Option` couldn't use, and production's had a unique `key` column nothing
  set, which would have broken the second new setting. Fixed in production, and the site
  baseline now has the schema's shape.
- ~~Scheduler engine wrote a column that didn't exist~~ (fixed 2026-10-15):
  `earliest_finish_at` added to `tasks` and `Scheduler.Task`.
- ~~`subscriptions` schema didn't match the table~~ (fixed 2026-10-15): the schema said
  `cancelled_at` (the column is `canceled_at`; now `source: :canceled_at`) and seven
  declared fields had no column. Added in production; in the site baseline.
- ~~The root `Dockerfile` used `FROM elixir:latest`~~ (pinned to `elixir:1.19`).
- **`Bacon8.LogBufferBackend` is a legacy `:gen_event` Logger backend**, deprecated since
  Elixir 1.15. It works (and now normalises the `:warn` level it is still handed), but should
  become an Erlang `:logger` handler.
- **Forum attachments are public by URL** (§7), which blocks VIP channels.

- **The legacy file system is dead code.** Production's `user_files` / `user_folders` are
  empty (checked 2026-10-15), so `Bacon8.Files` (`UserFile`, `UserFolder`),
  `FileController`, `file_manager_component.ex`, `Drive.Import` and `mix drive.import`
  can be deleted and the two tables dropped. Do it with the explorer cleanup in
  milestone 5; check other installs have run the import first.
- `User.registration_changeset/2` casts `:role` and `:is_admin`. `register_user/2`
  overwrites both, so it isn't exploitable today, but `Accounts.create_user/1` passes attrs
  straight through (its one caller left is the plugin's `mix rss.dev_users`). Drop the two
  fields from the cast and set them explicitly.
- `Accounts.authenticate_user/2` (no lockout, no rate limit) has no callers since the
  GraphQL removal; delete it so nothing new picks it up (invariant 16).
- `POST /api/webhooks/scheduler/:secret` carries its secret in the URL, so the request
  line in the app and ingress logs still shows it (parameter filtering only covers the
  parameters). Move it to a header.
- Bacon World's own follow-ups (creature collisions, server-side walls, remote crouch, the
  skill tree, `.glb.gz` upkeep, TypeScript errors) are tracked in `BACON_WORLD.md` §7.
- `Files` has a `:timer.sleep(10000)` in an upload path (goes with the legacy file system above).
- The admin files page links to `/uploads/user_files/...`, which is not where files are
  stored.
- `Bacon8Web.RoomChannel` is referenced (commented out) but doesn't exist.
- `desktop_live.ex` is ~2,000 lines; the explorer, uploads, calendar and audio
  should become separate app components (milestone 5).
- Repo-root files that are operator-specific belong outside the repo:
  `Handy_Command_Samples.md`, and any local secrets file (even when gitignored, keep
  secrets outside the working tree).
- Tracked dev secrets in `k3s/overlays/dev/secrets.yaml` should all be obvious
  placeholders.

---

## 14. Development workflow

- **Elixir 1.19.** If you don't have it locally, compile in Docker without touching the
  host tree (deps and build in throwaway volumes):

  ```sh
  docker run --rm -v "$PWD:/app" -v bacon8_deps:/app/deps -v bacon8_build:/app/_build \
    -w /app -e MIX_ENV=dev elixir:1.19 \
    sh -c 'mix local.hex --force && mix local.rebar --force && mix deps.get && mix compile --warnings-as-errors'
  ```

  Warnings printed while compiling *dependencies* (e.g. Phoenix struct-update type
  warnings on 1.19) do not fail the build; only `==> bacon8` output matters.
- **Tests** need Postgres and nothing else. Since 2026-10-15 `runtime.exs` uses fixed
  dev/test secrets and the `*_test` databases when `MIX_ENV=test`:

  ```sh
  docker network create bacon8chk
  docker run -d --rm --name bacon8chk-pg --network bacon8chk -e POSTGRES_PASSWORD=postgres postgres:16
  docker run --rm --network bacon8chk -v "$PWD:/app" -v bacon8_deps:/app/deps -v bacon8_build:/app/_build \
    -w /app -e MIX_ENV=test -e DB_HOST=bacon8chk-pg elixir:1.19 \
    sh -c 'mix local.hex --force && mix local.rebar --force && mix deps.get && mix test'
  docker stop bacon8chk-pg && docker network rm bacon8chk
  ```
- **Before committing:** `mix compile --warnings-as-errors` and the test suite, in Docker as above.
  There is no CI; nothing checks a push after the fact.
  `mix lint` runs format, credo, sobelow and dialyzer.
- **Security-sensitive areas** (anything touching paths, uploads, auth, payments,
  webhooks, the games server key) get a second reviewer, human or tool, who did not write
  the change.
- **Deployment** is via the kustomize overlays in `k3s/`. `README.md` covers it; anything
  specific to one installation stays out of this repo. `deploy-prod.sh` backs up both
  databases before it touches anything, and on an empty install restores both.
- **Assistant tooling (MCP).** Three MCP servers run on the development PC, and a Claude
  session linked to it (Claude Code there, or a cloud session through the desktop app) uses
  them alongside a shell. They are development tools; nothing in the hub or a game depends
  on them.

  | Server | What it is | Used for |
  |---|---|---|
  | `unreal` | Epic's `ModelContextProtocol` editor plugin (HTTP on loopback port 8000, `.mcp.json` at the repo root) plus RaysSpaceSim's `UnrealMCPPython`, which adds `run_python` (Python inside the running editor) | Editing the Unreal project; and, because it runs on Windows, launching Windows jobs (`subprocess` on a `.cmd`: Blender headless, Docker builds and tests). Tools run on the game thread with a 60 s budget: start long jobs in a thread and poll a log. RaysSpaceSim's `RAYSSPACESIM.md` has the details. |
  | `Blender` | The Blender Lab MCP extension in the interactive Blender 5.1 | Inspecting and editing scenes live (`execute_blender_code`, object summaries, screenshots, renders, API and manual search). The asset pipeline itself still runs headless (`blender -b --factory-startup` via `tmp/b8work/jobs/run_pipe.py`), so builds are repeatable. |
  | `MCP_DOCKER` | Docker's MCP gateway: a Playwright browser, fetch and more | Rendering the headless three.js harness (Bacon World's look checks) and other pages |

  The web game is where characters and assets are developed first (fast to change and
  check); the same B8 skeleton and assets then go to Unreal, Unity or Godot (decisions log,
  2026-10-20). `library/pipeline` builds both the web GLBs and the engine exports.
- **Brand assets**: replace a master in `brand/` (see its README), then regenerate every
  icon, favicon, manifest and splash in a throwaway container:

  ```sh
  docker run --rm -v "$PWD:/work" -w /work python:3.12-slim \
    sh -c "pip install -q pillow && python scripts/brand/build_brand_assets.py"
  ```

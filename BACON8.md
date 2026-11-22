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

Last substantive update: **2026-11-15**.

**Where things stand.** The dated change notes that used to open this file (2026-10-20 to 2026-10-29) were
removed on 2026-10-29: `git log` has them, and what is still true of each change lives in the section it
belongs to (the decisions log in §2, the subsystem sections, the invariants). To read the old text:
`git log -p --follow -- BACON8.md`. The most recent work, so you know where to look:

- **Front door and backgrounds.** The bacon-and-fork intro and the live game-status corner (`HomeLive`,
  `GameTicker`; §9 "Game status"). Backgrounds are SVG and CSS, not WebGL (`Components.Cosmos`).
- **Page builder.** Pages and posts are edited in place on a phone-first editor (`assets/js/page_builder/`,
  `docs/pages-blog-builder.md`). Pictures upload by HTTP (`POST /editor/media`).
- **Store.** A cart and numbered receipts; unfinished checkouts are settled (§8 "Baskets", "Unfinished checkouts").
- **Games platform.** Game cards with a kind (browser or download) and a page (§9). `GET /api/games/:slug/entitlements`
  reports a player's items and passes. `Bacon8.GameStatus` and the optional plugin callback `game_stats/0`.
- **Admin.** `/admin/audit` shows the audit log; below 768 px the admin sidebar is a drawer.
- **Plugins.** `bacon_store`, `bacon_world`, `chat_channels` (the forum, at `/chat`) and `feedback` (Suggestions &
  Bugs, with a queue that hands work to Claude; its README has the loop) ship with the hub. `rays_space_sim` is a
  private plugin with the Unreal project nested inside it (§4, §9).

**2026-11-03/04** (one long cloud session; uncommitted until Claude Code verifies it, see `handoff/`):

- **Trust and safety** (§15): a public report form at `/report` (including TAKE IT DOWN and DMCA requests), the
  admin queue at `/admin/moderation`, child-abuse and intimate-image reports hidden at once, evidence kept for a
  year, removed files' hashes refused on every upload path.
- **Phone notifications** (§16): Web Push. Everything that rings the bell also reaches the phones and browsers
  people turned on (Android; iPhone from the Home Screen). `/admin/notifications` sends announcements.
- **Plugins for sale** (§8 "Plugins for sale"): a store product per plugin, its downloads cut from git release
  branches `release/<plugin>/<version>` by `scripts/release/package_plugin.py`.
- **Bacon World's creatures** are data: camps, spawn rotation, rares, loot tables, live XP and loot events, on
  `/admin/bacon_world/bestiary` (`BACON_WORLD.md`, "Creatures, camps and loot").
- **Two new games**, private plugins with the engine project inside (§9 "Artillery and City Planner"):
  `artillery` (Godot 4.6; renamed Tears of Babylon and restarted 2026-11-07) and `city_planner` (Unity 6.3, scans hand-drawn floor plans into buildings, VR).
- **Rotating secrets** (§17): what each secret costs to change, how often, and
  `scripts/security/rotate-secrets.sh`.
- **Real visitor addresses** (§18): `Bacon8Web.ClientIP` reads the visitor's address once, from the ingress only;
  a Cloudflare Tunnel (`k3s/cloudflared/`) is what brings the real address past Docker Desktop.

**2026-11-15** (one cloud session, run and tested in Docker on the development PC through the editor's MCP;
uncommitted until the owner reads it, see `handoff/`):

- **An open door at sign-in, closed.** `GET /auth/login_success?user_id=<id>` signed the browser in as that
  account with nothing else asked: anyone who knew an account's id was that account. It now needs the sign-in
  page's own hand-off token for that user, a minute old at most (§6 invariant 20; decisions log).
- **Security debt paid** (§13): a new account's role can't come from the form; the scheduler's webhook secret
  travels in a header, not the URL; the tracked dev secrets were already only the `.example` files.
- **Tests for the security core** (§13): `Security`, `RateLimiter`, `Accounts.RateLimit`, `RateLimitPlug`,
  `Uploads`, sign-in and the session hand-off. Writing them found two more faults, both fixed: asking the
  limiter about a blocked identifier crashed it (and its restart forgot every count and block), and blocking
  or allowing what already was raised instead of answering.
- **Every game's definitions on the hub** (§9 "Shared content"): `Bacon8.GameContent`: zones, camps, creature
  types, loot tables, items, per game; an API, a loot roller, a history that undoes, and `/admin/content`.
  Bacon World's definitions are the same table now (`game_defs`); Tears of Babylon's zones and camps are on it
  and its game reads them.
- **Physics** (§9 "Shared physics"): Bacon World's ragdolls have hinged knees and elbows (box3d's revolute
  joint: `box3d.wasm` rebuilt) and placed pieces stand in its physics world; Tears of Babylon's guns, grenades
  and barrels wear placed pieces down through the hub.

**Next session, start here:**

1. The standing rules are in `plugins/bacon_world/BACON_WORLD.md` §6 and the owner's notes: build and test only in
   Docker; commit with explicit file lists; **the deploy builds from the working tree, so check `git status` for
   another session's uncommitted work before deploying**.
2. Known debt (§13) is ordered by how much it hurts; the first item is core code with no tests.
3. Plugin work has its own notebook: `BACON_WORLD.md` for Bacon World, `plugins/*/README.md` for the others,
   `plugins/rays_space_sim/unreal/RAYSSPACESIM.md` for the Unreal game.


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
15. [Trust and safety](#15-trust-and-safety)
16. [Phone and desktop notifications](#16-phone-and-desktop-notifications)
17. [Rotating secrets](#17-rotating-secrets)
18. [Real visitor addresses](#18-real-visitor-addresses)

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
| 2026-10-16 | **RaysSpaceSim becomes a private plugin**: a new private repository cloned into `plugins/rays_space_sim`. The hub ignores every plugin folder it doesn't ship. ~~The Unreal project stays its own repository at `/RaysSpaceSim/`.~~ (Moved 2026-10-29, see the last row of this section's 2026-10-29 entries.) | Owner's decision. The hub sees it exactly as it sees Web Lobby. |
| 2026-11-04 | **Bacon World becomes a private plugin to be sold on the store**, no longer in the public MIT hub: its own private repository (`Ray-Rios/Bacon_World`) in `plugins/bacon_world`, with its history kept (subtree split). The hub ignores the folder like `rays_space_sim`. Artillery and City Planner (renamed from Bacon Tanks and Bacon City) are private repositories too. | Owner's decision. Sold from release branches in its own repository (`scripts/release/package_plugin.py`). |
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
| 2026-10-20 | **Brand assets come from masters in `brand/`** (and the game's `plugins/rays_space_sim/unreal/Brand/`), turned into every icon, favicon, manifest and splash by `scripts/brand/build_brand_assets.py`. The masters are placeholders until the real artwork exists. The Phoenix favicon and the Start button image are gone. | One drop-in point for the artwork; and the old images were other companies' marks. |
| 2026-10-20 | **Brand:** ~~the logo is the "B8" monogram~~ (the icon became bacon, 2026-10-26, below; the wordmark "Bacon8" in the navbar is unchanged). The colours are blue `#247DF1`, cream `#E7F1FD` and near-black `#14100F`. The one-line description is "The kitchen sink." | Owner's decision. |
| 2026-10-26 | **The site icon is two strips of bacon at 45 degrees**, rendered in 3D: the favicon and app icons, the desktop's Start button and the navbar's Games link. On pages it sizzles and reacts to hovering like the Gem (`<b8-bacon>`). Supersedes the B8 monogram as the icon. | Owner's request. |
| 2026-10-20 | **All flagged third-party material is removed** and replaced with our own or CC0 work: synthesized sound effects and music (`scripts/audio/`), an original default avatar, no third-party fonts, and new character models (next row). The removed files wait in a gitignored holding folder until the owner deletes them. | Owner's decision; it was placeholder content. |
| 2026-10-20 | **Characters use our own skeleton, "B8 skeleton v1".** It has Unreal-style names, which Unreal's IK Retargeter, Unity's Humanoid and Godot's BoneMap all map. It has 3 spine bones, twist bones, breast and glute jiggle bones on every body, and `weapon_l`/`weapon_r` grip bones. Male and female share it. The bodies are Blender Studio's CC0 base meshes; the animations are Quaternius' CC0 Universal Animation Library, baked onto the skeleton. Built by the asset pipeline (`art/pipeline/Characters/B8Human`, originally in the game repository). | Owner's decision. Epic's skeleton and animations may only be used in Unreal, and the web, Unity and Godot versions must look the same as the Unreal game. |
| 2026-10-20 | **Legal pages are CMS pages:** `/pages/terms`, `privacy`, `refunds`, `copyright`, `contact`, `credits` and `gems`. They are seeded unpublished as placeholders to be reviewed with a lawyer, and the store's small print links to them. | Owner's decision. They can be edited in `/admin/pages` without a deploy. |
| 2026-10-20 | **Direction: a reusable core, with games and commerce as plugins** (ADR 0001, removed from the tree on 2026-10-24 and still in git: `git show 95aba50^:docs/adr/0001-core-and-plugins.md`). Web Lobby becomes **Bacon World** (`bacon_world`). The store, Gems and payments become **Bacon Store** (`bacon_store`). The games platform becomes a plugin later. The core becomes the starting point for other stand-alone sites. | Owner's decision. A site that sells nothing or runs no games shouldn't carry the code for them. |
| 2026-10-21 | **Web Lobby is renamed Bacon World** (`web_lobby` -> `bacon_world`), stored names included: the three `bacon_world_*` tables with their keys and indexes, the game row and the `plugin_states` row, by the plugin's own migrations. Plugins gain `previous_slugs/0`; old `/games/web_lobby/...` and `/admin/web_lobby/...` links answer 301. Ledger rows keep the slug they were written with. | ADR 0001, phase 1. A first-party game's name should say what it is; the redirect keeps old links and bookmarks working. |
| 2026-10-25 | **Glass: menus are frosted, palette swatches are glass, the colour follows the player.** Popups (the navbar user menu, the taskbar's start, audio, calendar and notification panels) use `.glass-menu` (`assets/css/app.css`): a tinted body ~~that is always 62-85% opaque~~ (2026-11-02, owner: the menus take the profile's glass opacity as set), a stronger blur, a sheen, a light edge and a fine grain, instead of the player's 15% `--glass-bg`, which left big panels nearly clear. The profile palette uses `.glass-swatch` (and `.glass-picker`) so no colour is a flat disc. The personal glass colour sets `--glass-menu-*` and, when the player has chosen one, `--bwg-*`, which Bacon World's windows read (unset: the game's own look). `glass_theme.ts` (live changes) and the inline script in `layouts/root.html.heex` (page load) do the same sums: keep them in step. | Owner's request. Menus read as clear against the frosted bars, and the profile colour never reached the game. |
| 2026-11-02 | **Menus follow the profile's glass opacity** (owner: "the opacity is still cranked up on the start menu and user's menu"). `--glass-menu-bg` takes the profile's opacity as it is (`glass_theme.ts` `setGlassExtras`, the inline script in `layouts/root.html.heex`); the tint is still darkened for readable text. Earlier the same day the bars stopped being backdrop roots so the menus' blur works (`#main-navbar`/`#taskbar` `::before`). | Owner's request. |
| 2026-10-25 | **The forum is a plugin, `chat_channels`**, mounted at `/chat` (nav link "Chat"). Games that build per channel `require` it (RaysSpaceSim does); the store treats it as optional. A notification says what it came from (`source_kind`, `source_id`) and where it goes (`metadata.path`), so the hub knows nothing about channels; pending invitations are listed on the Chat page and counted by a badge on the nav link. Supersedes ADR 0001's "the core keeps the forum and chat channels". | Owner's decision (and answers to the plan's open questions). The core should be accounts, content and the plugin framework; anything a site might not want is a plugin. |
| 2026-10-25 | **Pages and blog stay in the core**, are rebuilt to production grade (tests first), are written by admins, GMs and editors only, and keep the rows, columns and blocks model. | Owner's decision. |
| 2026-10-23 | **The asset pipeline moved out of the RaysSpaceSim repository** (first to `library/pipeline`; at `art/pipeline`, its own repository B8_Asset_Pipeline, since 2026-11-09), shared by every game; the v1 humans were deleted, their sources and the copies imported into Unreal. | Owner's decision. |
| 2026-10-23 | **Asset rule (all games): ours, CC0, or licensed for commercial use, credited, with the source files never redistributed.** Licensed source files live in the gitignored shared library `library/` (one licence table per kind, e.g. `library/substance/LICENSES.md`); only baked outputs ship, credited on `/pages/credits`. | Owner's decision. Widens "ours or CC0" on purpose so curated libraries (Substance materials) can be used, without ever publishing files we may only use. |
| 2026-10-21 | **Web pods wait for migrations.** An init container in `bacon8-web` runs `Bacon8.Release.await_migrations/0` and starts the app only when no migration is pending. | A deploy starts `db-init` and the web pods together, so new code could serve the old schema for a few seconds, or write rows a stored-name migration then has to merge (found during ADR 0001 phase 1). |
| 2026-10-21 | **The store is a plugin, `bacon_store`**, mounted at `/store`, with the plugin framework it needs (site, site_api and fixed routes, `requires/0`, hooks). Its tables and migrations keep their names and versions; its admin moves to `/admin/bacon_store`; Stripe's webhook gets `/api/store/webhooks/stripe`, with the old URL kept as a `fixed` route until the dashboard is switched. Phases 2 and 3 shipped in one deploy. | ADR 0001. Core stops knowing about money; the owner chose one deploy for both phases. |
| 2026-10-21 | **Plugin data hooks ask every installed plugin and fail safe** (a crash means keep the user's data, or delete no blobs). | Switching a plugin off must not let core delete what the plugin still owns. |
| 2026-10-21 | **The old webhook URL is dropped.** `/api/webhooks/payments/:provider` is no longer routed; Stripe's endpoint was created at `/api/store/webhooks/stripe`. Supersedes the `fixed` route in the row before last. | No Stripe endpoint had ever used the old URL, so there was nothing to keep working. |
| 2026-10-27 | **Suggestions & Bugs is a plugin, `feedback`**, at `/feedback`, opened from the start menu. Members only: guests (and anyone signed out, banned or inactive) see neither the icon nor the page. Members post (with screenshots) and vote; only admins edit others' items, approve, decline and submit. | Owner's request; a plugin because a site might not want it (2026-10-25). |
| 2026-10-27 | **Approved suggestions reach Claude by a runner on the development PC that collects them** (the site keeps the queue; nothing can push into a Claude conversation). One item at a time; the runner's token can only read submitted items and report on them, and Claude never sees it. Not GitHub issues: the hub repository is public, so members' reports and screenshots would be public, and the private plugins aren't in it. | Owner's choice of the options offered. The PC already has the code, the private plugins, Docker and the deploy script. |
| 2026-10-27 | **Feedback fixes may deploy without the owner pressing anything**, when the owner turns on "Deploy on its own" (off by default) on `/admin/feedback/agent`, and only for a change that passed the runner's own test run and a second Claude's review and touches nothing security-sensitive (sign-in, permissions, uploads, storage, payments, webhooks, the router, deploy files, production config, dependencies, secrets, data-dropping migrations, the runner). Everything else waits for an admin's Deploy. Turning the switch on is the owner saying "deploy"; with it off, the rule that deploys happen only when the owner says stands as before. | Owner's decision ("automatic after tests"), with the holds added so a member's text can't steer a sensitive change into production unreviewed. |
| 2026-10-29 | **The front page shows the games' live status** (lower left, one game at a time). Games report it through an optional `game_stats/0`; without one the hub measures what it already knows (server heartbeats, characters). | Owner's request. Visitors see the platform is alive before signing up; the hub never asks a game server for anything. |
| 2026-10-29 | **A buyer has one open card checkout at a time, open for 31 minutes; an unpaid checkout is not a purchase.** Starting another, Cancel, the provider's cancel link or the time running out closes it at the provider; the provider is asked first, so a payment is delivered, never cancelled. Purchases lists only paid orders; admins see open and abandoned checkouts in their own views. | Owner's report: Back from Stripe left "Pending" orders in his purchase history, and Buy ignored the cart. |
| 2026-10-29 | **The one refund there is: a duplicate payment.** Sales stay final, but money taken for something the buyer already owned is flagged for the owner to refund in Stripe (the hub never refunds by itself). | Two checkouts paid at once is the provider's money for nothing; a chargeback would follow. Rare now that only one checkout is open. |
| 2026-10-29 | **A game that needs a download has its own page**, an ordinary CMS page picked on the game's admin section; its card on /games opens it. In-browser games open the game. | Owner's request: RaysSpaceSim (a download) needs an editable page; Bacon World plays in the browser. |
| 2026-10-29 | **The Unreal project lives inside its plugin**, at `plugins/rays_space_sim/unreal/` (its own nested git; it was `/RaysSpaceSim/` beside `plugins/`). One game, one folder, one name. Scripts find it through the plugin's own location, not the hub root. | Owner's request: two folders with the same name was confusing. |
| 2026-10-29 | **The store sells several items in one purchase** (a cart; one receipt with one order number). Each item stays its own order underneath. | Owner's request: the front page shows a multi-item order, and the store only sold one item at a time. |
| 2026-10-28 | **Site backgrounds are SVG and CSS, never WebGL.** Six cosmic kinds (`Cosmos.kinds/0`) built from drifting SVG star tiles, gradients and CSS 3D transforms; only transform and opacity animate. | Owner's request: the three.js scenes made phones lag on every page. A game page that wants 3D draws its own. |
| 2026-10-27 | **Behind Docker Desktop every visitor's address is the node's own, `192.168.65.3`** (the Kubernetes node's InternalIP; Docker's port forwarding replaces the client address before nginx sees it, and the ingress adds no real-IP header). It names no one, so `Bacon8.Security.blockable_ip?/1` refuses to block private, loopback and link-local addresses (the Block buttons, the honeypot, the suspicious-request plug, and the blocker plug all check it), and sign-ins are throttled by the account (`Security.throttle_key/2`) when the address names no one. Other per-address limits (registration 5 per address, the API's 200 a minute, `auth_login` 5 per 5 minutes in the router) are still shared by all visitors ~~until real addresses are passed on~~ (2026-11-04: until the Cloudflare Tunnel is set up, §18). | Found from the security page, which showed internet scanners (`/blog/.env`, `wp-config.php`) as one internal address: it is not a compromised container. A shared address meant one scanner's probes, or five wrong passwords, could block or lock out every member. Real addresses need a proxy in front that passes them on (the owner's call). |
| 2026-11-03 | **Illegal content: hide first, keep evidence, report, then ban.** Reports of child sexual abuse material, child exploitation or intimate images shared without consent hide the thing at once, from everyone including staff; staff keep the evidence (a year, outside the drive's garbage collector) before removing, report child abuse to NCMEC themselves (the hub records the report number), and only then ban. Removed files' SHA-256s are refused on every upload path. The admin queue never shows a child-abuse report's content. Matching altered copies is left to PhotoDNA or Cloudflare's CSAM Scanning Tool (owner's sign-up). | US law (18 U.S.C. §2258A as amended by the REPORT Act; the TAKE IT DOWN Act's 48-hour removal from 2026-05-19) and the owner's question "how will we handle illegal content". §15. |
| 2026-11-03 | **Phone notifications are Web Push first, not an app.** The installable site plus Web Push reaches Android browsers and iPhones (iOS 16.4+, from the Home Screen) with no store accounts, review or Firebase; a native wrapper only if store presence is wanted. The push worker is `/push/sw.js` with the scope `/push/`, never `/`, where Bacon World's game worker is. Only push services' own hosts are ever called. | Owner: "/chat may need an android/iphone app for notifications". §16. |
| 2026-11-03 | **Plugins are sold from git release branches.** `release/<plugin>/<version>`, never moved; `scripts/release/package_plugin.py` archives the plugin as committed on that branch (never the working tree), refuses secret-looking files and adds `RELEASE.json`; the store recognises such a zip and records the release (branch, commit). One plugin per product; a release can be withdrawn without deleting buyers' past downloads. | Owner: "associate downloadable plugins to release branches". §8. |
| 2026-11-03 | **New game plugins are private by default, with the engine project inside** (`plugins/artillery/godot`, `plugins/city_planner/unity`), as RaysSpaceSim's Unreal project is. The hub's `.gitignore` hides them until the owner decides: their own repository, or listed to ship with the hub. | Same rule as 2026-10-29 (one game, one folder); keeps sellable games out of the public repo until decided. |
| 2026-11-04 | **Real visitor addresses come through a Cloudflare Tunnel, and the hub reads them in one place.** `Bacon8Web.ClientIP` (first plug in the endpoint) sets `conn.remote_ip` from `X-Real-IP`, else the rightmost untrusted `X-Forwarded-For` hop, only when the connection comes from a private address (the ingress); everything else reads `conn.remote_ip`. Before, five plugs each took the *first* `X-Forwarded-For` entry, which any visitor can write. ingress-nginx believes `CF-Connecting-IP` only from the tunnel pods' range (`k3s/cloudflared/`). | Owner: "/admin/security ... shows all attacks coming through as a docker desktop address". Docker Desktop's port forward drops the address and no cluster setting restores it; a tunnel dials out, so the address arrives in a header from Cloudflare. Also hides the home address and closes the router's ports. §18. |
| 2026-11-04 | **Secrets are rotated by one script, on a schedule and after any exposure.** `scripts/security/rotate-secrets.sh` (backup, generate, apply, restart; DB password changed in Postgres first); providers' keys (Stripe, SMTP) are typed in, never on the command line. | Owner asked for a rotation strategy after a cloud copy of the secrets files (deleted unread, 2026-11-04). §17. |
| 2026-11-07 | **Artillery starts over in Godot only** (owner: "barely functional garbage"). Gemini's uncommitted work was deleted: a Three.js browser client borrowing Bacon World's characters, chat-channel lobbies, a Kubernetes launcher and ~30 scripts building everything in code. The new game: a third-person soldier who climbs into vehicles, a co-op campaign and player-hosted PvP arenas, Godot 4.7.2 Forward+ and GDScript, scenes and Blender/CC0 art instead of shapes made in code, sign-in through a launcher. `plugins/artillery/ARTILLERY.md` is its notebook. | A browser client and a Godot client had grown into two different games, and the Compatibility renderer with code-built models can't look realistic. |
| 2026-11-07 | **Artillery is renamed Tears of Babylon** (`tears_of_babylon`), stored names included: its matches table and indexes, the game row, the `plugin_states` row and a saved game card, by the plugin's own migrations (`20261107120000`, `20261107120100`); `/games/artillery/...` and `/admin/artillery/...` answer 301 (`previous_slugs/0`). The owner's direction the same night: futuristic, 80s-punk soldiers against every kind of creature; a tank and a helicopter first, with separate driver and gunner seats (in PvP, one of each per team per round); characters share Bacon World's appearance data; player-hosted games reached over WebRTC; Terrain3D for World Creator maps; PvP for fun, unranked; a launcher of its own. `plugins/tears_of_babylon/TEARS_OF_BABYLON.md`. | Owner: "Artillery isn't what I was thinking it would be." |
| 2026-11-10 | **Every game's character creator works the same.** The camera: left-drag turns around the character and tilts the view, right- or middle-drag pans, the wheel zooms, and the framing buttons or tabs put it back (Bacon World `character-stage.ts`, Tears of Babylon `character_stage.gd`, RaysSpaceSim `B8Creator.cpp`). Every select screen can edit a saved character's look and save it. No face presets. The look's data (`appearance.ts` / `.ex` / `.gd`, RaysSpaceSim's `FB8Look`) is shared. | Owner: "I need the character creator on all systems to be nearly identical, functionally all the same"; presets removed at the owner's request. |
| 2026-11-04 | **City Planner scans drawings in the game, not on the hub.** The scanner is plain C# inside the Unity project (tested with .NET outside Unity); the hub only stores the photos (as drive files, under moderation) and the plans. | Works offline and on a headset; no image-processing service to run and secure on the hub. |
| 2026-11-15 | **The browser's session is set only by the sign-in page's hand-off** (§6 invariant 20): `/auth/login_success` needs a token `AuthLive` signs for that user, 60 seconds long, and gives the session a new id. | It believed the `user_id` in its URL: anyone could sign in as any account whose id they knew. Found reading the sign-in code to write its tests. |
| 2026-11-15 | **A scheduler webhook's secret goes in a header** (`X-Webhook-Secret`), never the URL; the old URL answers 410. | Request lines are logged by the app and the ingress; parameter filtering doesn't reach a path. |
| 2026-11-15 | **Every game's definitions are one hub service, `Bacon8.GameContent`** (§9 "Shared content"): Bacon World's `bacon_world_defs` becomes `game_defs` with a game slug; Tears of Babylon's zones and camps live there. Bacon World's Studio keeps editing its own rows; the hub's editor is plain JSON for every other game. | Owner: "Move camps, loot and item definitions to the hub, as you did with building." The Studio's pages and Bacon World's item table stay where they are for now: they are tied to that game's models, and moving them is its own piece of work. |
| 2026-11-09 | **No browser pop-ups: the site has its own confirm, alert and prompt** (`assets/js/b8_dialog.ts`, `assets/css/b8_dialog.css`). One glass dialog that eases in, centred in the upper third of the window, with the profile's glass colour, opacity and blur (`.glass-menu`, `--glass-rgb`). Every `data-confirm` goes through it with no template change (a capture-phase click listener, imported before `phoenix_html` in `app.ts`, holds the click and replays it with the attribute lifted); optional `data-confirm-title`, `-ok`, `-cancel`, `-tone`. Script calls `await b8Confirm(...)` / `b8Prompt(...)` / `b8Alert(...)` (plugins import it like the vendor shims, or use `window.B8Dialog`); `window.alert` is redirected to it. Destructive wording turns OK red and focus starts on Cancel; Esc cancels; while it is open it takes the keyboard and releases pointer lock, so Bacon World doesn't react underneath. Never call `window.confirm`/`prompt` again: they can't be restyled. | Owner: the browser's "bacon8.net says" box showed up across the site and in Bacon World when deleting items. |
| 2026-11-18 | **The creators' Face tab has a Mouth section in every game**, Black Desert's: Smile, Corners, Width, Height, Forward, Fullness, Upper lip, Lower lip, Overbite, Cupid's bow (look keys `mouth_*`, `lip_*`; 17 morphs made on every body by the art pipeline's `gltf/face_mouth.mjs`). The v2 female's face keys were rebuilt at the v1's strength. | Owner: "there isn't even a way to make the character smile"; "none of the facial morphs seem to be effecting the v2 Female". |
| 2026-11-18 | **City Planner is a stand-alone game: no Bacon8 sign-in**, with the shared character creator; its characters are kept on the player's computer. Its hub side (drawings, plans, cities) is no longer used by the game; whether it goes is the owner's call. | Owner: "it will not need Bacon8.net login, it can be a stand-alone game. It will still need the character creator though." |
| 2026-11-18 | **Faces as free as Black Desert's**: every face and eye slider goes both ways, more of them (the eyes 7 to 15, a Brow group; cheeks, jaw, chin, nose and ears next), clearer names; made by the art pipeline's process (README, "How a face key is made"). (The owner: "give the players as much customizable freedom as possible!!") |
| 2026-11-19 | **City Planner is called City Builder** wherever a player sees it: the Unity project (`productName`), the hub's game card, pages and admin menu, the drive folder new drawings go into. The code, the plugin slug `city_planner`, its tables and its repository keep the old name (§5). **And the disk layout review** (`handoff/CLAUDE_CODE_PROMPT_2026-11-19_cleanup_and_update.md`): the owner takes all of its proposals; `art/models` for masters first (`art/README.md`). |
| 2026-11-19 | **City Builder is rewritten as a building tour** (the owner: "the whole game needs to be re-written"): pick or import a blueprint (pictures and PDFs first), it is built in 3D, and you walk through it as your own character in third person, first person, a PC VR headset and on a Quest, all four in the first playable version; the city simulation is dropped; the samples are a licence-checked public-domain / CC0 set plus the owner's own plans. | The first version was a city simulation with the character nowhere in it. `plugins/city_planner/CITY_BUILDER.md` §1, §3 and §6 have the design, the technical choices (URP, OpenXR, UI Toolkit, PDFium) and the phases. |
| 2026-11-21 | **City Planner is City Builder in code too**, stored names included (the owner renamed the folder and the repository): Elixir `CityBuilder*`, slug `city_builder` (`previous_slugs: ["city_planner"]`: old links answer 301), tables `city_builder_*` and the game row by `20261121120000_rename_city_planner_to_city_builder`, the plugin state and saved card by `20261121120100`; C# namespaces and assemblies `CityBuilder.*`; the art build writes to `plugins/city_builder/unity`. Supersedes the 2026-11-19 row's "the code, the slug, its tables and its repository keep the old name". | Owner: "I've renamed city_planner folder and github repo to city_builder ... make sure city_planner is properly renamed everywhere". With only the folder renamed, plugin discovery (`lib/<folder>/plugin.ex`) skipped the plugin. |

---

## 3. Architecture

```
                 ┌──────────────────────────── Bacon8Web ──────────────────────────────┐
 browser ──────▶ │ Endpoint ─ UploadsGuard ─ Plug.Static ─ Session ─ Router            │
                 │   LiveViews (pages, admin, and the plugins': store, chat, games)                     │
                 │   DesktopLive (global live_component on authed pages)               │
                 │   Channels (chat, presence)                                         │
 game client ──▶ │   /api/auth/*  /api/games/:slug/*  (JSON, Guardian bearer)          │
 game server ──▶ │   /api/games/:slug/*  with X-API-Key (server key)                   │
                 └───────────────────────────────┬─────────────────────────────────────┘
                                                 │
                 ┌──────────────────────────── Bacon8 (contexts) ──────────────────────┐
                 │ Accounts  Security  Content  Files  Scheduler  Settings             │
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

- **Browser:** the signed session cookie holds the user's id (`user_id`), read by `Bacon8Web.Auth`
  (plug) and `Bacon8Web.UserAuth` (LiveView `on_mount`, which also turns away banned and inactive
  accounts on every mount). It is set in one place: `AuthController.login_success`, which the
  sign-in page (`AuthLive`, a LiveView, which can't write a cookie) sends the browser to with a
  hand-off token it signed for that user (invariant 20). (This file said "a session token" until
  2026-11-15. `Accounts.generate_user_session_token/1`, `get_user_by_session_token/1` and
  `delete_user_session_token/1` are stubs that keep nothing: §13.)
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
assets/                    esbuild + tailwind; SVG/CSS cosmos backgrounds (cosmos.css); vendor/ shims for plugins
plugins/                   installed plugins, one folder each (§9); bacon_world/ (a game) and bacon_store/ (a site plugin) are the examples
art/                       gitignored: everything art is made from and with
  pipeline/                the Bacon8 asset pipeline (Blender scripts, B8 skeleton and human blends, animation sources; `scripts/`, `Characters/`, `Animations/`, `gltf/`, `out/`): its own repository (B8_Asset_Pipeline). It left the RaysSpaceSim project on 2026-10-23 for `library/pipeline` and has been here since 2026-11-09
  source/                  sources never redistributed: MakeHuman's CC0 data, licensed textures and Substance files, World Creator maps, each kind with its LICENSES.md (2026-11-19: also music and lace photos)
  models/                  THE MASTERS, the only models anyone edits (2026-11-19): plain .glb files for every body, animation pack, garment, hair style (`Hair/<Body>/`), mob, world piece and weapon, plus the v2's blends and the fabrics; `build.cmd` writes the web pack (`priv/static/models`), the engine sets and every game's copy from them. No Git LFS history: backed up locally (`art/README.md` has the rules)
  build/                   what build.mjs makes for each engine (remade by the next build)
  snapshots/               copies of masters taken before a risky change, `<date>_<topic>` (was work/backup_models)
  work/                    scratch: anything here may be deleted
library                    a link on the development PC to the licensed source library (older notes say `library/...` for what is now under `art/`)
k3s/                       kustomize base + overlays (dev, prod)
config/runtime.exs         all deploy-time configuration via env vars
```

**Not part of the hub:** any plugin folder other than `plugins/bacon_world`, `plugins/bacon_store`, `plugins/chat_channels` and `plugins/feedback` (gitignored; a
private plugin is its own repository). RaysSpaceSim's deploy and build scripts, k8s manifests,
code map, mix task and admin pages are in its private plugin (2026-10-16), and so is the Unreal
project itself: `plugins/rays_space_sim/unreal/` is a second, nested git repository (2026-10-29).
The plugin's `.gitignore` and the root `.dockerignore` (`plugins/*/unreal`) keep it out of both.

**What on disk is kept and what is disposable (2026-11-19 cleanup; the owner asked for one).** Kept: the repositories
(hub, `art/pipeline`, each plugin, `plugins/rays_space_sim/unreal`), `art/source`, `backups/` (the nightly database
dumps: production data, never read by an assistant; `scripts/backup.ps1` keeps the newest 14 of each here, after copying every one to `D:\Backups`), `uploads/`. Regenerable: `art/build` (build.mjs), the web models (`priv/static/models`, packed from `art/models`), the games' copies
of the models, `art/pipeline/out`. Tracked tools: `tools/win/` (the launchers the scheduled tasks run, `paths.cmd`, `README.md`; moved out of `tmp/` 2026-11-19). Disposable: `tmp/` (logs, status files, the per-run `*_args.txt`, renders); the grown hair, which used to live there, is in `art/work/hair` (trials) and `art/models/Hair` (installed). Model snapshots (`art/snapshots/<date>_<topic>`): the masters (`art/models`) are
not in any repository (no LFS, by the owner's choice), so these and the nightly `D:\Backups` copy are their only history; keep the last few days' and anything the notebooks still point
at. Anything to be thrown away is moved to `_to_delete/<date>/<its old path>` (a `MANIFEST.txt` lists it), never
deleted by an assistant; `tools\win\cleanup.cmd` empties `_to_delete` when the owner runs it. Both `.gitignore` and
`.dockerignore` leave `_to_delete` out, and `.dockerignore` now also leaves out `plugins/*/unity` (City Builder's Unity
project would otherwise go into the web image with `COPY plugins`). The 2026-11-19 sweep moved ~11 GB (old shots,
superseded garment and hair experiments, the rejected hair pass 5, model snapshots from 11-01 to 11-15).
`handoff/CLAUDE_CODE_PROMPT_2026-11-19_cleanup_and_update.md` has the review of the layout and what is left to do;
`docs/UPDATING.md` is how to bring the hub and every game up to date.

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
| City Builder's slug `city_builder` (`city_planner` until 2026-11-21: renamed with migrations `20261121120000` and `20261121120100`, `previous_slugs` answering 301) | the plugin folder and `lib/city_builder/plugin.ex` (discovery needs both to match: a folder renamed without the code makes the hub skip the plugin), `slug:`, `/games/city_builder` and `/admin/city_builder`, the games database's `city_builder_*` tables, the GitHub repository City_Builder | Links and bookmarks break; the tables need a migration; the plugin is found under a new id, so its active state and any store entitlement keyed on the slug are lost unless migrated. |

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

   **SafePath confines; it does not decide ownership.** `Uploads.delete_file/1` deletes anything
   under uploads/ except the drive's blobs, so a URL or path that came from a browser, or from a
   column a form can set, must first be checked against what that user may touch: compare it with
   the user's own listing (`ProfileLive.own_avatar?/2`), or match the exact folder it must be in
   (`ChatChannels.Channel.icon_path?/2`, `Content.InlineMedia.remove/2`). Never cast a stored file
   path from form params. Until 2026-10-25 any member could delete others' uploads through the
   avatar buttons, and a channel's icon path came from the create form.

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
   sessions. **Any XML type can run script**, not only SVG: `.rss` and `.atom` were served
   inline as feed XML until 2026-10-25. The list is a denylist; when the MIME library learns a
   new XML or HTML type, add its extension (`safe_path_test.exs` checks the list).

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

18. **A page must notice a deploy itself.** LiveView reconnects an open tab to new code but keeps
    the old JavaScript, so every root LiveView mounts `Bacon8Web.StaticReload` (through
    `use Bacon8Web, :live_view`), which reloads when `static_changed?/1` says the tracked assets
    (`phx-track-static` on `app.js` and `app.css` in the root layout) changed. Keep those
    attributes, and don't give unversioned static files a long cache: the `/` `Plug.Static` keeps
    them an hour (`cache_control_for_etags`). Before 2026-10-26 it was a year, and Bacon World's
    players had to hard-refresh after every deploy.

19. **The visitor's address is `conn.remote_ip`, set once by `Bacon8Web.ClientIP`.** Never read
    `x-forwarded-for` or `x-real-ip` yourself: the first `X-Forwarded-For` entry is whatever the
    visitor typed. `ClientIP` believes those headers only from a trusted (private) peer, i.e.
    the ingress; LiveViews use `Bacon8Web.ClientIP.from_socket/1` (connect info `:peer_data` and
    `:x_headers`). Keep the plug first in the endpoint, before anything logs or limits by address,
    and never add Docker Desktop's `192.168.65.0/24` to ingress-nginx's `proxy-real-ip-cidr` (§18).

20. **Only the sign-in page's hand-off sets the browser's session.** `GET /auth/login_success` signs the
    browser in as `user_id` only with `handoff`, a `Phoenix.Token` that `AuthLive` signs for that user
    after `Accounts.authenticate_user_secure/3` has passed (`AuthController.handoff_token/1`, salt
    "login handoff", good for 60 seconds), and gives the session a new id. Until 2026-11-15 it
    believed the `user_id` in the URL by itself: any account, admins included, for the price of
    knowing its id, which pages and API answers show. Any other code that wants to sign a browser in
    goes through the same hand-off; never `put_session(:user_id, ...)` from a value a request
    supplied. Tests: `test/bacon8_web/controllers/auth_controller_test.exs`.

---

## 7. User storage and the file explorer

Each user's drive (`user_files`, `user_folders`, files under `uploads/users/<id>/`) and the desktop File Explorer that works on it. Deployed 2026-10-15; the legacy import found nothing to move. The design, the explorer and the import are in the full text.

Full text: [docs/storage.md](docs/storage.md).

## 8. Store, payments, currency and entitlements

The store is the `bacon_store` plugin (since 2026-10-21; mounted at `/store`). Its tables keep their `store_*` / `wallet_*` / `payment_events` names, a documented exception to the `<slug>_` prefix. The full text covers payments, currency, entitlements, plugins for sale (2026-11-03) and the milestone-4 target model.

Full text: [docs/store.md](docs/store.md).

## 9. Games platform and plugins

What stays in the hub for games (the game and character registry, server heartbeats and commands, releases and the launcher, session claims, entitlements), what moved to each game's own plugin, the plugin system (milestone 2), and the plugins: Bacon World (the template), Tears of Babylon, City Planner/Builder, and the shared services for physics, building and content. Read the full text before adding a plugin or a hub-side game service.

Full text: [docs/games-platform.md](docs/games-platform.md).

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

**Since 2026-10-27** plugins' apps are in the start menu's grid: `desktop_apps/1` takes the user
(nil when signed out) and returns `%{label, path, icon}` maps, each opened by navigating to its
path. A plugin leaves out what the user may not open (Suggestions & Bugs gives guests nothing). The
`%Bacon8.Desktop.App{}` struct above is still the target.

---

## 11. Chat channels and VIP channels

Channels live in the `chat_channels` plugin (`plugins/chat_channels`, module `ChatChannels`;
tables `chat_channels`, `channel_members`, `chat_messages`,
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
| 12 | **Trust and safety live** (§15) | The owner's steps in §15 are done: NCMEC registration, DMCA agent, policy pages and a footer link to `/report`, a hash-matching service, a minimum age. |
| 13 | **Notifications on phones** (§16) | VAPID keys set; tried on an Android phone and an iPhone from the Home Screen. A native app only if store presence is wanted. |
| 14 | **Plugins for sale** (§8) | The first release branches cut and packaged; products priced and published. |
| 15 | **Tears of Babylon and City Planner played** (§9) | A Windows build of each that a person has played, card pictures, download pages; City Planner compiled and tried in Unity and on a headset. |

---

## 13. Known debt

Ordered roughly by how much it hurts.

- **Browser sessions can't be taken back** (found 2026-11-15 while testing them). The cookie holds the
  user's id and nothing the server could revoke: `Accounts.generate_user_session_token/1`,
  `get_user_by_session_token/1` and `delete_user_session_token/1` are stubs (`Accounts.UserToken` and its
  table exist, unused), and `Bacon8.UserSession` is an agent nothing reads. So "sign out everywhere", ending
  sessions on a password change, and ending a stolen cookie before it expires aren't possible; a ban works only
  because `UserAuth` re-reads the account on every mount. Making the stubs real (a token row per session,
  checked on each request) signs everyone out once: the owner's call on when.
- **Wrong passwords never lock an account** (found 2026-11-15). `authenticate_user_secure/3` refuses an
  account whose `locked_until` is in the future, but nothing sets it: failures are counted per address (or
  per account behind the gateway address) by the rate limiters only. Decide: lock after N failures, or drop
  the field.
- **Two routes lead nowhere**: `POST /auth/2fa/verify` and `/auth/2fa/setup` name `AuthController` actions
  that don't exist (a 500 for whoever posts there). Remove them or build 2FA.
- **Much of the core still has no tests.** Found 2026-10-25 by module name (indirect cover may
  exist): ~~`Security`, `RateLimiter`, `Uploads`~~ (tested since 2026-11-15, with `Accounts.RateLimit`, the
  API's rate-limit plug, sign-in and the session hand-off), `UserFileUpload`,
  `UserSession` (unused, above), ~~`Moderation`~~ (tested since 2026-11-03), `Email`, `Mailer`, `Calendar`, `Desktop`,
  `Avatar`, `Storage` and the media code. There are no LiveView tests for the profile, the admin
  dashboard, user management or the SQL console. Covered so far: the forum (now the plugin), pages
  and blog (the context, the public pages, both admin pages, the inline media), `SafePath`,
  notifications. Security-sensitive areas (§14) deserve tests before they are touched.
- **Unverified since 2026-11-04** (built in the cloud, tested only there): the Unity scripts of `city_planner`
  (never compiled: no Unity in the cloud), Web Push on real phones, Tears of Babylon played by a person. And no
  hash matching beyond exact SHA-256 yet (§15).
- `ChatLive` (the `chat_channels` plugin) is ~2,050 lines of handlers; splitting them by feature is optional.
  The store's own channel-pass tests need chat installed.
- **RaysSpaceSim's settings still live in the hub's prod configmap** (`HOLOSIM_*`,
  `WORLD_*`, and `deploy-game.sh` writes `HOLOSIM_IMAGE` there), so a game deploy edits a
  hub file. Move them to a configmap the plugin's `k3s/` owns and have the hub deployment
  read it with `envFrom` (`optional: true`).
- **Old third-party files may still sit in production's volumes.** The repository stopped serving third-party
  material on 2026-10-20 (original sounds, music and default avatar; no third-party fonts; CC0-based characters).
  Still to do in production: delete the old files from the uploads and models volumes and sync the new models.
- **The legal pages are unpublished drafts.** Publish them from `/admin/pages` after the
  lawyer's review, and before the store takes live payments.
- **Game releases are Development builds**: the console works for players and the window
  title carries debug info. Ship Shipping builds (`CLIENT_CONFIG=Shipping`).
- A few core comments still mention RaysSpaceSim as history. Harmless; don't add new ones.
- **`Bacon8.LogBufferBackend` is a legacy `:gen_event` Logger backend**, deprecated since
  Elixir 1.15. It works (and now normalises the `:warn` level it is still handed), but should
  become an Erlang `:logger` handler.
- **Forum attachments are public by URL** (§7), which blocks VIP channels.
- **`UploadsGuard` decides inline or download with a denylist** (`SafePath.active_content?/1`,
  invariant 4). An allowlist of types safe to show inline (pictures, video, audio, PDF), with
  everything else sent as a sandboxed download the way the drive's `Sniff` works, would not need
  updating when browsers or the MIME library learn a new type. Found in the 2026-10-25 review.
- ~~`User.registration_changeset/2` casts `:role` and `:is_admin`.~~ Done 2026-11-15: neither is cast;
  the caller passes `role:` as an option (`registration_changeset/3`), `is_admin` follows it, and anything
  else is a member. `register_user/2` passes the first-user and default roles that way.
- ~~`POST /api/webhooks/scheduler/:secret` carries its secret in the URL.~~ Done 2026-11-15:
  `POST /api/webhooks/scheduler` with the secret in `X-Webhook-Secret` (or `Authorization: Bearer`); the
  old URL answers 410 and runs nothing. **Anything outside that calls a scheduler webhook must move its
  secret to the header**, and a secret that was ever in a URL is in old logs: make the event a new one.
- Bacon World's own follow-ups (creature collisions, server-side walls, remote crouch, the
  skill tree, `.glb.gz` upkeep, TypeScript errors) are tracked in `BACON_WORLD.md` §7.
- `desktop_live.ex` is ~2,000 lines; the explorer, uploads, calendar and audio
  should become separate app components (milestone 5).
- ~~Tracked dev secrets in `k3s/overlays/dev/secrets.yaml` should all be obvious placeholders.~~ Checked
  2026-11-15: that file is gitignored and not in this repository's history (it began fresh on 2026-10-17);
  what is tracked is `secrets.example.yaml`, all placeholders. Values that were in the old repository's
  history are still worth rotating (§17).

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
  2026-10-20). `art/pipeline` builds both the web GLBs and the engine exports.
- **Brand assets**: replace a master in `brand/` (see its README), then regenerate every
  icon, favicon, manifest and splash in a throwaway container:

  ```sh
  docker run --rm -v "$PWD:/work" -w /work python:3.12-slim \
    sh -c "pip install -q pillow && python scripts/brand/build_brand_assets.py"
  ```

---

## 15. Trust and safety

The engineering side of handling illegal and abusive content (built 2026-11-03): what the law asks of a US site, how reports and takedowns work, what is preserved. Not legal advice; the owner's lawyer has the last word.

Full text: [docs/trust-and-safety.md](docs/trust-and-safety.md).

## 16. Phone and desktop notifications

Web push for every notification (`Bacon8.Push`, `Bacon8.Push.WebPush`, `push_opt_in.ts`), turned on per device and with an option to hide the message text on a lock screen (built 2026-11-03).

Full text: [docs/notifications.md](docs/notifications.md).

## 17. Rotating secrets

When and how to rotate each group of secrets, with the commands (written 2026-11-04). No secret's value is in the file or the repo; the secrets files are gitignored (§6).

Full text: [docs/secrets-rotation.md](docs/secrets-rotation.md).

## 18. Real visitor addresses

Why every visitor showed up as Docker Desktop's `192.168.65.3` (it proxies each connection into its VM) and the two-part fix made in the hub on 2026-11-04.

Full text: [docs/visitor-addresses.md](docs/visitor-addresses.md).

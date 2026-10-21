# ADR 0001: A reusable core, with the store and the games as plugins

- **Status:** Accepted (direction), 2026-10-20. **Phase 1 done 2026-10-21** (Web Lobby is
  Bacon World); phases 2-5 are planned.
- **Deciders:** the owner.
- **Supersedes:** nothing. Extends the plugin system in BACON8.md §9.

## Context

Bacon8 started as one community site with games. Three things changed on 2026-10-20:

1. **The Web Lobby is growing into a game of its own.** It is getting proper characters,
   CC0 animation libraries, weapons, combat and a character creator. Its name should say
   so, and its code should be the template for every game.
2. **The store should be a plugin, the way WooCommerce is for WordPress.** A site that
   sells nothing should not carry Gems, payments and a ledger.
3. **The owner wants to start other, simpler stand-alone sites from the same core.**
   Today the core assumes a games platform (a second database) and a store. A plain
   community or company site needs neither.

The plugin system (BACON8.md §9) already gives plugins their own namespace, tables,
routes, admin pages, desktop apps, supervised children, entitlement kinds and hub
events, with activation from `/admin/plugins`. It has four limits:

- It only mounts **game-style** routes: `/games/<slug>`, `/api/games/<slug>` and
  `/admin/<slug>`.
- Core still **calls into the store directly**:
  - `Accounts.delete_user/1` checks orders, wallet and license keys to decide whether to
    anonymise;
  - `Drive.gc_blobs/2` keeps product file bodies;
  - `Application` starts `Store.Sweeper`;
  - navigation and the taskbar link `/store`;
  - the API toolbox lists orders;
  - the endpoint's raw-body reader exists for payment webhooks.
- Plugins **can't depend on each other**: Bacon World needs the games platform, and
  RaysSpaceSim needs the games platform and, later, the store.
- **Site identity is partly code.** The session cookie name is in `endpoint.ex`; brand
  and colours live in `brand/` (`brand.json`).

## Decision

**Core** is what every site needs:

- accounts and security;
- content (pages, blog), the forum and chat channels;
- the drive;
- notifications and email;
- the desktop shell;
- the admin area;
- entitlements (the generic "has access to X" check);
- settings and brand;
- the plugin framework.

Everything else is a plugin:

| Plugin (slug) | Was | Contains |
|---|---|---|
| `bacon_world` | `web_lobby` | the browser game: characters, zones, combat, three.js client |
| `bacon_store` | core `Store`, `Wallet`, `Payments` | products, checkout, Gems ledger, payment providers and webhooks, library, sweeper, store admin |
| `bacon_games` (later) | core `Games` + `GamesRepo` | games platform: characters, servers, releases, launcher, platform API (games database) |
| `rays_space_sim` | (private, unchanged) | the Unreal game's server side |

Plugins declare what they need (`requires: [:bacon_games]`), and the hub refuses to
activate one whose requirements are inactive.

**Naming:** the "Bacon" prefix marks first-party plugins. Third-party or per-site plugins
use their own names.

## Consequences

**Good**

- A new site is "core + the plugins it wants". The core can run with one database.
- Each plugin is a template. Bacon World shows a game; Bacon Store shows a commerce
  plugin with its own site routes and webhooks.
- Core stops knowing about money. Security review of payments is scoped to one folder.

**Costs and risks**

- **The plugin framework grows** (mount points, dependencies, more hooks). That is
  small, and each hook removes a direct core→plugin call.
- **Renames touch stored names.** These include the Web Lobby's game row slug, its table
  names and `plugin_states`, and the payment webhook URL configured in the Stripe
  dashboard. Each needs a data migration or an operator step (listed below). BACON8.md §5
  rules apply: plan downtime, write the runbook.
- **Money tables are not renamed.** `store_*`, `wallet_*` and `payment_events` keep their
  names inside `bacon_store` (a documented exception to the `<slug>_` table prefix).
  Renaming ledgers buys nothing and risks data.

## Plan

Each phase ends green (compile with warnings as errors, plus the full test suite, both
in Docker) and is deployed before the next starts.

### Phase 1: rename Web Lobby to Bacon World (done 2026-10-21)

1. **Code.** `git mv plugins/web_lobby plugins/bacon_world`, then rename the modules:
   - `WebLobby` → `BaconWorld`
   - `WebLobbyWeb` → `BaconWorldWeb`
   - the plugin `slug` → "bacon_world", `name` → "Bacon World"

   Also update the PubSub and Presence prefixes (`web_lobby:` → `bacon_world:`), the
   localStorage key (`web_lobby:sound` → `bacon_world:sound`), the `.gitignore`
   exception (`!/plugins/bacon_world/`), `config :bacon8, :default_active_plugins` and
   the prod configmap's `BACON8_ACTIVE_PLUGINS`. Keep the JS hook names; they are
   global and not stored.
2. **Games database.** Leave the plugin's first migration as it is (BACON8.md
   invariant 14: never edit a baseline). Add a migration after it that renames the three
   tables and everything named after them: `ALTER TABLE IF EXISTS web_lobby_zones RENAME
   TO bacon_world_zones`, the same for spells and character_spells, then `ALTER INDEX`
   for the primary keys (`*_pkey`) and unique indexes (`*_slug_index`,
   `*_character_id_spell_id_index`) and `ALTER TABLE ... RENAME CONSTRAINT` for the two
   foreign keys (`*_fkey`). Ecto looks constraints up by those default names, so stale
   ones would surface later as crashes instead of changeset errors. The tables use
   UUID keys, so there are no sequences. The same migration runs
   `UPDATE games SET slug = 'bacon_world', name = 'Bacon World' WHERE slug = 'web_lobby'`;
   characters follow by `game_id`. A fresh install runs both migrations and ends with the
   same schema as production. `down` renames everything back.
3. **Site database.** Add a plugin site migration:
   `UPDATE plugin_states SET slug = 'bacon_world' WHERE slug = 'web_lobby'`. First count
   any other stored `web_lobby` values (the ledger's `game_slug`, entitlement keys
   `web_lobby:*`). None are expected; ledger rows are history and keep the slug they
   were written with.
4. **Old links.** Add a `previous_slugs/0` plugin callback (default `[]`). The plugin
   router then adds a permanent redirect from `/games/<old>/*` to `/games/<new>/*`.
   Bacon World returns `["web_lobby"]`.
5. **Docs.** BACON8.md §9 ("Web Lobby (the template plugin)" becomes "Bacon World"),
   `plugins/README.md`, the plugin README, `README.md`.

**Done when:** `grep -ri web_lobby` matches only the migrations, `previous_slugs` and
history notes. Existing characters still load. `/games/web_lobby` redirects.

### Phase 2: plugin framework for site plugins

1. **Mount points.** Extend `Bacon8.Plugin.Routes` with `site` (browser) and `site_api`
   blocks mounted at `/<mount>` and `/api/<mount>`. A plugin declares `mount/0`; for
   the store it is "store". Admin stays at `/admin/<slug>`. A route that must keep an
   absolute path for an external caller (a webhook URL already registered with a
   provider) goes in a `fixed` block, which needs a `reason:` string.
2. **Dependencies.** Add `requires/0` (default `[]`). `Plugins.activate/2` refuses while a
   requirement is inactive, and `deactivate/2` refuses while an active plugin requires
   the one being turned off. Show both on `/admin/plugins`.
3. **Hooks that replace direct core→store calls:**

   | Hook | Replaces |
   |---|---|
   | `retains_user_data?(user_id) :: boolean` | `Accounts.delete_user/1` checking store tables; any `true` means anonymise |
   | `storage_refs() :: [storage_key]` | `Drive.gc_blobs/2` keeping product files |
   | `nav_links(user) :: [%{label, path, icon}]` | hard-coded `/store` links in navigation and taskbar |
   | `profile_tabs(user)` | the `/profile/orders` tab |
   | `raw_body_paths() :: [prefix]` | the endpoint's raw-body reader knowing about payment webhooks |
   | `admin_tools/0` (optional) | the API toolbox's store section |
4. **Tests.** Tests for each hook, using the fixture plugin.

### Phase 3: extract the store as `bacon_store`

1. Move `lib/bacon8/{store,wallet,payments}*`, the store LiveViews, `StoreFileController`,
   `PaymentWebhookController`, the store admin pages and `store_components.ex` into
   `plugins/bacon_store`. The namespaces become `BaconStore` and `BaconStoreWeb`.
2. Move the migrations unchanged: same versions and table names, so production runs
   nothing. They go into the plugin's `priv/repo/migrations`.
3. Routes go into the plugin's `site` and `site_api` blocks:
   - the pages: `/store`, `/store/p/:slug`, `/store/library`, `/store/orders`, media and
     downloads;
   - the webhook: `POST /api/store/webhooks/:provider`. Keep the old
     `/api/webhooks/payments/:provider` in a `fixed` block until the Stripe dashboard
     points at the new URL, then remove it.
4. Implement the Phase 2 hooks in the plugin. `Store.Sweeper` moves to `children/0`.
   Entitlement kinds (`store_download`, `channel_access`, `channel_slots`) are
   registered by the plugin.
5. Move the tests (`store_*`, `stripe_test`, `wallet_test`) into `plugins/bacon_store/test`.
6. **Done when:** core compiles and its suite passes with `plugins/bacon_store` deleted;
   with it, everything in BACON8.md §8 behaves as before (the Stripe test-mode checkout,
   webhooks, disputes, Gems).
   - **Operator step:** after deploying, change the Stripe webhook endpoint to
     `/api/store/webhooks/stripe`.

### Phase 4: games platform as `bacon_games` (larger; after 1–3)

Move `Bacon8.Games` (games, characters, servers, releases, launcher, platform API) and
`Bacon8.GamesRepo` into a plugin. Bacon World and RaysSpaceSim declare
`requires: [:bacon_games]`. The games database becomes optional:
`GamesRepo` starts only when the plugin is installed. Rename nothing stored. The
`/api/games/*` paths stay, because game clients use them.

### Phase 5: the site kit

Make "start a new site from the core" a documented, five-minute job:

- **Config instead of code** for identity:
  - `SITE_NAME`, `SITE_URL`, the brand directory (`brand/` with `brand.json`, already
    used);
  - `SESSION_COOKIE_NAME` (default `_bacon8_key`, kept for this site);
  - a default theme;
  - which CMS page is the home page;
  - menus as CMS data (WordPress-style menus).
- **`mix bacon8.new_site <name>`**, or a checklist in `README.md`. It:
  - copies `k3s/overlays/prod` to a new overlay with its own namespace, domain,
    database names and secrets;
  - sets the brand masters;
  - picks the plugins (`BACON8_ACTIVE_PLUGINS`).
- **Each site is its own deployment and databases.** Bacon8 stays single-tenant on
  purpose (BACON8.md §1).
- **Plugins stay in-tree folders.** A site keeps the ones it wants, and private ones
  are their own repositories (unchanged).

## Alternatives considered

- **Keep the store in core, just hide it.** Rejected: it doesn't make a lean core, and
  money code stays entangled with accounts and the drive.
- **Hex packages for core and plugins.** Rejected before (§2, 2026-10-15): plugins depend
  on the hub, so a package model is circular. Forking the core repo per site is simpler.
- **Multi-tenant (many sites in one deployment).** Rejected: every table would need a
  tenant id, and the isolation and backup story gets much harder. Separate deployments
  are cheap on k3s.

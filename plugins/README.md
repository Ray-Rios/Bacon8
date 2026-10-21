# Plugins

Each folder here is a Bacon8 plugin, WordPress-style: drop a folder in, deploy, then
activate it on **/admin/plugins**. See BACON8.md §9 for the full contract.

```
plugins/<slug>/
  README.md
  lib/<slug>/plugin.ex          <Slug>.Plugin - `use Bacon8.Plugin, slug: "<slug>", ...`
  lib/<slug>/...                your contexts and schemas
  lib/<slug>_web/...            your LiveViews and controllers
  lib/<slug>_web/routes.ex      `use Bacon8.Plugin.Routes` - api / browser / admin blocks
  priv/games_repo/migrations/   your tables, prefixed <slug>_
  priv/repo/migrations/         (optional) site-database tables
  assets/js/index.ts            `export const hooks = {...}`: your LiveView hooks
  test/test_helper.exs          required by mix (may be empty)
  test/                         runs with `mix test`
  k3s/                          (optional) Kubernetes manifests; deploy-prod.sh applies them
```

Rules of the road:

- The folder name is the slug: lowercase letters, digits and underscores
  (`bacon_world`). It names your module (`BaconWorld.Plugin`), prefixes your tables
  (`bacon_world_zones`) and is your game slug unless `game/0` says otherwise.
- Use your own namespace (`BaconWorld`, `BaconWorldWeb`), never `Bacon8.*`.
- Talk to the hub only through its public contexts (`Bacon8.Games`, `Bacon8.Drive`,
  `Bacon8.Entitlements`, ...). Core code never references a plugin.
- API routes mount at `/api/games/<game slug>/...` (controllers get `params["game_slug"]`,
  as the hub's own game routes do); pages at `/games/<slug>/...`; admin pages at
  `/admin/<slug>/...` (admins only - link them from `admin_nav/0`).
- Need to react to the hub? Implement `hub_event/1` (channel updated/deleted, member
  removed - see `Bacon8.Plugin`). It's called for installed plugins, active or not.
- Shipping files you read at runtime? Put them in `priv/` and find them with
  `Bacon8.Plugins.priv_dir("<slug>")`.
- Settings: read your own environment variables at runtime (a small `Config` module
  that calls `System.get_env/1`, overridable with `config :bacon8, YourModule, ...`);
  the hub's `config/runtime.exs` doesn't know your plugin.
- Run migrations with `mix bacon8.migrate` (plain `mix ecto.migrate` only sees `priv/`).
  Migration versions share one table with core: use real timestamps.
- JavaScript: your `assets/js/index.ts` is picked up automatically on the next asset build.
  Hook names are global, so make them distinctive. Import npm packages through the shims in
  `assets/js/vendor/` (e.g. `import * as THREE from "../../../../assets/js/vendor/three"`);
  esbuild can't see `node_modules` from here.
- A private plugin can be its own git repository cloned into this folder. The hub's
  `.gitignore` ignores every plugin folder except the ones it ships, so it stays out
  of the public repo, and `.dockerignore` keeps its `.git`, `k3s/` and scripts out of
  images. Switch it on from the first boot with `BACON8_ACTIVE_PLUGINS`.

`bacon_world/` is the reference plugin: copy it to start your own.

Renaming a plugin changes stored names (BACON8.md §5). Return the old slug from
`previous_slugs/0` so `/games/<old>/...` and `/admin/<old>/...` redirect, and rename your
tables, game row and `plugin_states` row in a new migration; never edit the first one.
Bacon World (formerly `web_lobby`) is the worked example.

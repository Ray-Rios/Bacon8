# Bacon Store

Products, checkout, Gems (the hub-wide currency), payment providers and their webhooks,
the buyer's library, the sweeper that ends timed passes, and the store admin. The full
description is BACON8.md §8.

It is Bacon8's reference **site plugin** (ADR 0001, phase 3): where Bacon World is a game
under `/games`, this mounts at the top level, and core reaches it only through plugin
hooks (BACON8.md §9). Delete this folder and the hub still builds and runs, without a
store.

## What's where

| Path | What it is |
|---|---|
| `lib/bacon_store/plugin.ex` | The plugin: mount `"store"`, admin nav, entitlement kinds, and the hooks core calls |
| `lib/bacon_store/store.ex`, `store/` | Products, orders, checkout, delivery (`Fulfilment`), the library, the `Sweeper` |
| `lib/bacon_store/wallet.ex`, `wallet/` | The double-entry Gem ledger |
| `lib/bacon_store/payments.ex`, `payments/` | Providers (`Stripe`, `Fake`), the webhook event inbox |
| `lib/bacon_store_web/routes.ex` | All routes, below |
| `lib/bacon_store_web/live/` | Store pages; `admin/` for products and orders |
| `lib/bacon_store_web/controllers/` | Product media and downloads, payment webhooks |
| `priv/repo/migrations/` | The store's tables. Moved from core unchanged (same versions) |
| `test/` | Run with the core suite |

## Routes

| Path | |
|---|---|
| `/store`, `/store/p/:slug`, `/store/library`, `/store/orders[/:id]`, `/store/fake-checkout/:ref` | pages (`site`) |
| `/store/media/:id`, `/store/download/:id` | product images and downloads (`site`, `:drive_files` pipeline) |
| `POST /api/store/webhooks/:provider` | payment webhooks (`site_api`, `:webhooks` pipeline) |
| `/admin/bacon_store/products[/new\|/:id]`, `/admin/bacon_store/orders[/:id]` | admin |

## Hooks it implements

- `retains_user_data?/1`: a user with orders, a wallet or license keys is anonymised, not deleted.
- `storage_refs/0`: product images and downloads are blobs the drive's GC must keep.
- `raw_body_paths/0`: both webhook paths, so the provider's signature can be checked.
- `nav_links/1`, `profile_tabs/1`, `admin_tools/0`, `admin_dashboard/0`: the Store link, the
  buyer's orders and library, the order list in the API toolbox, revenue and recent orders.

## Settings

Read at runtime from the environment (the hub's `runtime.exs` doesn't know them):
`STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET`, `PAYMENTS_PROVIDER`. App config under
`BaconStore.Payments` overrides them (development turns the fake provider on; tests also
set `read_env: false`).

## Turning it on

Production activates it through `BACON8_ACTIVE_PLUGINS` (`bacon_world,bacon_store,...`);
an admin can switch it on or off at `/admin/plugins`. While it's off, `/store` and the
webhooks answer 404 (Stripe retries), and its data stays.

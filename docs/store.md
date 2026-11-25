Moved word for word from BACON8.md (§8) on 2026-11-19; BACON8.md keeps a short summary and links here.

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
| Baskets (2026-10-29) | **Several items in one purchase.** The cart is `store_cart_items` (`BaconStore.Store.Cart`: one of each product, 20 at most, it follows the buyer between devices); "Add to cart" on an item's sheet, the Cart button opens `?cart=1`. Paying is `Store.start_basket_checkout/3` (one provider checkout: Stripe gets a line per item, `client_reference_id` the basket) or `Store.buy_basket_with_gems/2` (one transaction: all paid and delivered, or none). **Each item is still its own order**, so delivery, license keys, disputes and "Retry delivery" work per item as before; the orders of one purchase share `basket_id`, `number` (from `store_order_number_seq`, starting at 8001) and, by card, `provider_ref` (no longer unique). A completed checkout must pay the basket's total; a dispute is on the whole payment, so it holds every item. `start_checkout/3` and `buy_with_gems/2` are baskets of one. Bought items leave the cart. **Receipts:** `Store.receipt/1`, `list_user_receipts/2`, `list_receipts/1`; `StoreComponents.receipt/1` is the front page's card (number, items, total, a stamp: Paid, Pending, Void, Disputed, Charged back) on `/store/orders`, `/store/orders/:id`, the library's "Recent orders" and `/admin/bacon_store/orders` (with the buyer; the detail shows each item's order). Migration `20261029100000` makes every existing order a basket of one with a number |
| The Gem (2026-10-25) | The currency has its own 3D gem, rendered in Blender (`art/pipeline/scripts/fire_gem.py`, Cycles turntable, 48 frames; `gem_sheets.py` adds the star glints and makes the sprite sheets `priv/static/images/gem/gem-64/160/288.webp` and the still `gem.webp`). On pages it is `<b8-gem>` (`assets/js/fire_gem.ts`): it turns and floats, and hovering makes it react a different way each time (whirl, hop, flare of embers, sparkles, wobble). Templates use `Bacon8Web.Components.Gem`: `<.gem size={20} />`, `<.gems amount={1500} />`, and `<.icon icon={item.icon} />` where `"gem"` is the gem (the Store's navbar link, Products in the admin sidebar). Amounts on the store pages, the Gem packs (bigger pack, bigger gem) and gem-pack products all use it; `Store.format_gems/1` stays for plain text |
| Card | `Store.start_checkout/3` reserves a license key until the order is paid, fails or is cancelled. Paid but undeliverable (keys ran out) stays "paid" with a reason; `/admin/bacon_store/orders` has "Retry delivery" |
| Expiry | `BaconStore.Store.Sweeper` (every 5 min, advisory lock): ends timed items and passes (a pass's channel membership goes with it), settles card checkouts whose 31 minutes are up (`Store.settle_stale_checkouts/1`, 2026-10-29c), and as a last resort cancels card orders still unpaid after 48 h |
| Unfinished checkouts (2026-10-29c) | **One open card checkout per buyer, 31 minutes long.** A Stripe session is created with `expires_at` (Stripe allows 30 min to 24 h) and the buyer's email; the basket keeps its `checkout_url` and `checkout_expires_at`. Optional provider callbacks `expire_checkout/1` (Stripe: `POST /v1/checkout/sessions/:id/expire`) and `checkout_status/1` (`GET /v1/checkout/sessions/:id`). `start_basket_checkout/3` calls `settle_open_checkouts/1` first: each waiting basket is closed at the provider and cancelled ("replaced by a newer checkout"), or, if the provider says it was paid, delivered (and the new basket's check then sees what was bought). `cancel_checkout/2`: the buyer's Cancel and the provider's cancel link (`/store/orders/:id?checkout=cancelled`). `reconcile/1` asks the provider and applies what it says as an event (`reconcile:<ref>` in `payment_events`, so the real webhook later changes nothing): run when the buyer comes back (`?checkout=done`), opens a waiting order, the store or Purchases. A provider that can't be reached leaves the checkout open and refuses a new one (`:checkout_open`). **Purchases and the library's "Recent orders" list only orders with `paid_at`**; `Store.open_checkouts/1` is the unfinished one, shown on `/store` (a banner) and Purchases with "Continue to payment" and "Cancel"; the stamp says "Unpaid". Admin `/admin/bacon_store/orders` views: Purchases (default), Checkouts open, Abandoned checkouts, Everything, and each status. **Pay with other things in the cart** adds the item to the cart and opens it (`StoreLive.with_cart/2`). **Paid for something already owned**: the order stays "paid" with `Store.duplicate_note/0`, nothing is delivered twice, and the admin's order says to refund that payment in Stripe. The fake provider follows the same rules (a closed checkout can't be paid; its Cancel goes through the cancel link). Store migration `20261029120000` |
| Pages | `/store` (category tabs, glass cards, Gem packs, the item sheet; 2026-10-28), `/store/p/:slug` (redirects to the sheet since 2026-10-28), `/store/library` (downloads, keys, items and passes), `GET /store/media/:id` (images), `GET /store/download/:id` (buyers only, attachment) |
| Admin | `/admin/bacon_store/products` (all products, new-product buttons per kind, categories), `/admin/bacon_store/products/new?kind=…` and `/admin/bacon_store/products/:id` (`BaconStoreWeb.Admin.ProductEditor`: text, prices, delivery, images, files, keys) |
| Accounts | `Accounts.delete_user/1` anonymizes a user with orders, ledger entries or keys instead of deleting the row |
| Glass cards (2026-10-28) | **The storefront is glass cards** like the games' (`StoreComponents.store_card/1`, styles `priv/store_cards.css` inlined into the page, hooks in `plugins/bacon_store/assets/js/`): every product and Gem pack on sale. The front shows the item turning in 3D in the middle with its kind, name and price; hovering (a tap on touch screens) turns it over to the item blurred behind frosted glass with its summary, description and what you get. **Clicking a card slides a sheet up from the bottom** (`?item=<slug>` on `/store`, so links open it and Back closes it; Esc, ✕ or the backdrop slide it away): the item large, its pictures, the description, and the pay buttons (card and/or Gems, with the Gem confirm). There is no separate product page: `/store/p/:slug` redirects to the sheet (the stable's Buy links and the admin's view links keep working). **The 3D item** (`Catalog.art/1`): the Gem for packs; the game's own model when the game plugin draws it (an optional `store_art(grant_kind, grant_key)` on its plugin module, returning `%{src, glow}`: Bacon World's four mounts); else an admin-uploaded picture; else the kind's 3D icon (a crate for downloads, a key for license keys, a ticket for passes, a chest for game items). The turntables are `<b8-spin>` (`store_spin.ts`): 48-frame Blender renders (`art/pipeline/scripts/store_turntables.py`, Cycles, then `store_sheets.py` for the 128/224/320 px sheets and a still), turning slowly and floating, reacting when their card is hovered (a whirl and a hop, or a turn back, and a glow in the item's colour). Sheets: `plugins/bacon_store/priv/static/spin/`, `plugins/bacon_world/priv/static/store/` |
| Game items (2026-10-24) | Bacon World's dragon mounts are the first plugin item kind: `BaconWorld.Plugin.entitlement_kinds/0` returns `["bacon_world_mount"]`, the key is the mount's id (`"*"` grants every mount). `BaconWorld.Mounts.ensure_store_products/0` creates their `item` products (`mount-<id>`, inactive) for the owner to publish. Admins ride all mounts without buying |

Download size is capped by `config :bacon8, BaconStore.Store, max_download_bytes:` (default 2 GiB). Uploads go through the LiveView socket in 1 MB chunks and are staged in the pod's temp directory first, so the pod needs that much free temp space.

Next: card subscriptions for storage tiers and VIP channels (Stripe Billing), then PayPal.

### Plugins for sale (2026-11-03)

A plugin is sold as a `download` product whose files are its releases (`BaconStore.Store.Releases`,
table `store_product_releases`). Built and tested in the cloud 2026-11-03; no release cut yet.

1. **Cut a release branch** from committed, tested work: `release/<plugin>/<version>` (never moved; a fix is a
   new version). The plugin's `use Bacon8.Plugin, version:` must say the same version on that branch.
2. **Package it on the development PC** (production has no git):
   `python3 scripts/release/package_plugin.py <plugin> <version> [--cut <ref>] [--notes "..."]` archives the
   plugin's folder as committed on that branch (`git archive`; uncommitted work, gitignored files and nested
   repositories stay out), from the hub's repository or, for a private plugin, its own (`plugins/<slug>/.git`).
   It refuses secret-looking files (`*secrets.yaml`, `.env*`, keys, certificates), adds `RELEASE.json`
   (plugin, version, branch, commit, built_at, notes) and writes `tmp/releases/<plugin>-<version>.zip`.
3. **Sell it**: `/admin/bacon_store/products` → "Sell a plugin" makes the product (`plugin-<slug>`, inactive, the
   owner's price); upload the zip under "Download files". The store reads `RELEASE.json` and records the release
   (refusing a second plugin on one product or a version already released); the releases list on the product
   page can withdraw ("yank") one, which hides its file from new buyers without deleting it.

Owner's decisions before the first sale: which plugins and at what price; their licence (the hub is public
and MIT; Bacon World ships in it, so selling it sells convenience and support rather than exclusive code);
and that models and audio are not in git (the asset rule, §2 2026-10-23), so a release zip carries code only
until assets have a licensed way into it.

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

The jeweller's Gem-only sets for the games that keep their own bags (Tears of Babylon,
RaysSpaceSim; 2026-11-24): `Bacon8.GemShop`, `GET /api/games/:slug/gems/jeweller` and
`POST /api/games/:slug/gems/jeweller/buy` (`item_id`, `character_id`, `body`, `nonce`), as the
player or the game server for them. One `spend` under the game's slug, keyed by the click's
nonce (a retry charges nothing and returns the same pieces); the game adds the pieces to the
character. Bacon World's own jeweller (`BaconWorld.Jeweller`) still puts them in its bags itself.

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


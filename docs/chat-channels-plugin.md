# Plan: the forum becomes the `chat_channels` plugin

Status: **phases 1 and 2 done 2026-10-25**; phases 3 and 4 open. Written 2026-10-25 after the forum got its tests
(`test/bacon8/forum/*`: 105 tests, plus 34 for pages and blog; commit `37d84ea`).

## Decision (owner, 2026-10-25)

- The forum leaves the core and becomes a plugin: slug **`chat_channels`**, display name
  "Chat Channels", mounted at **`/chat`**.
- The navbar and taskbar link says just **"Chat"** (not "Forum"). It comes from the plugin's
  `nav_links/1`, so it disappears with the plugin.
- Games that use channels depend on it the way RaysSpaceSim's Holo-sims already do: they
  declare `requires/0 = ["chat_channels"]`, and the hub refuses to activate them (or to
  switch chat off under them) otherwise. The mechanism exists and is tested
  (`test/bacon8/plugin_hooks_test.exs`, "requires/0").
- **This supersedes ADR 0001 on one point.** ADR 0001 (removed from the tree; `git show 95aba50^:docs/adr/0001-core-and-plugins.md`)
  listed "the forum and chat channels" as part of the core. The owner has now decided chat
  is a plugin. Everything else in ADR 0001 stands.
- The core keeps `/pages` and `/blog` (the `Bacon8.Content` context). They are rebuilt
  separately (see "Not in this plan").

## What exists today (measured, not remembered)

| | |
|---|---|
| Context | `Bacon8.Forum` (`lib/bacon8/forum.ex`, 1,557 lines) and 9 schema modules in `lib/bacon8/forum/` |
| Tables | `chat_channels`, `chat_messages`, `chat_message_attachments`, `chat_reactions`, `chat_threads`, `channel_members`, `channel_invites`, `streaming_sessions`, `custom_emojis` |
| Where they are created | **Phase 4 done (2026-10-26):** the plugin's own migration `plugins/chat_channels/priv/repo/migrations/20261026000000_create_chat_tables.exs` (idempotent: a no-op on production, builds a fresh database). They used to be in core's baseline |
| Per-user settings | `chat_user_settings` (`ChatChannels.UserSettings`): `channel_allowance` (default 5), `channel_order`, `allow_invites`. Copied from the old `users` columns by `20261026000100_create_chat_user_settings.exs` |
| UI | `ForumLive` (3,085 lines), `EmojiPickerComponent`, admin `CustomEmojis`; routes `/forum` and `/forum/:channel_id`; the `ChatInput` hook and forum sidebar code in `assets/js/app.ts` |
| Links | hard-coded "Forum" in `components/navigation.ex` and `components/taskbar.ex`; `forum` is a reserved mount in `plugin_router.ex` |
| PubSub topics | `chat:channels` and `channel:<id>` (kept as they are) |
| Tests | channels, permissions, messages, invites (`test/bacon8/forum/`), 105 tests |

## What depends on it, and how each seam is cut

The core must not reference a plugin, so every place the core or another plugin calls
`Bacon8.Forum` needs a replacement before the code can move.

| Caller | Uses | Resolution |
|---|---|---|
| `Bacon8.Accounts` (delete user, anonymise) | deletes the user's messages and reactions | a hub event `{:user_deleted, user_id}` through `Bacon8.Plugins.notify/1` (the mechanism already carries channel events); the plugin deletes its own rows. The `has_many :chat_messages` on `User` goes |
| `Bacon8.Notifications` (@mentions) | `Message`, `Forum.get_channel/1`; `user_notifications.channel_id` is `belongs_to Forum.Channel` | the plugin calls a generic core API to create a mention notification with a source (kind + id); the association becomes a plain column. **Decision needed**, see below |
| `Bacon8.Files` | `MessageAttachment` alias | legacy (BACON8.md §13 calls the module dead); delete the alias |
| `DesktopLive` | pending invites badge, accept and decline | move to the plugin as its own desktop app, or let `nav_links/1` carry a badge count. **Decision needed** |
| `Bacon8.Plugin` docs | event structs `%Bacon8.Forum.Channel{}` | become `%ChatChannels.Channel{}`; the plugin is the one emitting `{:channel_updated, ...}`, `{:channel_deleted, ...}` and `{:channel_member_removed, ...}` |
| **RaysSpaceSim** (`holo_sims.ex`, `sim_access.ex`, `holo_sim_controller.ex`) | creates, edits and deletes user channels, members, `channel_allowance`, `list_owned_channels` | hard dependency: `requires: ["chat_channels"]`, direct calls to `ChatChannels` |
| **Bacon Store** (`catalog.ex`, `fulfilment.ex`) | lists private channels to sell access to, adds and removes members for channel-access and channel-slot products | soft dependency: those two product kinds are offered only while the plugin is active (`Bacon8.Plugins.active?/1`), calls go through `ChatChannels`; no `requires` |
| `UploadsGuard` | the `forum/` upload folder | the path stays (it is only a documented exception today); no change in phase 1 |

## Data

- **Tables keep their names and the DDL stays in the core baseline for now.** The same rule
  as Bacon Store ("its tables keep their names"), with one difference: the baseline already
  created these, and `user_notifications` has a foreign key to `chat_channels`, so moving the
  DDL into a plugin migration before notifications are decoupled would break fresh installs.
  Phase 1 moves code only. Moving the DDL (as idempotent `create_if_not_exists` plugin
  migrations) is phase 4.
- **`users.channel_allowance` and `users.channel_order` stay on the user row** in phase 1.
  The plugin reads them. They can move to a `chat_channels_user_settings` table in phase 4.
- No production data is touched in phases 1 to 3.

## Phases

Each phase ships on its own (verify, commit, deploy, check) and can be reverted by
reverting its commit.

**Phase 1: move the code, rename the namespace.** `plugins/chat_channels/` with
`ChatChannels.Plugin` (`mount: "chat"`), the context and schemas as `ChatChannels.*`,
`ForumLive` moved as it is, the tests moved with their fixtures, the `ChatInput` hook and
sidebar code moved into the plugin's `assets/js/index.ts`. Cut every seam in the table above.
`Bacon8.Forum` is deleted, not aliased. The plugin keeps the PubSub topic names.
*Check:* the full suite, the release test (no migration pending), the plugin tests for
requires, `/chat` works as `/forum` did.

**Phase 2: the links and the old address.** `/forum` and `/forum/:channel_id` answer 301
to `/chat/...` (a `fixed` route, as Bacon Store did for Stripe's old webhook URL); the navbar
and taskbar read `nav_links/1` ("Chat"); `forum` leaves the reserved mounts list.

**Phase 3: tidy.** Delete the dead code (below). Split `ForumLive` into the sidebar, the
message list, the composer, the member list and the invite dialogs. This is the risky,
rewarding part, and it is easier once the tests and the plugin boundary exist.

**Phase 4: finish the separation (done 2026-10-26).** The chat DDL left the site baseline for an idempotent
plugin migration; `channel_allowance`, `channel_order` and the invite switch moved to `chat_user_settings`
(the store adds slots through `BaconStore.Chat.add_channel_allowance/2`; the invite switch is on the Chat
page, not the profile); `user_notifications.channel_id` and its foreign key were dropped (core migration
`20261026000200`). **Left on purpose:** `users.channel_allowance`, `channel_order` and `allow_channel_invites`
still exist in production, unread, until the owner has checked the copy; then a core migration drops them.
The baseline was edited (against its own "don't edit" note) because it is the only way a fresh database
stops creating chat tables; it never runs on production.

## Operational notes (the things that bite)

1. **Production's plugin list must name `chat_channels`.** `BACON8_ACTIVE_PLUGINS` in
   `k3s/overlays/prod/configmap.yaml` is `"bacon_world,bacon_store,rays_space_sim"`. If the
   code ships and the list doesn't, chat vanishes (and RaysSpaceSim's Holo-sims, which
   require it, are then inactive too). Change the list in the same commit as phase 1.
2. A plugin that is active by default but whose requirement is off is not active
   (`plugin_hooks_test.exs`), so the list needs both names.
3. Existing `plugin_states` rows: a first activation runs `on_activate/0`; make it a no-op
   (the tables exist).
4. The kick and ban hooks (`{:channel_member_removed, ...}`) are synchronous and are the
   security half of removing someone from a running game world. Phase 1 must keep them
   synchronous and keep the test that pins them.

## Dead code to delete while moving

All have no callers outside the forum module (checked 2026-10-25):

- `list_user_channels/1` (a stub that always returns `[]`, with a TODO)
- `list_messages_by_room/2` (queries a `room_id` the table doesn't have, and never runs the query)
- `create_message/1` (the one-argument "Social Hubs" version)
- `list_public_user_channels/0`
- `list_channel_streams/2`

## What was done (phases 1 and 2, 2026-10-25)

The code moved with `git mv` (history kept) and was renamed: `Bacon8.Forum` is `ChatChannels`,
the schemas `ChatChannels.Channel` and so on, `ForumLive` is `ChatChannelsWeb.ChatLive`. The plugin is
`plugins/chat_channels` (slug `chat_channels`, mount `chat`); see its README.

| Seam | How it was cut |
|---|---|
| Account removal | A hub event, `{:user_content_removed, user_id}`, sent inside the account's transaction; the plugin deletes its rows. `User` lost `has_many :chat_messages` |
| Notifications | Generic: `source_kind`, `source_id` and `metadata.path` (migration `20261025020000`); the hub's panel renders those. Mentions and invitations are created by the plugin (`ChatChannels.Notices`). `Notifications.create_notification/1` now announces what it creates |
| Desktop | The invitation list, accept and decline moved to the Chat page; the nav link carries a count badge (the plugin contract has an optional `:badge`). The bell counts notifications only (an invitation is now one) |
| `Bacon8.Files` | Looks the attachment schema up when needed and sees none without chat |
| Bacon Store | `BaconStore.Chat` finds chat when called (no compile-time dependency); channel lists use schemaless queries |
| RaysSpaceSim | `requires/0 = ["chat_channels"]`; calls `ChatChannels` directly |
| Navigation | The hard-coded "Forum" links went; the plugin's `nav_links/1` supplies "Chat" |
| Old address | `/forum` and `/forum/:channel_id` answer 301 to `/chat` (a `fixed` route; the query string is kept) |
| Activation | `chat_channels` is in the default list (`config/config.exs`) and in production's `BACON8_ACTIVE_PLUGINS` (`k3s/overlays/prod/configmap.yaml`) |
| JS | The four forum-only hooks (`MessageList`, `ChatInput`, `SidebarResizer`, `Sortable`) moved to the plugin's `assets/js/index.ts`; a dead `MessageReactions` hook was dropped |
| Dead code dropped | `Bacon8.ForumAttachment`, `AdminLive.Channels` (a "coming soon" stub), `EmojiPickerComponent` (unused) |

Checked: the hub compiles and its core tests pass **without** the plugin (and without RaysSpaceSim,
which needs it); the one exception is the store's own channel-pass tests.

**Bugs found on the way, fixed:** @mentions never created a notification (`actor.username` does not
exist, inside a task that failed quietly); marking a notification read crashed (microseconds in
a whole-second column) and "Mark all read" and the old-notification cleanup silently did
nothing for the same reason; `list_user_notifications/2` preloaded the removed association and
its `rescue` returned an empty list; the mention link opened the wrong page; `bob@example.com`
counted as a mention of "example".

## What is left

- **Phase 3, tidy (2026-10-26):** done: the five dead functions are deleted; the message and emoji components
  moved to `ChatChannelsWeb.ChatComponents` (`ChatLive` 3,158 -> ~2,750 lines); `/chat/invite/:code` is
  `InviteLive` (shows the channel, joins on a button press, one plain answer for any unusable code). Still open:
  split the rest of `render/1` (sidebar, composer, member and invite dialogs) into components, and test voice/
  video/stream channels.
- **Phase 4: done** (see above), including dropping the three unread `users` columns (2026-10-26, after the
  owner's OK and a production comparison: 3 non-default users, 3 settings rows, 0 differences).
- Test the voice, video and stream channels.

## Decisions (owner, 2026-10-25)

1. **Mention notifications:** generic source columns (done).
2. **Pending invites:** a badge on the Chat nav link, with the list on the Chat page (done).
3. **Phase 4:** yes, chat is self-contained (done 2026-10-26).

## Not in this plan

- Rebuilding the `/pages` and `/blog` builders. The tests for them exist now
  (`test/bacon8/content_test.exs`, 34 tests) and already found four bugs; the builders
  need their own design.
- Voice, video and stream channels keep working as they are (`streaming_sessions` moves with
  the rest). The code in them has no tests yet.

# Chat Channels

Text, voice, video and stream channels; messages with replies, reactions, pins and
attachments; per-channel membership and roles; invites; custom emojis. It was the hub's
forum until 2026-10-25, when it became a plugin (`docs/chat-channels-plugin.md` has the
plan, the reasons and what is still to do).

It is a **site plugin**: it mounts at `/chat` (not under `/games`), and the hub reaches it
only through plugin hooks. The navigation link says "Chat".

## What other things need from it

| | |
|---|---|
| **RaysSpaceSim** | A hard dependency. Holo-sims are built per channel, so that plugin declares `requires/0 = ["chat_channels"]`: the hub won't activate it without chat, or switch chat off under it. It calls `ChatChannels` directly. |
| **Bacon Store** | Optional. Channel passes and channel slots go through `BaconStore.Chat`, which finds chat when called, so the store compiles and runs without it. |
| **The hub** | Nothing, by design. Account removal, notifications and the desktop reach chat through events and plain data (below). |

## What's where

| Path | |
|---|---|
| `lib/chat_channels.ex` | The context: channels, messages, reactions, threads, members, invites, streams, emojis, and the permission checks |
| `lib/chat_channels/*.ex` | Schemas, `Plugin` (the hooks the hub calls), `Notices` (what chat tells the hub's notifications) |
| `lib/chat_channels_web/live/chat_live.ex` | The /chat page (large; splitting it is the plan's phase 3) |
| `lib/chat_channels_web/live/admin/custom_emojis_live.ex` | /admin/chat_channels/custom-emojis |
| `lib/chat_channels_web/routes.ex` | Routes, including the 301 from the old /forum address |
| `assets/js/index.ts` | The page's hooks (message list scrolling, the input, the resizable sidebar, drag-sorting) |
| `test/` | Runs with the core suite: channels, permissions, messages, invites, notices, the plugin, the page |

## How it touches the hub

- **Account removal.** When a user is banned or deleted the hub sends
  `{:user_content_removed, user_id}` inside the account's transaction; `ChatChannels.Plugin`
  deletes that user's messages and reactions.
- **Notifications.** Chat creates ordinary hub notifications (`Notices`): a mention, an
  invitation. Each carries `source_kind: "chat_channel"`, `source_id` (the channel) and a
  `path` in its metadata, which the panel opens. The hub knows nothing else about them.
- **Pending invitations.** They are listed at the top of the Chat page's sidebar, and the
  navigation link shows their count as a badge (`nav_links/1`).
- **Events chat sends** (`Bacon8.Plugins.notify/1`): `{:channel_updated, new, old}`,
  `{:channel_deleted, id}` (before the rows go), `{:channel_member_removed, channel_id,
  user_id}` (kick, ban or leave; synchronous on purpose, it is the security half of removing
  someone from a running game world).

## Data

The tables keep their names (`chat_channels`, `chat_messages`, `chat_message_attachments`,
`chat_reactions`, `chat_threads`, `channel_members`, `channel_invites`, `streaming_sessions`,
`custom_emojis`) and are created by this plugin's own migration (`priv/repo/migrations`). A user's channel
allowance, list order and invite switch live in `chat_user_settings` (`ChatChannels.UserSettings`).
Uploads still go to `uploads/.../forum/...` (a documented exception, BACON8.md §7).

A channel's icon lives in `uploads/<uploader>/channel_icons/<channel id>/`, and only the server sets
`icon_path`: `Channel.changeset/2` doesn't cast it, `Channel.put_icon/2` accepts nil or a file in that
folder, and changing the icon or deleting the channel deletes files only when `Channel.icon_path?/2`
agrees (rows saved before 2026-10-25 may hold anything; until then the create form could set it).

## Known gaps

- `ChatLive` (~2,050 lines) is now the page's state and event handlers; everything it draws (messages, emoji
  pickers, sidebar, header, pinned messages, edit/reply/composer forms, dialogs) is in `ChatComponents`.
- Voice, video and stream channels exist but have no tests.

## Turning it off

Switching it off hides /chat, the link and the emoji admin page; the data stays. It can't be
switched off while an active plugin requires it. Deleting the folder removes chat from the hub
(the core still builds and its tests pass); RaysSpaceSim then can't be built, because it requires it.

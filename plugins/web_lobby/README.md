# Web Lobby

A small multiplayer 3D arcade that runs in the browser: make a character, walk
around the lobby with other players, chat with people nearby, and throw stones
at anyone who has PvP turned on.

It is also Bacon8's **reference plugin**. Copy this folder to start your own
(see `plugins/README.md` and BACON8.md §9).

## What's where

| Path | What it is |
|---|---|
| `lib/web_lobby/plugin.ex` | The plugin: name, version, its game card, its routes |
| `lib/web_lobby/world.ex` | Characters, zones, positions |
| `lib/web_lobby/combat.ex` | Spells, HP/MP, respawn (server-authoritative) |
| `lib/web_lobby/models.ex` | Which character models players can pick |
| `lib/web_lobby/{zone,spell,character_spell}.ex` | Schemas for the plugin's own tables |
| `lib/web_lobby_web/routes.ex` | `/games/web_lobby` |
| `lib/web_lobby_web/play_live.ex` | Character select and the live world |
| `priv/games_repo/migrations/` | `web_lobby_zones`, `web_lobby_spells`, `web_lobby_character_spells` |
| `assets/js/` | The three.js client (`WorldCharacterUIScene` hook) |
| `test/` | Runs with `mix test` |

## Data

Characters are the hub's `game_characters` rows for game `web_lobby`, so they
are not a Web Lobby table at all. Lobby-only values sit in the row's JSON maps:
`stats` holds HP, MP and the PvP flag; `settings` holds the character type,
model, zone and last position. The plugin's own tables, in the games
database, are prefixed `web_lobby_`.

## Character models

Players pick from the model files the hub serves under `/models/`
(`priv/static/models`, a volume in production). With no models installed,
set `ENABLE_BUILTIN_MODELS=true` to offer three simple built-in ones.
`MAX_CHARACTER_MODELS` caps the list; a `supported_models.txt` in the models
folder (one relative path per line) limits it to those files.

## Multiplayer

All on the hub's PubSub and Presence, topics prefixed `web_lobby:`. Moves are
checked on the server for speed, height and collisions; chat reaches players
within 64 units; one character per account can be in the world at a time.

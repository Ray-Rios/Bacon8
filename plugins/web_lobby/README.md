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
| `assets/js/` | The three.js client (`WorldCharacterUIScene` hook); `lobby-audio.ts` for sound |
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
folder (one relative path per line) limits it to those files. A character whose
model has been removed wears the first model still offered.

The shipped models are the **Bacon8 humans**, `Humans/Male.glb` and
`Humans/Female.glb`. They are CC0 base bodies (Blender Studio) on the B8 skeleton,
with 20 CC0 clips from Quaternius' Universal Animation Library and a Bacon8 outfit.
The game repository builds them (`SourceAssets/Characters/B8Human/build_humans.py`,
the `*_web.glb` outputs), along with the full 89-clip versions, the Unreal assets and
test weapons with a shared grip (`weapon_r` / `weapon_l` bones).

Any rigged glTF/GLB (or FBX) works. Clips are found by name (`model-manager.ts`).
`PREFERRED_CLIPS` lists the exact names each action prefers first:

| Action | Clip |
|---|---|
| idle | `Idle_Loop` |
| walk | `Walk_Loop` |
| run | `Jog_Fwd_Loop` |
| jump | `Jump_Loop` |
| attack (the throw) | `OverhandThrow` |
| cast | `Spell_Simple_Shoot` |
| death | `Death01` |
| hit | `Hit_Chest` |

Then name patterns (`Idle`, `Walk`, `Run`, `Jump`, `Attack...`, `Death`) cover other
models. Death plays once and holds; the attack plays once over the current motion.

Characters are copied with `SkeletonUtils.clone`; a plain `clone()` would leave every
copy bound to the template's bones, and nothing would animate.

**Coming next:** the rename to **Bacon World** (`bacon_world`; ADR 0001, phase 1),
weapon attachment, the upper-body attack layer, jiggle springs and body morphs (the
game repository's `SourceAssets/Characters/ANIMATION_ROADMAP.md`).

## Sound

`assets/js/lobby-audio.ts` plays the hub's own sounds from `/audio/lobby/`
(throws, hits, footsteps, jumps, death, respawn) and loops
`/audio/music/arcade-lobby.mp3` while you are in the world. The HUD's Sound button
turns it all off, remembered per browser. Browsers allow sound only after the
first click or key press.

## Multiplayer

All on the hub's PubSub and Presence, topics prefixed `web_lobby:`. Moves are
checked on the server for speed, height and collisions; chat reaches players
within 64 units; one character per account can be in the world at a time.

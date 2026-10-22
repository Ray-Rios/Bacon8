# Bacon World

A small multiplayer 3D arcade that runs in the browser: make a character, walk
around the lobby with other players, chat with people nearby, and throw stones
at anyone who has PvP turned on.

It is also Bacon8's **reference plugin**. Copy this folder to start your own
(see `plugins/README.md` and BACON8.md §9).

It was called **Web Lobby** (slug `web_lobby`) until 2026-10-21. Old links
(`/games/web_lobby/...`) answer 301 to `/games/bacon_world/...`, and the migrations below
renamed its tables, its game row and its `plugin_states` row.

## What's where

| Path | What it is |
|---|---|
| `lib/bacon_world/plugin.ex` | The plugin: name, version, its game card, its routes |
| `lib/bacon_world/world.ex` | Characters, zones, positions |
| `lib/bacon_world/combat.ex` | Spells, HP/MP, respawn (server-authoritative) |
| `lib/bacon_world/models.ex` | Which character models players can pick; the humans' slider and hair manifests (`human_assets/0`) |
| `lib/bacon_world/appearance.ex` | `BaconWorld.Appearance`: normalises a look (never trusts the client) |
| `lib/bacon_world/{zone,spell,character_spell}.ex` | Schemas for the plugin's own tables |
| `lib/bacon_world_web/routes.ex` | `/games/bacon_world` |
| `lib/bacon_world_web/play_live.ex` | Character select and the live world |
| `priv/games_repo/migrations/` | `bacon_world_zones`, `bacon_world_spells`, `bacon_world_character_spells` (created as `web_lobby_*`, renamed by `20261021120000`) |
| `priv/repo/migrations/` | the site DB's `plugin_states` row, renamed by `20261021120100` |
| `assets/js/world-character-ui-scene.ts` | The hook (`WorldCharacterUIScene`): front end, world, multiplayer |
| `assets/js/front-ui.ts`, `character-stage.ts` | Character select and creator (HTML) over a lit 3D stage |
| `assets/js/appearance.ts`, `human-factory.ts` | The look model, and building a human from a look |
| `assets/js/character-controller.ts`, `controls-math.ts` | Third-person controls (below) |
| `assets/js/world-dressing.ts` | The lobby village and its colliders |
| `assets/js/model-manager.ts` | Characters in the scene: loading, animation clips |
| `assets/js/lobby-audio.ts` | Sound |
| `assets/js/__tests__/` | JS unit tests: `sh __tests__/run.sh` in a node container (esbuild + `node --test`) |
| `test/` | Runs with `mix test` |

## Data

Characters are the hub's `game_characters` rows for game `bacon_world`, so they
are not a Bacon World table at all. Lobby-only values sit in the row's JSON maps:
`stats` holds HP, MP and the PvP flag; `settings` holds the character type,
model, zone and last position. The plugin's own tables, in the games
database, are prefixed `bacon_world_`.

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
| run (jog, the default pace) | `Jog_Fwd_Loop` |
| sprint (Shift, or over 5.5 m/s) | `Sprint_Loop` |
| crouch / crouch-walk | `Crouch_Idle_Loop` / `Crouch_Fwd_Loop` |
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

## Looks and the creator

A character's look lives in its `settings["appearance"]`: body type, height, seven body and
three face sliders (morph targets on the v2 humans), skin, eyes and brows, one of 45 hair
styles, one of 6 facial hair, and outfit pieces with their colours. `BaconWorld.Appearance`
normalises every look the client sends: unknown keys are dropped, sliders clamped, colours
must be `#RRGGBB`, garments come from a fixed list and hair styles from the installed
manifest. The body type picks the model and can't change after creation. Characters made
before looks existed get the default look for their model.

Events: `three_ui_create_character` (replies `%{ok, character_id}` or `%{ok: false, error}`),
`three_ui_update_appearance` (refused while that character is in the world) and
`fetch_appearances` (other players' looks, at most 64 ids). `/models` doesn't serve `.json`
(BACON8.md invariant 17), so the LiveView passes the humans' manifests in
`data-human-assets`.

`human-factory.ts` builds each human from its look: the geometry is shared, each outfit gets
one cached index buffer that hides the skin under its clothes, hair and facial hair are bound
to the body's bones, and tints are per character.

## The village

`world-dressing.ts` lays out the lobby from `World/B8_Props.glb` and `World/B8_BuildKit.glb`:
the plaza and well, a market, seven houses, a camp, a training yard, a farm, trees and rocks,
merged per material (about 210k triangles in ~45 draw calls). It keeps the local player out
of its circle and box colliders (the controller's `collide` option), and its fog, fill light
and lamps follow the day/night cycle.

## Controls

RaysSpaceSim's on-foot movement with EverQuest-style mouse handling
(`character-controller.ts`; numbers in `controls-math.ts`):

| Input | |
|---|---|
| Click the game | lock the pointer: free look, the character turns to face where it moves |
| Hold right button | steer: the character faces where the camera looks (works locked or not) |
| WASD / arrows | move relative to the camera; Shift sprints, C crouches, Space jumps |
| Wheel | zoom (1.5 to 9 m) |
| Ctrl | free the cursor |
| Esc | free the cursor and open the game menu (sensitivity, invert Y, sound, log out) |
| Enter / `/` | chat / a slash command |

## Models on the volume

Gitignored; synced to the models volume with `sync-models-to-k8s.sh`: `Humans/Male.glb`
and `Female.glb` (v2, meshopt-compressed) with `Male.json` / `Female.json`, `Humans/Hair/`
(45 hair and 6 facial-hair GLBs, `icons/`, `hair_manifest.json`), and `World/`. Without
them the site falls back to whatever is on the volume, and looks have nothing to change.

## Sound

`assets/js/lobby-audio.ts` plays the hub's own sounds from `/audio/lobby/`
(throws, hits, footsteps, jumps, death, respawn) and loops
`/audio/music/arcade-lobby.mp3` while you are in the world. The HUD's Sound button
turns it all off, remembered per browser. Browsers allow sound only after the
first click or key press.

## Multiplayer

All on the hub's PubSub and Presence, topics prefixed `bacon_world:`. Moves are
checked on the server for speed, height and collisions; chat reaches players
within 64 units; one character per account can be in the world at a time.

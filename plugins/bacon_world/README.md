# Bacon World

A small multiplayer 3D world that runs in the browser: make a character, walk around
the village with other players, chat with people nearby, fight the skeletons outside
town with either hand, loot what they carried, and level up. There are no classes:
everyone starts the same and will grow through one shared skill tree.

It is also Bacon8's **reference plugin**. Copy this folder to start your own
(see `plugins/README.md` and BACON8.md §9).

**Where it stands, the owner's decisions and what's next: [`BACON_WORLD.md`](../../BACON_WORLD.md)**
at the repository root. This file is the module-by-module reference.

It was called **Web Lobby** (slug `web_lobby`) until 2026-10-21. Old links
(`/games/web_lobby/...`) answer 301 to `/games/bacon_world/...`, and the migrations below
renamed its tables, its game row and its `plugin_states` row.

## What's where

| Path | What it is |
|---|---|
| `lib/bacon_world/plugin.ex` | The plugin: name, version, its game card, its routes |
| `lib/bacon_world/world.ex` | Characters, zones, positions |
| `lib/bacon_world/combat.ex` | Spells, HP/MP, respawn (server-authoritative) |
| `lib/bacon_world/items.ex` | The item catalogue: weapons with EverQuest-style DMG/DLY, shields, a torch, junk |
| `lib/bacon_world/inventory.ex`, `inventory_item.ex` | What a character carries: two hands, 24 bag slots, coins |
| `lib/bacon_world/progression.ex` | Levels, experience, con colours, skill points banked for the tree |
| `lib/bacon_world/melee.ex` | Swing numbers: reach and arc, hit chance, damage, delay |
| `lib/bacon_world/mobs.ex`, `mobs/` | Creatures: spawns and kinds, the rules (`Brain`, pure), the zone process, its keeper |
| `lib/bacon_world_web/game_events.ex` | PlayLive's fighting, looting and inventory events |
| `lib/bacon_world/models.ex` | Which character models players can pick; the humans' slider and hair manifests (`human_assets/0`) |
| `lib/bacon_world/appearance.ex` | `BaconWorld.Appearance`: normalises a look (never trusts the client) |
| `lib/bacon_world/{zone,spell,character_spell}.ex` | Schemas for the plugin's own tables |
| `lib/bacon_world_web/routes.ex` | `/games/bacon_world` |
| `lib/bacon_world_web/play_live.ex` | Character select and the live world |
| `priv/games_repo/migrations/` | `bacon_world_zones`, `bacon_world_spells`, `bacon_world_character_spells` (created as `web_lobby_*`, renamed by `20261021120000`), `bacon_world_items` (`20261022000000`) |
| `priv/repo/migrations/` | the site DB's `plugin_states` row, renamed by `20261021120100` |
| `assets/js/world-character-ui-scene.ts` | The hook (`WorldCharacterUIScene`): front end, world, multiplayer |
| `assets/js/front-ui.ts`, `character-stage.ts` | Character select and creator (HTML) over a lit 3D stage |
| `assets/js/appearance.ts`, `human-factory.ts` | The look model, and building a human from a look |
| `assets/js/character-controller.ts`, `controls-math.ts`, `mouse-filter.ts` | Third-person controls (below); `mouse-filter.ts` repairs remote-desktop mouse-look |
| `assets/js/world-dressing.ts` | The lobby village and its colliders |
| `assets/js/model-manager.ts` | Characters in the scene: loading, their animators, what they hold |
| `assets/js/anim-driver.ts` | The animator: four body channels, strafes, stances, swings with either hand (mirrored) |
| `assets/js/game-world.ts`, `game-ui.ts` | Fighting, looting, the inventory; the EverQuest-style windows and hotbar |
| `assets/js/mobs-view.ts` | Creatures on the client: models, weapons, smoothing, corpses |
| `assets/js/items.ts`, `nameplates.ts`, `asset-url.ts` | Weapon models and icons; names over heads; versioned model URLs |
| `assets/js/lobby-audio.ts` | Sound: recorded effects, nature beds, ambient music |
| `assets/js/__tests__/` | JS unit tests: `sh __tests__/run.sh` in a node container (esbuild + `node --test`) |
| `test/` | Runs with `mix test` |

## Data

Characters are the hub's `game_characters` rows for game `bacon_world`, so they
are not a Bacon World table at all. World-only values sit in the row's JSON maps:
`stats` holds HP, MP, the PvP flag, level, experience, banked skill points, coins and
whether the starter kit was given; `settings` holds the character type (always
"Adventurer" now: there are no classes), model, zone, last position and look. What a
character carries is `bacon_world_items` (one row per occupied slot). The plugin's own
tables, in the games database, are prefixed `bacon_world_`.

## Character models

Players pick from the model files the hub serves under `/models/`
(`priv/static/models`, a volume in production). With no models installed,
set `ENABLE_BUILTIN_MODELS=true` to offer three simple built-in ones.
`MAX_CHARACTER_MODELS` caps the list; a `supported_models.txt` in the models
folder (one relative path per line) limits it to those files. A character whose
model has been removed wears the first model still offered.

The shipped models are the **Bacon8 humans**, `Humans/Male.glb` and `Humans/Female.glb`.
They share the B8 skeleton and 20 CC0 clips from Quaternius' Universal Animation Library.

- The male is built on Blender Studio's CC0 base mesh (v2).
- The female is built on MakeHuman's CC0 body (2026-10-22). Her clothes, hair, lashes and
  brows are MakeHuman CC0 assets, fitted to her.

The game repository builds them all with the scripts in `SourceAssets/Pipeline` (see its
README), along with the animation packs, the weapons (shared grip on the `weapon_r` /
`weapon_l` bones), the skeleton creature and the village kit.

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

The Bacon8 humans and the skeletons don't use `PREFERRED_CLIPS`: `anim-driver.ts` drives
them from the B8 animation packs (`Humans/Anims/B8_<Body>_Anims_{Core,Combat}.glb`, 143
clips; the body's own 20 stand in until they load). It splits the body into four channels
(legs, torso, each arm) so a character can run holding a sword and a shield and swing
either hand while the other keeps its guard. Moving sideways or backwards relative to
where the character faces plays the strafe and backpedal clips, for remote players too.
Left-hand swings are the right-hand clips mirrored at load (the skeleton is symmetric;
checked against a baked mirror, worst error 0.004).

## Looks and the creator

A character's look lives in its `settings["appearance"]`. It holds:

- body type and height;
- seven body and three face sliders (the humans' 13 morph targets);
- skin, eyes and brows;
- a hair style (23 male, 31 female) and, for the male, one of 6 facial hair;
- outfit pieces with their colours.

`BaconWorld.Appearance` normalises every look the client sends:

- unknown keys are dropped and sliders clamped;
- colours must be `#RRGGBB`;
- garments come from a fixed list;
- hair styles come from the installed manifest. A retired style id (one that the manifest's
  `aliases` map) becomes the style that replaced it.

The body type picks the model and can't change after creation. Characters made before looks
existed get the default look for their model.

Events: `three_ui_create_character` (replies `%{ok, character_id}` or `%{ok: false, error}`),
`three_ui_update_appearance` (refused while that character is in the world) and
`fetch_appearances` (other players' looks, at most 64 ids). `/models` doesn't serve `.json`
(BACON8.md invariant 17), so the LiveView passes the humans' manifests in
`data-human-assets`.

`human-factory.ts` builds each human from its look:

- The geometry is shared, and tints are per character. A grey texture's material carries a
  `tint_gain` in its glTF extras: 1.25 for skin and clothes, 2.0 for hair.
- Each outfit gets cached index buffers that hide the skin under its clothes, and the parts of
  a garment worn under another, such as trousers under a shirt's hem or boots under trousers.
  These come from the `_region` vertex attribute and the manifest's `hides`.
- Hair and facial hair are bound to the body's bones and take the same morphs. A hair style's
  scalp decal is drawn with a polygon offset.

## The village

`world-dressing.ts` lays out the lobby from `World/B8_Props.glb` and `World/B8_BuildKit.glb`:
the plaza and well, a market, seven houses, a camp, a training yard, a farm, trees and rocks,
merged per material (about 210k triangles in ~45 draw calls). It keeps the local player out
of its circle and box colliders (the controller's `collide` option), and its fog, fill light
and lamps follow the day/night cycle.

## Controls

RaysSpaceSim's on-foot movement, EverQuest's mouse with the cursor free, and Black
Desert's mouse buttons with mouse-look on (`character-controller.ts`; numbers in
`controls-math.ts`):

| Input | |
|---|---|
| Click the game | mouse-look on: free look, the character turns to face where it moves |
| Left / right button (mouse-look on) | swing the left / right hand; held, keep swinging as the weapon's delay allows. A two-hander: left quick, right heavy. The character turns to face where you look |
| Hold right button (cursor free) | steer: the character faces the camera; W runs, S backpedals (slower), A/D strafe, diagonals turn the body 45° |
| Right-click (cursor free) | a corpse: loot it; a creature: target it |
| Q E F Z X | special attacks, earned in the skill tree (locked for now) |
| 1 | Throw Stone (PvP) |
| I / G / Tab | inventory / loot the nearest corpse / next target (creatures first) |
| WASD / arrows | move relative to the camera; Shift sprints, C crouches, Space jumps |
| Wheel | zoom (1.5 to 9 m) |
| Ctrl | free the cursor |
| Esc | close a window, or the game menu (mouse, sound, effects / nature / music volume, resolution, log out) |
| Enter / `/` | chat / a slash command |

A slow frame moves the character its full distance (in 50 ms steps), so a machine or
remote-desktop session that renders slowly doesn't play in slow motion. Resolution
"Auto" lowers the rendering resolution while the game runs under ~38 fps. The menu shows
the frame rate.

**Remote desktop.** Over RDP, Chrome re-centres a locked pointer and the remote end hears
about it a round trip later. Until then, every report is a jump of a third of the page.
`mouse-filter.ts` tracks both cursors and recovers the hand's real movement. A local mouse
passes through untouched. While it is repairing jumps, the menu's FPS line says
"remote-desktop mouse (N fixed)". There is no camera-smoothing option any more.

## Fighting, creatures and loot

Skeletons live in three camps outside the village (`BaconWorld.Mobs.Spawns`): the Old
Graveyard (decaying skeletons, levels 1-2), the Ruined Chapel (2-3) and the Barrow
(skeleton warriors, 3-5, with two-handers). Each holds the weapon it will most likely
drop. The village is safe: no creature goes within 40 m of the spawn, and a chase ends
there or 30 m from the creature's home, when it runs back and heals.

One zone process runs them for the whole cluster (`BaconWorld.Mobs.Zone`, registered with
`:global`; `Keeper` on every node starts it where nobody has), ten times a second, against
the players in the zone's Presence (position, level, dead). It broadcasts events and,
five times a second, the positions of moving creatures on `bacon_world:mobs:<zone>`.

A swing (`melee_attack`) hits what is in front of you within the weapon's reach: one
creature for one-handers and fists (your target if it's in the arc), up to three for
two-handers. Each hand has its own swing timer (the weapon's DLY); damage and hit chance
are EverQuest-shaped (`BaconWorld.Melee`). A creature's attack on you is applied by your
own LiveView, which owns your HP. Kills give experience by con (grey gives none), a level
gives full HP/MP and banks a skill point for the tree.

Corpses: the top damage dealer may loot alone for a minute, then anyone; one looter at a
time; coins go straight to the looter; a corpse decays after four minutes, or seconds
after it's emptied, and the creature respawns later. Inventory: click an item to pick it
up, click a slot to put it down or swap; right-click to equip or unequip. Everyone sees
what you hold (`zone_gear`, and `gear` in presence). New and existing characters get a
starter kit once: a short sword in hand and a shield, dagger, club, spear, quarterstaff
and torch in the bags, one of each stance.

## Models on the volume

These are gitignored, and the owner syncs them to the models volume with
`sync-models-to-k8s.sh`:

| Folder | What it holds |
|---|---|
| `Humans/` | `Male.glb` and `Female.glb` (meshopt-compressed), `Male.json` and `Female.json`, `README.txt`, `CREDITS.md` |
| `Humans/Hair/` | 23 male hair, 6 facial hair and 31 female hair GLBs, `icons/`, `hair_manifest.json` (with `aliases`) |
| `Humans/Anims/` | the four animation packs |
| `Weapons/` | `B8_Weapons.glb` (43 weapons, shields and tools in bone space) and `icons/` |
| `Mobs/` | `B8_Skeleton.glb`, the skeleton creature, rigid on the B8 male armature |
| `World/` | `B8_Props.glb` and `B8_BuildKit.glb` |

Without them, the site falls back to whatever is on the volume.

Every model URL carries a version (`?vsn=<hash of size and mtime>`, from
`BaconWorld.Models.asset_versions/0` in `data-human-assets`), so an updated file is a new
URL and Plug.Static caches it as immutable; unchanged files stay cached. A `.glb.gz`
beside a `.glb` is served compressed (the hub's `/models` static has `gzip: true`).

## Sound

`assets/js/lobby-audio.ts` plays real recordings from `/audio/world/` (CC0; credits in
`priv/static/audio/world/CREDITS.md`): a voice for jumping, swinging, pain and death
(a man's or a woman's, by the character's body),
landings, footsteps by surface (cobbles on the plaza, gravel on the paths, grass), weapon
swings, hits on bone and on flesh, bones breaking, coins, chimes. Each kind has several
takes and a little pitch variety. Under it: birds and wind by day, crickets by night, the
campfire when you're near it, and a quiet ambient music bed (`music_ambient.mp3`, made by
the game repository's `SourceAssets/Pipeline/build_audio.py`).

The game menu has a Sound switch (the master) and Effects, Nature and Music volume sliders.
They are remembered per browser (`bacon_world:volume_*`, 0–100). Browsers allow sound only
after the first click or key press.

## Multiplayer

All on the hub's PubSub and Presence, topics prefixed `bacon_world:`. Moves are
checked on the server for speed, height and collisions; chat reaches players
within 64 units; one character per account can be in the world at a time. Names over
heads are sprites placed in the frame they're drawn (no box, coloured by con for
creatures; `nameplates.ts`).

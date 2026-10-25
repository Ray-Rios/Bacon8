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
| `lib/bacon_world/combat.ex` | HP/MP, PvP flags, respawn (server-authoritative); spells later (Throw Stone is retired) |
| `lib/bacon_world/items.ex` | The item catalogue: weapons with EverQuest-style DMG/DLY, shields, a torch, junk, underwear and cloth armour |
| `lib/bacon_world/inventory.ex`, `inventory_item.ex` | What a character carries: two hands, five worn slots, 24 bag slots, coins |
| `lib/bacon_world/merchants.ex` | NPC traders: Tilda the clothier, her stock, reach and prices |
| `lib/bacon_world/progression.ex` | Levels, experience, con colours, skill points banked for the tree |
| `lib/bacon_world/melee.ex` | Swing numbers: reach and arc, hit chance, damage, delay |
| `lib/bacon_world/mobs.ex`, `mobs/` | Creatures: spawns and kinds, the rules (`Brain`, pure), the zone process, its keeper |
| `lib/bacon_world_web/game_events.ex` | PlayLive's fighting, looting and inventory events |
| `lib/bacon_world/mounts.ex` | Mounts: the dragon drakes, who owns which (entitlement kind `bacon_world_mount`; admins ride all), their store items (`ensure_store_products/0`) |
| `lib/bacon_world_web/mount_events.ex` | PlayLive's mount events (`mounts_fetch`, `mount_summon`, `mount_dismount`), the presence's `mount`, `zone_mount` |
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
| `assets/js/character-controller.ts`, `controls-math.ts`, `mouse-filter.ts` | Third-person controls (below), mounted movement and flight (double-tap Space); `mouse-filter.ts` repairs remote-desktop mouse-look |
| `assets/js/world-dressing.ts` | The lobby village and its colliders |
| `assets/js/surface-textures.ts` | CC0 surface textures on the untextured models, by material name (triplanar, no UVs) |
| `assets/js/model-manager.ts` | Characters in the scene: loading, their animators, what they hold |
| `assets/js/anim-driver.ts` | The animator: four body channels, strafes, stances, swings with either hand (mirrored) |
| `assets/js/game-world.ts`, `game-ui.ts` | Fighting, looting, the inventory; the EverQuest-style windows and hotbar |
| `assets/js/mobs-view.ts` | Creatures on the client: models, weapons, smoothing, corpses; dragons (Baconator: moves, breath, roar) |
| `assets/js/dragon-view.ts` | The B8 dragon: loading, a rig that picks its own locomotion (ground or air), one-shots, fire breath, the mounts' hue shift |
| `assets/js/mounts.ts` | Mounts on the client: the dragon under its rider, the rider seated on the saddle bone |
| `assets/js/npcs-view.ts` | Merchants on the client: built as humans, picked by proxy cylinders, face you while trading |
| `assets/js/wardrobe.ts` | Gear slots, what each worn item puts on the body and hides, and the bone corrections (joint offsets, relaxed fingers) |
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

- Both are built on MakeHuman's CC0 body: the female 2026-10-22, the male 2026-10-24. Their
  clothes, hair, lashes and brows are MakeHuman CC0 assets fitted to each; underwear, tank,
  shorts and trousers are shells made from each body.

The asset pipeline builds them all with the scripts in `library/pipeline/scripts` (see its
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
- body and face sliders (`appearance.ts` `SHAPES`): build, muscle, shoulders, belly, hips,
  glutes, chest size (his pectorals), glute lift, waist, arms, thighs, calves and three face
  sliders for both bodies; for the female also the chest's height, spacing and shape. The
  creator shows them in sections (Body, Chest, Glutes, Arms and legs);
- skin, eyes and brows;
- a hair style (18 male, 31 female) and, for the male, one of 6 facial hair.

Clothes are not part of the look (since 2026-10-23): they are items (below).

`BaconWorld.Appearance` normalises every look the client sends:

- unknown keys are dropped and sliders clamped;
- colours must be `#RRGGBB`;
- an old look's `outfit` is dropped;
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
- What is worn comes from the gear (`create(look, body, gear)`, `setWorn`). Each combination
  gets cached index buffers that hide the skin under its clothes, and the parts of a garment
  worn under another, such as trousers under a shirt's hem or boots under trousers. These
  come from the `_region` vertex attribute and the manifest's `hides`; underwear hides
  nothing.
- A wardrobe garment (the female's v3 underwear and cloth) takes a design: a packed texture
  (R shade, G trim, B accent, A cut-out, from `Humans/Wardrobe/`) tinted with the item's
  main, trim and accent colours by a patched `MeshStandardMaterial`, alpha-tested.
- After the animation each frame (`postAnimate`): joint offsets for morphs that move bones,
  the posture correction (manifest `posture`: `pelvis_tilt_deg` tucks the pelvis, `spine_deg`
  turns spine_01..03, `clavicle_deg` [forward, down] brings the shoulders forward and down,
  `arm_out` turns each arm out by what it is doing (`CharacterAnimator.armSets()`),
  `free_hand_deg` turns an empty hand, `relaxed_hand` replaces the default finger curl; hers is
  24 / [-24, -9, 9] only, his is in `mhm_build.py`'s `POSTURE`) and relaxed fingers on empty
  hands. Each starts from what the animation left in the bone, so nothing compounds
  on a bone no clip keys. Clips load through `fixForearmTwist`, which repairs the packs'
  forearm twist tracks (a pipeline bug that wrung the forearms in weapon clips).
- Hair and facial hair are bound to the body's bones and take the same morphs. A hair style's
  scalp decal is drawn with a polygon offset.

## The village

`world-dressing.ts` lays out the lobby from `World/B8_Props.glb` and `World/B8_BuildKit.glb`:
the plaza and well, a market, seven houses, a camp, a training yard, a farm, trees and rocks,
merged per material (about 210k triangles in ~45 draw calls). It keeps the local player out
of its circle and box colliders (the controller's `collide` option), and its fog, fill light
and lamps follow the day/night cycle.

`surface-textures.ts` gives those pieces, the ground, the weapons and the skeleton real
surfaces: each material name (`M_Stone`, `M_RoofTile`, `W_Leather`, ...) maps to a CC0 texture
set in `/models/World/Textures/` (credits beside them), projected triplanar in the mesh's own
space, so the models need no UVs. The material keeps its colour and gains the texture's
pattern, normals, roughness and occlusion. Pieces are merged per family and material (the kit
and the props share names but not textures). The Esc menu's Textures button turns it off
(after a reload).

## Controls

RaysSpaceSim's on-foot movement, EverQuest's mouse with the cursor free, and Black
Desert's mouse buttons with mouse-look on (`character-controller.ts`; numbers in
`controls-math.ts`):

| Input | |
|---|---|
| Click the game | mouse-look on: free look, the character turns to face where it moves |
| Left / right button (mouse-look on) | swing the left / right hand; held, keep swinging as the weapon's delay allows. A two-hander: left quick, right heavy. The character turns to face where you look |
| Left drag (cursor free) | turn the camera around the character (she keeps facing her way); letting go doesn't lock the pointer |
| Hold right button (cursor free) | steer: the character faces the camera; W runs, S backpedals (slower), A/D strafe, diagonals turn the body 45° |
| Right-click (cursor free) | a corpse: loot it; a creature: target it; a merchant: trade |
| Q E F Z X | special attacks, earned in the skill tree (locked for now) |
| I / G / Tab | inventory / loot the nearest corpse / next target (creatures first) |
| R | interact: the targeted or nearest person in reach (a merchant opens her wares). Reserved for interactions (doors and the like later) |
| WASD / arrows | move relative to the camera; Shift sprints, C crouches, Space jumps |
| Wheel | zoom (1.5 to 9 m) |
| Ctrl | free the cursor; press again for mouse-look (Ctrl with a movement key never reaches the browser, so no Ctrl+A select-all) |
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
drop. The skeleton model is rigged on the male's armature (since 2026-10-24) and plays his
animation packs. One-handed weapons with a single striking side are turned 180 degrees in
the hand (`HOLD` in `items.ts`): add every new one there. The village is safe: no creature goes within 40 m of the spawn, and a chase ends
there or 30 m from the creature's home, when it runs back and heals.

One zone process runs them for the whole cluster (`BaconWorld.Mobs.Zone`, registered with
`:global`; `Keeper` on every node starts it where nobody has), ten times a second, against
the players in the zone's Presence (position, level, dead). It broadcasts events and,
five times a second, the positions of moving creatures on `bacon_world:mobs:<zone>`.

A swing (`melee_attack`) hits what is in front of you within the weapon's reach: one
creature for one-handers and fists (your target if it's in the arc), up to three for
two-handers. The arc is 90 degrees for one-handers and 110 for two-handers, aimed where the
camera looks; right against you it widens to 160, and nothing behind you is ever hit. Each hand has its own swing timer (the weapon's DLY); damage and hit chance
are EverQuest-shaped (`BaconWorld.Melee`). A creature's attack on you is applied by your
own LiveView, which owns your HP. Kills give experience by con (grey gives none), a level
gives full HP/MP and banks a skill point for the tree.

PvP is melee too: when you and another player are both flagged (`toggle_pvp`), your swing
hits them if they stand in its reach and arc (`GameEvents.pvp_swing/3`, against the zone's
Presence positions, so the reach has 0.8 m of slack). The hit is broadcast as `:pvp_hit`
and applied by the target's own LiveView, as a creature's is; any change to a player's
health (a hit, regeneration, a death, a respawn) goes to the zone as `:zone_hp`, so target
windows follow it and others see the death and the respawn. Throw Stone, the old
web-lobby test spell, is retired (`Combat` no longer grants or lists it; its rows stay
in the database until a cleanup migration is OK'd).

Picking a player with the mouse tests a box around each one, never their meshes: three's
raycast against a skinned, morphing mesh skins every vertex on the CPU, which froze the
game on every swing at a player.

**Clothes and underwear are items.** Five worn slots sit beside the hands: `under_top`,
`under_bottom`, `chest`, `legs`, `feet`. Underwear is layered under the rest and comes off
like anything else. New characters, and older ones at their next login, get the cream linen
set and a purse of 100 copper (1 gold) once (`stats` flags `starter_wear`, `starter_purse`).
Six underwear sets (linen, athletic, rose lace, coral, polka dot, emerald; 20 to 120 copper
a piece) and eight pieces of cloth armour (tunic, blue-dyed tunic, tank, wool sweater,
trousers, shorts, cloth shoes, tall leather boots). Coins are EverQuest's: 10 copper make a
silver, 10 silver a gold, 10 gold a platinum (`items.ts` `money`).

Health rides in each player's presence meta (`hp`, `max_hp`), so target windows and the
player list keep it across presence syncs (without it a hit player's bar read full again
within a tenth of a second). Regeneration (a twelfth of the pool every 4 s, not while dead)
runs on one timer per LiveView: each login starts a new chain and orphans the old.

**Merchants** (`BaconWorld.Merchants`). Tilda Threadwell, Clothier, stands in the village
(15.5, -6.7 m) and sells all 20 wearables at their value; she buys anything for a quarter of
its value (at least 1 copper). Trading needs you within 6 m and alive: R (the targeted or
nearest person in reach), or right-click her with the cursor free (`merchant_open`, `merchant_buy`, `merchant_sell`); walking away closes the
window. In her window, right-click a row to buy it (or select it and press Buy); with her
window open, right-click a stack in your bags to sell it (the tooltip shows the offer).
`fetch_mobs` lists the zone's merchants.

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
| `Humans/` | `Male.glb` and `Female.glb` (meshopt-compressed), `Male.json` and `Female.json`, `Wardrobe/` (hers) and `Wardrobe/Male/` design textures, `README.txt`, `CREDITS.md` |
| `Humans/Hair/` | 18 male hair, 6 facial hair and 31 female hair GLBs, `icons/`, `hair_manifest.json` (with `aliases`) |
| `Humans/Anims/` | the four animation packs |
| `Weapons/` | `B8_Weapons.glb` (43 weapons, shields and tools in bone space) and `icons/` |
| `Mobs/` | `B8_Skeleton.glb`, the skeleton creature, rigid on the old (v2) B8 male armature, and `Anims/`, that armature's packs |
| `World/` | `B8_Props.glb` and `B8_BuildKit.glb`; `Textures/`: surface texture sets (`<set>_c/_n/_r.webp`) and `CREDITS.md` |

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
the asset pipeline's `library/pipeline/scripts/build_audio.py`).

The game menu has a Sound switch (the master) and Effects, Nature and Music volume sliders.
They are remembered per browser (`bacon_world:volume_*`, 0–100). Browsers allow sound only
after the first click or key press.

## Multiplayer

All on the hub's PubSub and Presence, topics prefixed `bacon_world:`. Moves are
checked on the server for speed, height and collisions; chat reaches players
within 64 units; one character per account can be in the world at a time. Each position
packet carries `m`, the body's motion flags (1 crouching, 2 airborne), sent at once when
they change, so others see you crouch and jump; every accepted swing is broadcast as
`:zone_swing` (hand, heavy, delay) and plays on the swinger's animator on every other
screen. Names over
heads are sprites placed in the frame they're drawn (no box, coloured by con for
creatures; `nameplates.ts`).

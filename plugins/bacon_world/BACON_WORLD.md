# BACON_WORLD.md: Bacon World, where it stands and where it's going

**What this file is.** This is the working notebook for **Bacon World**, the 3D multiplayer game
that runs in the browser. It is Bacon8's reference game plugin (`plugins/bacon_world`, at
`/games/bacon_world`).

**Read it first** when you pick the game up in a new session.

Related documents:

- `BACON8.md` covers the hub (plugin contract §9, invariants §6, workflow §14).
- `plugins/bacon_world/README.md` is the module-by-module reference.
- The asset pipeline (`C:\Bacon8\library\pipeline`, moved out of RaysSpaceSim on 2026-10-23) builds the art. See `library/pipeline/scripts/README.md`.

**Rules for editing this file.** They are the same as BACON8.md's:

- Public-safe. No hostnames, IPs, credentials, cluster names or anything specific to one
  deployment.
- Facts dated. The owner's decisions are recorded, not re-argued.

Last update: **2026-10-29**.

---

## 1. What Bacon World is

A small online RPG in the browser, written with three.js and Phoenix LiveView:

- Make a character in a creator: body type, sliders, skin, eyes and hair. Everyone starts in
  plain cream underwear; clothes are cloth armour you buy, find and wear.
- Walk a village with other players and chat with people nearby.
- Fight skeletons outside town with either hand, loot their corpses EverQuest-style and level up.
- Take on Baconator, a fire-breathing dragon boss in his lair, and ride (and fly) dragon mounts
  bought in the Bacon Store.

It is also the template other Bacon8 games copy.

**Direction.** It should feel like a classic MMO, with:

- EverQuest's windows, looting and con colours;
- RaysSpaceSim's on-foot controls, and its double-tap-Space flight on mounts (no rolls);
- Black Desert's mouse-button attacks;
- Path of Exile's single shared skill tree.

All of it uses our own or CC0 art. Every 3D asset is built by scripts in the game repository,
so it can be rebuilt and changed.

## 2. State on 2026-10-29

This section used to be a dated log of every delivery (2026-10-22 to 2026-10-29, about 720 lines, with the
tuning numbers and the owner's play-test notes). It was replaced on 2026-10-29 by the inventory below. The log
is in git: `git log -p --follow -- plugins/bacon_world/BACON_WORLD.md` (the last commit that still had it is the
one before "Docs: current state"). Look there when a symptom looks familiar, for example a two-handed grip that
"was fixed" before. The lessons that came out of it are in §6 and §7.

Everything below is committed and deployed. Production needs the models synced
(`sync-models-to-k8s.sh`) for the terrain and the large models; without the terrain files the game falls back to a
flat round island.

### The world

- **Crater Lake** is the starter zone: the owner's World Creator heightfield (4096 m square, heights -306 to
  +689 m), built into game files by `library/pipeline/scripts/terrain_build.py` (`World/Terrain/` on the models
  volume). The town's centre is the game's origin and its ground is height 0. The server (`BaconWorld.Terrain`,
  `BaconWorld.Water`) answers height, water and walkable questions; the browser (`terrain.ts`, `terrain-world.ts`)
  draws 32 x 32 chunks with level of detail, painted by slope and height. One water plane is the sea and every lake.
- **Water**: wading to 1.2 m; deeper water is swum (slower, no jumping, fighting or fishing), **C** swims down and
  **Space** up. Mounts swim too. `water.ts` mirrors `BaconWorld.Water` with the same tests on both sides.
- **Fishing**: Old Bram, Angler, sells the pole; **R** casts and reels in; the Millpond and the sea have their own
  catches. The bobber is a curl of bacon (`crafted.ts`).
- **Sound**: placed sound (pan, distance, low-pass, a voice cap, a master compressor), spell schools, dragon and
  mount voices, beds and music by mood. CC0 sources, built by `library/pipeline/scripts/audio/build_audio_v2.py`.
  Real surf, splash and kraken recordings are still wanted.
- **The sky and the glass**: the sun and moon sit in the sky; the player's personal glass colour reaches the game's
  windows through `--bwg-*` CSS variables (unset on the default theme).

### Building (the owner's "build mode")

- The backquote key toggles build mode (`build-world.ts`, `build-ui.ts`, `placed-view.ts`; server
  `BaconWorld.Building`, `BuildEvents`; tables `bacon_world_placements`, `bacon_world_asset_rules`,
  `bacon_world_seeds`). A searchable window lists the catalogue (128 models: props, trees and plants, rocks,
  building pieces, every creature kind, NPC templates). Place, Shift-place, pick up, turn, raise, size, remove, undo.
- **Who may place what**: each asset has a lowest role (`admin > gm > moderator > editor > member`); admins change it
  in the window. Every check is on the server, with a burst limit.
- **The village and the camps are placements**, seeded once from `priv/seed/*.json` (`Building.ensure_seeded/1`).
  What builders move or delete stays that way. Drawn instanced (one draw call per kind and part).
- **Binding stones** (`P_Waystone`, admin-only; one by the village square): within 100 m only GMs and admins may
  build (`Building.protected?/4`). **R** beside one binds you there; Recall and respawn use the bind.
- Placed creatures are spawn points (count 1-12, spread 0-40 m); placed merchants trade with their template's stock.

### Combat and creatures

- Melee for both hands (arcs 90 degrees one-handed, 110 two-handed), looting EverQuest style (G takes everything),
  levels, coins, con colours, PvP with red names. Bows never run out of arrows (cone hit along the aim; arrows fly
  and stick for four seconds).
- **Spells and skills**: mana, cast times, a spell bar (2x10) and skills on Q E F Z X; the **skill tree** (K, Path of
  Exile style, one tree for everyone; the editor is `/admin/bacon_world/skills`).
- **Groups** (`BaconWorld.Groups`): up to 20, `/invite`, `/accept`, `/disband`, `/makeleader`, `/g`; experience is
  split by level (`Groups.shares/2`), loot by anyone in the killer's group, coins split among those near.
- **Creatures**: skeletons, giant and plague rats, goblins and goblin archers, orcs and orc warlords, and two
  bosses: **Baconator**, the dragon (level 12, his own camp on the plateau NE of the crater), and the **Kraken**
  (level 16, roams the deep water of Crater Lake; its specials are grab, ink and maelstrom, wound up so players can
  see them coming). Camps are placements now.
- **Mounts** (entitlement kind `bacon_world_mount`, sold in the Bacon Store; the stablemaster Rowena Ashby chooses
  one): three drakes that fly (double-tap Space, like RaysSpaceSim) and the Abyssal Kraken that swims. Riders fight
  with the mount's moves (claw and fire breath; tentacle lash and maelstrom).

### Characters and items

- Two bodies, both built on MakeHuman's CC0 assets (§5): the female and the male, with Black Desert style body
  sliders, MakeHuman hair styles and clothes. Everyone starts in underwear; clothes are cloth armour items.
- **Items** (`items.ex`, `inventory.ex`): weapons by set (dagger, sword, axe, maul, spear, halberd, staff, bow,
  fishing pole), armour in slots including **head**, EverQuest coins, merchants (Tilda Threadwell, Clothier; Old Bram;
  the stablemaster; villagers). **The grill fork** (the site's front-page fork) is the starter one-handed piercing
  weapon and the **Robin Hood hat** is a wearable (head slot) and placeable object; both, the bow's arrow and the
  bacon bobber are drawn in code (`crafted.ts`), so there is nothing to sync.
- **Two-handed weapons** are held by posing the weapon, not the arms (`two-hand.ts`, `human-factory.ts`
  `twoHandDrive`): both hands are put on the weapon every frame with a two-bone IK. If a grip looks wrong, render
  both bodies standing, running and through every swing before changing anything (§6).
- Player names are Bacon8 blue, red with PvP on. Windows are draggable (`window-drag.ts`); the game's card on
  /games has Baconator's head on its front.

### Tests

The plugin's Elixir tests run with the hub's suite; the JavaScript tests run with
`plugins/bacon_world/assets/js/__tests__/run.sh` (115 pass on 2026-10-29). Look-checks are done in the three.js
harness (see §8).

## 3. The owner's decisions (settled; don't re-litigate)

| Date | Decision |
|---|---|
| 2026-10-21 | **No classes.** Everyone starts the same and grows through **one shared skill tree, Path of Exile style, with a single central start**. Each level banks a skill point (`BaconWorld.Progression`). `character_type` is always "Adventurer". |
| 2026-10-21 | **Hands on the mouse buttons, Black Desert style**, with mouse-look on (pointer locked): left button = left hand, right = right hand; held = keep swinging. A two-hander: left quick, right heavy. **Q E F Z X** are reserved for the tree's special attacks. |
| 2026-10-21 | **Right-button steering stays** with the cursor free (EverQuest): the character faces the camera; W runs, S backpedals, A/D strafe. *Never remove it.* |
| 2026-10-21 | **RaysSpaceSim's on-foot controls, minus flight**: camera-relative WASD, the character turns to face its movement, the same speeds and acceleration (`controls-math.ts`). |
| 2026-10-21 | **EverQuest feel**: names over heads with no box, con colours, a target window, an inventory window (click to carry, click to drop or swap, right-click to equip), corpses looted killer-first, one looter at a time, combat text in the chat log. |
| 2026-10-21 | **Skeleton creatures** live in camps outside the village; the village is safe. |
| 2026-10-21 | **Real recorded sounds** for grunts, landings, hits and swings (CC0 recordings), **not synthesized**. |
| 2026-10-22 | **Volume sliders**, not on/off switches, for effects, nature and music. |
| 2026-10-25 | **Sound is immersive but never loud or jarring**: several takes of everything, never the same take twice, minimum gaps, distance dulling, music that rests between tracks. Real CC0 recordings, still not synthesized. |
| 2026-10-22 | **No camera-smoothing option.** Remote-desktop jumps are repaired by `mouse-filter.ts`; a local mouse is untouched. |
| 2026-10-21 | **Assets are ours or CC0.** Epic's content stays Unreal-only, and no paid UAL Pro/Source files from mirrors. **No DAZ-derived meshes**: the owner's two DAZ-based female files must not be used, so the female is built on MakeHuman (owner's choice, 2026-10-21). |
| 2026-10-23 | **Asset rule widened on purpose: ours, CC0, or licensed for commercial use, credited, with the source files never redistributed.** Licensed sources (Substance .sbsar and the like) live in the gitignored shared library `C:\Bacon8\library\` with a licence table; only what we bake from them ships, and it goes on the credits page. The DAZ and Epic exclusions above still stand. |
| 2026-10-23 | **Substance materials are baked in Blender** with Adobe's Substance 3D add-on (`b8_substance.py`). The library's unverified files aren't used until their source is recorded; files that can't be used legally are deleted. |
| 2026-10-23 | **The asset pipeline lives in `C:\Bacon8\library\pipeline`** (moved out of RaysSpaceSim; not a git repository): `scripts/`, `Characters/` (the B8 skeleton and human blends), `Animations/`, `out/`. The v1 humans were deleted: their source files and the copies imported into Unreal. |
| 2026-10-23 | **The MakeHuman male look `m2` is approved as is.** Carry on with his rebuild; his animations must not show A-pose fanned fingers. |
| 2026-10-21 | The female should be **stunning**. She is editable in Blender (`library/pipeline/Characters/B8Human/B8_Female_MPFB.blend`) so the owner can sculpt her later. |
| 2026-10-23 | **No clothes in character creation.** New characters start in **cream bikini underwear**. |
| 2026-10-23 | **Underwear is equipment**: a top and a bottom, separate items, layered under clothes and armour, and removable. They are ordinary 3D gear: no content warnings around them. |
| 2026-10-23 | **At least five underwear sets for sale from an NPC merchant.** The old clothes meshes become **cloth armour**. |
| 2026-10-23 | **EverQuest currency**: platinum, gold, silver and copper. |
| 2026-10-23 | **Throw Stone is removed**: it was only a test from the old web-lobby game. |
| 2026-10-23 | **R is reserved for interactions** (NPCs now; doors and the like later). Right-clicking a merchant with the cursor free still works too. |
| 2026-10-23 | **Body sliders take their cues from Black Desert Online**: more control over the chest (call it "chest", not "bust"), glutes ("glutes", not "seat"), waist and limbs. |
| 2026-10-24 | **More monsters, starting with a boss: Baconator, a dragon** (original design; the owner's reference art only sets the mood). **The dragon's rig doubles as the mounts'.** |
| 2026-10-24 | **Mounts are for sale** (Bacon Store) **and fly like RaysSpaceSim: double-tap Space** to take off and land, **no barrel rolls**. |
| 2026-10-24 | **Old character rigs and files are removed** (moved aside for deletion). The male and female share one skeleton definition, each with its own fit; that's what we work with. |
| 2026-10-24 | **The dragon is realistic, not cartoony**: jawline, muscle, scaly skin, fiery red serpent eyes, leather wings, detailed horns (owner, on the first cut). |
| 2026-10-24 | **The skill tree**: Path of Exile style, starting in the middle and radiating out in six directions; **Recall** (to the bind point) is everyone's level-1 skill; the first six nodes are a heal, a fireball, +10 HP, +10 MP, a root and a spin attack; one node a level, joined to what you have. The owner extends it on an admin page by dragging spells, skills and buffs onto nodes. |
| 2026-10-24 | **Skills go on Q E F Z X; spells on their own bar, two rows of ten, bottom right** by default. |
| 2026-10-24 | **A stablemaster NPC** chooses which of the account's mounts M summons. |
| 2026-10-26 | **Esc clears the selected target first**; with no target it opens the menu. A target that dies or respawns is dropped. |
| 2026-10-26 | **Looting: G takes everything** from the nearest corpse with no window, unless the inventory is full. An empty corpse opens no window (G or click). |
| 2026-10-26 | **The world is an island in an ocean** that covers everything that isn't land, with **a small fishing lake near the town** (the Millpond). **Fishing is in the game.** (On Crater Lake, next row, the sea fills the bay and runs off past the open south edge; the other edges are mountain ridges.) |
| 2026-10-26 | **The starter zone is Crater Lake**, the owner's World Creator map (4096 m square), with the town on the flat by the bay south of the crater. Zones are World Creator heightfields, exported as 16-bit RAW with their Min/Max, made into game files by `terrain_build.py`. Players reach other zones through zone lines at natural chokepoints (EverQuest style); seamless streaming isn't planned. |
| 2026-10-26 | **The world is built in game, by people, not by asking Claude.** Players (and the owner) place and delete objects in the world: ground types, building pieces, rocks, trees, bushes, everything, creatures and NPCs included. Claude makes the assets; what each role may place is locked by role (for example, only admins place boss creatures). |
| 2026-10-26 | **Binding stones** (admins only place them): players set their spawn point at one, and nobody may build within a radius about the size of the town around one. |
| 2026-10-26 | **Who may place what is set in game by admins, item by item.** Guests may place nothing. There are **no limits** per player and **nothing decays**. **Anyone allowed to place a kind of object may also delete any object of that kind**, whoever placed it. |
| 2026-10-26 | **Characters swim.** Deep water is open to everyone; creatures don't follow. |
| 2026-10-27 | **The second boss is the Kraken**, in the middle of Crater Lake: highly detailed, "the stuff of nightmares" (original design; the owner's reference art only sets the mood). **It is also a mount for sale: it can't fly, it swims very fast.** |
| 2026-10-27 | **Two-handed weapons start over**: no more fitting library clips; the arms follow the weapon (two-hand.ts). |
| 2026-10-27 | **Diving**: in deep water C swims down, Space swims up, and jumps at the surface. **Mounts swim** too (no walking on water). |
| 2026-10-27 | **Under water is only lightly tinted** (the owner: the murk "was a bit much"), and nothing may change the fog's kind at run time (it rebuilds every shader). |
| 2026-10-27 | **The boss Kraken is 1.5 times its first size and roams the lake freely** (no set path). |
| 2026-10-27 | **Mounts attack.** The dragons breathe fire and claw; the Kraken's moves were ours to choose (Tentacle Lash, Maelstrom). |
| 2026-10-28 | **Build mode is the backquote key (`` ` ``).** Click something your role may use to pick it up and move it; holding it, the right button turns it gently; a right-click alone deletes it. A searchable menu lists what can be brought into the world. |
| 2026-10-28 | **GMs and admins place and remove NPCs and creatures** (the defaults; admins can change any asset's role in game). |
| 2026-10-28 | **More creatures: rats, goblins and orcs**, beside the skeletons and the bosses. |
| 2026-10-28 | **A bow, and no arrows to manage: bows fire endless arrows.** |
| 2026-10-28 | **The village and the camps become placements.** Only admins and GMs may edit a town: nothing within **100 m** of a binding stone (was 70 m in the plan). |
| 2026-10-28 | **Groups, EverQuest style, up to 20; no raids.** Experience is split by level weight with a small group bonus; grey-con, dead or far (100 m) members get none. Anyone in the group may loot during the lock minute, one at a time; coins split evenly among the members near. |
| 2026-10-29 | **The site's grill fork is the starter one-handed piercing weapon; the Robin Hood hat is a wearable hat and a placeable object; the bow shoots the hat's arrow; the fishing bobber is bacon.** |
| 2026-10-21 | Targets for the content push: **20+ hair styles per sex**, more weapons, buildable pieces, **50+ props**, finished weapon animations, body morphs. **Everything lands in Bacon World first**, character creation included. |

## 4. How it fits together

**Server** (`plugins/bacon_world/lib`):

- `BaconWorld.World`: characters, zones, positions.
- `Appearance`: normalises looks and never trusts the client. It maps retired hair ids
  through the manifest's aliases.
- `Items`: the catalogue, with EverQuest DMG/DLY.
- `Inventory`: the `bacon_world_items` table.
- `Melee`.
- `Progression`.
- `Mobs`: `Spawns`, the pure `Brain`, a cluster-wide `Zone` process under `:global`, and a
  `Keeper` on every node.
- `Combat`: HP/MP, PvP flags, respawning (Throw Stone is retired).
- `Merchants`: the NPC traders (Tilda the clothier), their stock, reach and prices.
- `Models`: the model list, `human_assets/0` and the versioned URLs.
- `BaconWorldWeb.PlayLive`: select, the creator, the world. `game_events.ex` holds its fighting,
  looting and inventory events.

Characters are the hub's `game_characters` (games DB):

- `stats`: HP, MP, level, XP, skill points, coins;
- `settings`: model, zone, position, `appearance`.

**Client** (`plugins/bacon_world/assets/js`, a LiveView hook `WorldCharacterUIScene`):

- `front-ui.ts` and `character-stage.ts`: character select and the creator, in HTML over a lit
  3D stage.
- `appearance.ts`: the look model and morph weights.
- `human-factory.ts`: builds a human from a look (below).
- `character-controller.ts`, `controls-math.ts` and `mouse-filter.ts`: controls.
- `anim-driver.ts`: four body channels, strafes, stances, swings with either hand (mirrored).
- `game-world.ts` and `game-ui.ts`: fights, loot, inventory, the EverQuest-style windows.
- `mobs-view.ts`, `npcs-view.ts` (merchants), `nameplates.ts`, `items.ts`, `world-dressing.ts`
  (the village and its colliders).
- `wardrobe.ts`: gear slots, what each worn item puts on the body, and the bone corrections.
- `lobby-audio.ts`: sound (buses, placed voices, loops, moods, the UI); `audio-mix.ts`: its
  testable logic. New sounds go in `priv/static/audio/world/` and a `GROUPS`/`POOLS` entry.

**Humans on the client** (`human-factory.ts`):

- Bodies, packs and hair GLBs load once. Instances share geometry and own their materials.
- **Tints.** A material named by role (`Skin`, `Iris`, `Brows`, `<Garment>_Main`, `_Trim`,
  `Shoes_*_Upper`, `_Sole`, and hair) takes the look's colour. A grey texture comes with a glTF
  extras **`tint_gain`**, and colour × gain gives the chosen colour on average:
  - skin and clothes: 1.25;
  - hair: 2.0.
- **Hiding.** Each vertex carries a `_region`. `Female.json`/`Male.json` `hides` maps a garment
  to the regions it removes. Hiding applies to the body (skin under clothes) and, since
  2026-10-22, to garments: trousers under a shirt's hem, boots under trousers. The filtered
  index buffers are cached per template and per hidden set (`filteredGeometry`).
- **Hair.** `Hair/hair_manifest.json` lists the styles per body. Its `aliases` (old id → new id)
  keep looks saved with retired styles working. A style's scalp decal (`decal` extras) gets a
  polygon offset, and alpha-tested cards get alpha-to-coverage.
- **Morphs.** Every mesh with morph targets (body, garments, hair, lashes, brows) takes the
  same weights from the look's sliders (22 on the male since 2026-10-24; 28 on the female since stage G). A morph that moves joints (`Shoulders_Broad`)
  moves the bones too (`joint_offsets` in the manifest).
- **Wardrobe** (both bodies). Worn items come from the gear (`under_top`, `under_bottom`,
  `chest`, `legs`, `feet`; and `head`, the Robin Hood hat, drawn in code by `crafted.ts`), not the look. Each is a garment mesh plus a design: a packed
  texture (shade, trim, accent, cut-out) tinted with the item's three colours (his designs in
  `Wardrobe/Male`).
- **After the animation** (`postAnimate`): the posture correction and relaxed fingers on
  empty hands. Each bone starts from what the animation left (a bone no clip keyed this frame
  still holds last frame's output, which once compounded 7 degrees a frame until she stood on
  her head). Clips load through `fixForearmTwist` (see §7).

## 5. The humans and other art

**Built by** `library/pipeline/scripts` (Blender's Python module, headless). Its
README has every script, source and run order.

- **Male** (2026-10-24), the same pipeline with `B8_BODY=Male`: `mhf_core.py` (look `m2`,
  1.78 m; Toigo's light male skin, its legs' colour calmed; `eyebrow008`; Mindfront lashes 01;
  the chest keys are his pectorals), `mhm_build.py` (his wardrobe shells and MakeHuman
  garments: the crude male tee, fisherman sweater, cloth shoes, ankle boots), `mhf_morphs.py`
  (waist, limbs and glute lift; not the chest shaping), `mhf_anims.py` (his packs),
  `mhf_syshair.py` (18 styles) and his six facial hair styles (grown by `build_hair.py` on the old
  male and refit to the new head by `mhm_facial.py`, retired with the old rigs on 2026-10-24; the
  GLBs stay). The skeleton creatures are rigged on his armature (2026-10-24, third delivery).
- **Female** (2026-10-22), built by `mhf_core.py`, `mhf_finish.py`, `mhf_anims.py` and
  `mhf_syshair.py`:
  - body: MakeHuman's `hm08` CC0 body and targets, look `v2`;
  - skin: a neutral grey texture with makeup;
  - procedural eyes;
  - lashes: Mindfront strand-mesh lashes;
  - brows: MakeHuman's `eyebrow001` card;
  - rig: the B8 skeleton, with MakeHuman's game-engine weights;
  - 13 morphs, plus 15 from stage G (chest, waist, limbs, glute lift).
- **Female v3** (2026-10-23, `mhf_v3.py`, the Pipeline README's stage F): the fixes above,
  and the **wardrobe**. Underwear (two top shapes and one bottom) and the new tank, shorts and
  trousers are shells made from her own body, with one shape key per morph. Designs are
  packed textures: six tops, six bottoms, plus the cloth pieces.
- **Female clothes as items** (cloth armour): the tunic (crude T-shirt), blue-dyed tunic,
  tank, wool sweater (fisherman sweater), trousers, shorts, cloth shoes and tall leather
  boots (thigh-high). The tee, sweater, flats and boots are the MakeHuman CC0 garments;
  boots go under trousers, trousers under shirts.
- **Underwear sets**: linen (cream, the starter), athletic, rose lace, coral, polka dot and
  emerald.
- **Female hair**: 31 styles from MakeHuman's system assets and the community Hair 01 pack,
  all CC0. Each has a soft scalp decal so the hairline isn't a hard edge, and the morphs.
- **Credits**: `priv/static/models/Humans/CREDITS.md` (models volume) and the site's
  `/pages/credits`.

- **The dragon** (2026-10-24, `build_dragon.py` + `dragon_shape.py` + `dragon_skin.py`; section 2 has
  the method): one model for Baconator and the mounts, its own 46-joint rig and 13 clips, baked
  4K skin, 2K wing leather, emissive slit eyes. Headless: `python tmp\b8work\jobs\dragon_go.py`
  (`fast` for a coarse look), then `meshopt_d.cmd` and `jobs/stage_dragon.sh`. Loot icons:
  `build_dragon_icons.py` (`dicons.cmd`).

**The shared library** (2026-10-23, `C:\Bacon8\library`, gitignored, see its README):
- `textures/`: 120 CC0 PBR texture sets at 2K (ambientCG and Poly Haven): fabrics, leathers,
  woods, bricks, roof tiles, slate, thatch, rock, ground, grass, paving, cobbles, metal,
  plaster and more, each with `meta.json`; `textures/LICENSES.md` lists them. Credit both
  sites when used. The game's runtime sets are packed from here by the pipeline step in
  `tmp/b8work/tex/pack.py` (to move into the pipeline; see section 7).
- `substance/`: 17 Substance materials whose licence is known (Allegorithmic, Adobe, TextureCan).
  The other 247 had no recorded source and were deleted on the owner's instruction, with 5
  restricted military camo patterns and 4 duplicates. `library/substance/LICENSES.md` is the licence table;
  `library/pipeline/scripts/b8_substance.py` bakes `verified/` to WebP texture sets
  (base colour, normal, ORM) with `meta.json` for the credits. None is in the game yet.

**Sources** (none in git): the MPFB2 repository, the Ubuntu `makehuman-data` 1.1.1 package
(system assets), MakeHuman's community asset packs, Quaternius UAL1+2, and Blender Studio's
human base meshes.

**Checking how it looks.** The cloud sessions use a headless harness, not in the repo (on
the development PC it sits in `C:\Bacon8\tmp\b8work\harness`):

- `harness.ts` builds a human with the real client code (`HumanFactory`, the animator, the
  wardrobe), poses it and renders one frame, driven by URL parameters (`gear`, `main`,
  `off`, `clip`, `t`, `view`, `yaw`, `shape`). esbuild bundles it in a throwaway node
  container; a `python:3.12-slim` container serves it beside the models.
- Playwright (the Docker MCP browser, at `host.docker.internal`) loads it. Copy the canvas
  into an `<img>` with `toDataURL` before screenshotting.
- `village.ts`/`village.html` render the village (`mode=village`, `cam=` and `at=` in
  metres), the weapons (`mode=weapons&list=`) or the skeleton, with `surf=off` for the old
  look. Software WebGL is slow: it renders once, waits (`wait=`, ms) for the textures, and
  renders again.

## 6. Working rules (from the owner)

- **Claude (cloud) builds and delivers. Claude Code verifies, tests and commits.**
  - Deliveries land uncommitted in `C:\Bacon8`, with a prompt in `C:\Bacon8\handoff\`
    (`CLAUDE_CODE_PROMPT_<date>.md`).
  - Don't run two Claude Code sessions on `plugins/bacon_world` at once.
- **Nothing is built on the development PC.** Compile and test only in throwaway Docker
  containers (BACON8.md §14). Models, audio and asset scripts run in the cloud session.
- **Secrets.** Never paste or print a secret: Stripe keys live only in gitignored
  `secrets.yaml` / `.env.stripe`, and Claude Code must not open `.env.stripe`. The plugin's
  `k3s/*secrets.yaml` is never committed.
- **Production** reads and irreversible deletions need the owner's OK. **Deploy only when the
  owner says. Don't run `sync-models-to-k8s.sh` until told.**
- **Line endings.** The `C:\Bacon8` working tree is CRLF (autocrlf). The `RaysSpaceSim`
  repository stores and checks out LF.
- **Handoff and hub files go in `C:\Bacon8`**, never `C:\PhxLive` (the old name).

## 7. Known issues and next steps

Only what is still open. What was finished is in §2 and git. Items marked "(real game)" have only been checked in
the harness and in tests, not by a person playing.

**To check in a real game**

- Everything new since 2026-10-26: walking Crater Lake (the map's orientation: the RAW's first row is taken as
  north, -z), swimming and diving, fishing in the sea, the lake and the Millpond, the Kraken fight, build mode as a
  member, a GM and an admin (two players building at once), groups, bows, the fork, the hat on tall and long
  hairstyles, the fork in dagger swings, and the arrow in flight and stuck in the ground.
- The first start of each zone seeds its placements (a log line `bacon_world:building seeded`). Watch the zone's
  start time and `fetch_mobs`: about 550-1,000 rows per zone. A zone seeded once never re-reads the seed files, so
  later edits to `world-dressing.ts`' layout don't reach it (by design).
- Production needs `World/Terrain/` synced (`sync-models-to-k8s.sh`; the owner's OK) or it stays on the flat island.
- Mount store products: `BaconWorld.Mounts.ensure_store_products/0` creates them off; publish them in the store.

**World and building**

- Placed things block walking on the client only (like the village); the server checks speed, not walls. Stacking is
  by PgUp/PgDn: nothing snaps one piece onto another and nobody can walk up stairs or onto floors.
- Still from code, not placements: the fixed merchants (`Merchants`: Tilda, Old Bram, the stablemaster...), the
  village's ground (the plaza and paths are painted) and a camp's ground patch.
- Terrain painting is by rule (slope, height); World Creator's splat and scatter maps would do it properly. No
  normal maps on the ground yet; distant chunks are plain. Zone lines (a ferry from the bay, a pass in the ridges)
  are for when there is a second zone. Crater Lake could have its own fish.
- Creatures follow the ground's height but ignore slopes, and stop dead at deep water. Creatures don't collide with
  anything.
- Swimming: no breath and no boats; weapons stay in hand. The lake's edge is a client-side collider.

**Combat and creatures**

- Kraken: its numbers (HP, damage, special cadence, the maelstrom's pull) are first guesses; tune after a fight.
  It is ~98k triangles: fine for one boss, but with many riders on Kraken mounts a lighter mount level of detail
  is worth building. Being held and dragged are applied by the victim's client (as creature damage is), not
  enforced by the server's move checks.
- Baconator and the drakes: tune the sculpt in `dragon_shape.py` (muscle blobs, `SKULL`, `JAW`) and the skin in
  `dragon_skin.py` from what the owner says. No aerial combat; Baconator ignores fliers over 6 m. The rider's seat
  (`SEAT_DROP_M`) on very tall or short bodies, and a saddle prop, are open.
- Goblins and orcs keep the male's posture-less clips (no hunch); a goblin shaman or orc caster needs spells for
  creatures (none exist). The plague rat is the rat tinted; its own model would be better.
- Bows: the limbs don't flex as the string is drawn; no aiming up or down (arrows fly level, to the target's height
  when there is one); PvP arrows land like swings (decided at once).
- Groups are in memory: a server restart ends them. Invites by name reach anyone in the world, but experience and
  coin splits only count members in the killer's zone. Nameplates don't yet colour groupmates.
- PvP reach is checked against Presence positions (up to 100 ms old) with 0.8 m slack. Creature and PvP hits write
  the player's HP to the games DB on every hit; batch them if fights get big.
- Spell targeting of other players for harm (a PvP fireball) isn't wired; heal works on players.
- **Spell lights are pooled (three).** A fourth effect at once goes without a light. New effects must use
  `takeLight`/`giveLight` and shared materials; never add or remove lights or dispose shared materials (either
  recompiles every lit material and freezes the game for seconds).

**Sound.** Real CC0 recordings are wanted for: surf, a cast, a splash, a reel, the Kraken's water (a big splash,
a whirlpool, a wet slap, ink), a bow's twang, an arrow's thud, rat squeaks, goblin chatter and orc grunts. The
placeholders reuse existing recordings (`sw_drip`, `loot`, the dragon's roars pitched down).

**Skills and fishing.** New *kinds* of ability need code (an entry in `abilities.ex`, its effect in `skill_events.ex`
and `spell-fx.ts`); placing existing ones on the tree is done in `/admin/bacon_world/skills`. A new spell school
needs a `cast_loop_<school>.mp3` and a `CAST_SCHOOL` entry. Ability icons are emoji. Catching is flat (80% on a
timely reel): no fishing skill, bait or rod tiers, and fish can't be cooked yet.

**Items and economy.** Armour beyond cloth; more merchants. Existing characters lose their old creator outfit and
get the linen set and 1 gold at their next login. Throw Stone's spell rows stay in the games DB (retired in code);
deleting them needs the owner's OK.

**Characters (art)**

- Tuning the male's posture: all of it is in `mhm_build.py`'s `POSTURE`; the harness's `?tilt=`, `?spine=a,b,c`,
  `?clav=fwd,down`, `?arm=free:u,l;torch:u,l`, `?fh=x,y,z` and `?relax=index:a,b,c,s;...` override the manifest on
  either body. Render side views (`view=side&yaw=18`, `focus=spine_02&dist=2.9&az=250&el=0`).
- The female (the owner wants her stunning): some hairstyles (ponytail, long) still read as painted at the temple;
  some hair shells are low-poly (long01) and LongWavy is 15.5k vertices (an LOD); the Mindfront lashes cost about
  19.8k vertices per character (swap for cards at a distance); face polish (slightly larger eyes, eye-scale ~0.12 in
  `LOOKS["v2"]`, skin sheen or subsurface, catchlights); more outfits (skirts and dresses are CC0 and fit her; a
  dress needs a slot rule in `appearance.ts`/`.ex` and `human-factory.ts`).
- The male's six facial hair styles are refits of the old procedural cards (MakeHuman has no CC0 beard set yet).
  No A-pose fanned fingers: every clip must key the fingers. The skeleton creatures share the male's packs but not
  his posture correction (it lives in `HumanInstance`). Old `Mobs/Anims/` awaits the owner's OK to delete.
- Sources (CC0) are in `C:\Bacon8\library\makehuman` (gitignored): MPFB2's data, MakeHuman's system assets and the
  community packs (hair01, shirts01, pants01, shoes01, underwear01, suits01, eyebrows01, eyelashes01, skins01-03).
  The light Toigo skins are what's used.

**Surface textures.** The cloth armour and underwear have design textures; the leather and plate armour still to
come should use the library's leathers and metals the same way. Move `pack.py` (library set to runtime WebP) into
`library/pipeline/scripts/` and generate `SETS` from it. Triplanar costs about ten texture reads per pixel on
textured surfaces; the Esc menu's Textures switch turns it off for low-end machines, and baking UVs and textures into
the GLBs in Blender is the cheaper path. Trees' leaves, food, paint and gems are untextured on purpose.

**Housekeeping**

- The village's colliders and the lake's edge are client-side only.
- `/models` serves `.glb.gz` only when present and newer than the `.glb`: make them whenever models change
  (`gzip -k -9`).
- The client has a few pre-existing TypeScript errors under `npm run type-check` (implicit `any`s); it bundles fine.
- Ctrl+W still closes the tab: browsers don't let pages intercept it.

**Assets still wanted:** weapon animations per weapon type, finished and polished (see
`library/pipeline/Characters/ANIMATION_ROADMAP.md`).

## 8. Picking up the torch

1. Read this file, then `plugins/bacon_world/README.md`, then BACON8.md §6 and §9.
2. `git status` in `C:\Bacon8`. Anything uncommitted belongs to the newest prompt in
   `handoff/`. Has Claude Code run it? Its commit message says so.
3. For art work, start from `library/pipeline/scripts/README.md`. Fetch the sources
   it lists, then rebuild in the cloud session and deliver with a new handoff prompt.
4. Record new owner decisions in §3 and update §2 and §7 before you stop.

**Working from a cloud session** (how the 2026-10-2x sessions ran; the tools are those of a
Claude session linked to the development PC through the desktop app):

- **Files**: the linked computer's shell (`device_bash`, a Linux VM) sees `C:\Bacon8` as
  `$HOME/mnt/Bacon8` (read, write, Python with Pillow). Hub files are CRLF: edit them with a
  short Python read-modify-write that keeps `\r\n`. Deleting needs the owner's permission
  prompt (`device_request_delete_permission`).
- **MCP servers on the development PC** (BACON8.md §14 has the full list): `unreal`
  (`run_python` in the editor), `Blender` (the interactive Blender 5.1: `execute_blender_code`,
  screenshots, renders; its glTF importer can't read meshopt files, so import the pipeline's
  pre-meshopt GLBs or append from the `.blend`s) and `MCP_DOCKER` (the Playwright browser for
  the harness). Blender's window screenshot comes back black when it is minimised: render to
  a file (Workbench, a camera) and stage it instead.
- **Windows commands** (Blender 5.1, Docker): the VM can't run them. The Unreal editor's MCP
  (`run_python`) runs Python on Windows, so `subprocess.run(["cmd", "/c", r"C:\...\x.cmd"])`
  runs a `.cmd`; long jobs go in a `threading.Thread` and are polled from the VM by a log or a
  `.done` file. Blender always runs `-b --factory-startup` (an installed Substance add-on
  errors otherwise) through `tmp/b8work/jobs/run_pipe.py`, which puts SciPy and Pillow
  (`B8_PYLIB`) on the path. `tmp/b8work/mhenv.cmd` sets the MakeHuman paths.
- **Ready-made jobs** in `tmp/b8work/`: `mcore.cmd`, `mbuild.cmd`, `mmorph.cmd` (the male's
  stages A, C+F, G; `mfull.cmd` runs all three then meshopt), `meshopt_m.cmd`,
  `anims_chain_m.cmd` (his packs), `mhair_chain.cmd` / `mfac.cmd` (hair, facial hair),
  `hbuild.cmd` / `vbuild.cmd` (harness bundles), `skel.cmd` + `meshopt_s.cmd` (the skeleton
  creature), `jobs/dragon_go.py` + `meshopt_d.cmd` + `jobs/stage_dragon.sh` (the dragon; run
  the `.py` jobs with `python` from `run_python`, polled by `dragon.done`), `jobs/render_go.py`
  (Cycles renders of a GLB), `jobs/blender_go.py <script>` (any headless Blender script),
  `sbuild.cmd` (the skills harness: `skills.html?points=&learned=n0,n2`, `?mode=editor`),
  `jstest.cmd` (JS tests, bundle, type-check)
  and `mixtest.cmd` (Elixir compile and tests, with a throwaway Postgres).
- **Seeing it**: the Docker MCP browser opens the harness at
  `http://host.docker.internal:8765/harness/grid.html?u=<params>&l=<label>&u=...` (several
  views side by side; navigation times out at once, then wait about a minute and
  screenshot). Parameters: `body`, `clip`, `t`, `view` (full, upper, side, hand), `yaw`,
  `focus=<bone>&dist=&az=`, `hair`, `facial`, `shape=key:v,...`, `gear=slot:item,...` (slots
  `under_top`, `under_bottom`, `chest`, `legs`, `feet`), `main`, `off`, `hat=1` (the Robin Hood hat; `hatfit=up,fwd,tilt,scale`
  tries a fit), `w=`/`h=` (each view's size), `tilt`, `spine`, `clav`,
  `rest=1` (the bind pose), `mob=1` (the skeleton creature on the male's packs). `village.html?mode=dragon`
  (`scale`, `clip`, `t`, `tint=scales,membrane,eye`, `fly=1`, `yaw`) and `mode=lair` show the dragon
  and the lair. Each frame
  leaves `window.POS` (key bone positions, metres) for measuring. The harness's
  `catalog.json` is a copy of the items: add an item there before trying it.
- **Staging models**: copy into `priv/static/models/...`, make the `.glb.gz` (`gzip -9 -k -f`),
  back up what's replaced under `tmp/b8work/backup_models/`.
- **Deliver**: a `handoff/CLAUDE_CODE_PROMPT_<date><letter>.md` for Claude Code, and update
  §2/§7 here and the project's copies of this file and BACON8.md.

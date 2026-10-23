# BACON_WORLD.md: Bacon World, where it stands and where it's going

**What this file is.** This is the working notebook for **Bacon World**, the 3D multiplayer game
that runs in the browser. It is Bacon8's reference game plugin (`plugins/bacon_world`, at
`/games/bacon_world`).

**Read it first** when you pick the game up in a new session.

Related documents:

- `BACON8.md` covers the hub (plugin contract §9, invariants §6, workflow §14).
- `plugins/bacon_world/README.md` is the module-by-module reference.
- The game repository (`RaysSpaceSim/`, its own git) builds the art. See `SourceAssets/Pipeline/README.md`.

**Rules for editing this file.** They are the same as BACON8.md's:

- Public-safe. No hostnames, IPs, credentials, cluster names or anything specific to one
  deployment.
- Facts dated. The owner's decisions are recorded, not re-argued.

Last update: **2026-10-23**.

---

## 1. What Bacon World is

A small online RPG in the browser, written with three.js and Phoenix LiveView:

- Make a character in a creator: body type, sliders, skin, eyes and hair. Everyone starts in
  plain cream underwear; clothes are cloth armour you buy, find and wear.
- Walk a village with other players and chat with people nearby.
- Fight skeletons outside town with either hand, loot their corpses EverQuest-style and level up.

It is also the template other Bacon8 games copy.

**Direction.** It should feel like a classic MMO, with:

- EverQuest's windows, looting and con colours;
- RaysSpaceSim's on-foot controls (minus flight);
- Black Desert's mouse-button attacks;
- Path of Exile's single shared skill tree.

All of it uses our own or CC0 art. Every 3D asset is built by scripts in the game repository,
so it can be rebuilt and changed.

## 2. State on 2026-10-23

**Deployed (through `1eb78e8`, 2026-10-21):**

- fighting, skeleton creatures, EverQuest looting, inventory, levels;
- real recorded sounds;
- character select and the creator with looks;
- the lobby village;
- RaysSpaceSim-style controls and EverQuest-style mouse handling.

**Committed 2026-10-22, not yet deployed (models not yet synced):**

| Handoff prompt (`handoff/`) | What it brought |
|---|---|
| `CLAUDE_CODE_PROMPT_2026-10-22b.md` | Skeletons now attack and can be hit (the BEAM's monotonic clock is usually negative; timers started at 0). A remote-desktop mouse filter (`mouse-filter.ts`) replaces the camera-smoothing option, which is gone. Effects, nature and music volume sliders. New grass footsteps. |
| `CLAUDE_CODE_PROMPT_2026-10-22c.md` | The female rebuilt on MakeHuman (CC0), with 31 MakeHuman hair styles, MakeHuman clothes fitted to her, strand lashes and a brow card. Hair-style aliases (client and server). Garments hide the parts of garments under them. And these docs. |

**Committed, deployed and synced 2026-10-23:** `handoff/CLAUDE_CODE_PROMPT_2026-10-23.md` (below).
The owner's testing of it led to the next delivery.

**Delivered 2026-10-23 (second), uncommitted** (`handoff/CLAUDE_CODE_PROMPT_2026-10-23b.md`):

- **The female's body sliders, Black Desert style**: the chest gets size, height, spacing and
  shape (round to perky); the glutes size and lift; new waist, arms, thighs and calves
  (pipeline stage G, `mhf_morphs.py`; 15 new shape keys, every garment follows). "Bust" is
  now "Chest" and "Seat" "Glutes". The creator's body tab is in sections: Body, Chest,
  Glutes, Arms and legs.
- **Posture**: she stands straight (pelvis tucked 20 degrees, the lumbar following, the
  chest brought upright higher up), instead of the arched lower back and forward belly.
- **Relaxed hands**: fingers drawn together and curled at the knuckles, thumb alongside.
- **Daggers**: both hands up at elbow height, blades forward and up, wrists straight (the
  right hand was at the thigh with the wrist bent 88 degrees). Her animation packs were
  rebuilt, which also ships the forearm-twist fix in the data.
- **PvP "instant heal"**: target bars read full again on every presence sync (health wasn't
  in the presence); now it is, and regeneration runs on one timer per LiveView.
- **R interacts** (the targeted or nearest person in reach: a merchant opens her wares).
- **New characters wear their underwear** in the creator and on the select screen (the item
  catalogue now loads before any character is dressed).
- The blends open in the rest pose (every clip was an unmuted NLA track playing at once).

The first 2026-10-23 delivery:


- **The female, v3** (pipeline stage F, `mhf_v3.py`): relaxed fingers on empty hands; the
  shoulder slider no longer changes the hands' size (joint offsets); a rounder bust; skin
  seam streaks gone; she stands straighter (pelvis tilted back 7 degrees after the animation);
  new tank, shorts and trousers made from her own body so they don't clip; the forearm
  "wringing" with daggers fixed (a pipeline bug in every authored weapon clip, repaired on
  load).
- **Underwear and clothes as items.** No clothes in the creator. Underwear tops and bottoms
  are separate, removable items in their own slots (`under_top`, `under_bottom`) under
  `chest`, `legs` and `feet`; everyone starts in the cream linen set and with 1 gold. Six
  underwear sets and eight pieces of cloth armour (the old clothes meshes).
- **The first merchant**: Tilda Threadwell, Clothier, in the village. She sells all 20
  wearables and buys anything for a quarter of its value. **Coins are EverQuest's**:
  platinum, gold, silver, copper (10 to the next).
- **Multiplayer fixes** from the owner's testing: others now see you swing, crouch and jump;
  PvP melee works (both flagged) and is applied by the target's own LiveView; picking a
  player no longer raycasts their skinned meshes (that froze the game on every swing at a
  player); Ctrl toggles mouse-look both ways; Ctrl+A no longer selects the whole page; and
  **Throw Stone is gone** (it was the old web-lobby test).

**On the models volume (gitignored; synced only when the owner says):**

- `Humans/` holds:
  - `Male.glb` (v2), and `Female.glb` (MakeHuman v3, 2026-10-23), each with its `.json`;
  - `Wardrobe/`: the female's 36 packed design textures (`.webp`) and `icons/` for the 20
    wearable items;
  - `Anims/`: the four animation packs (core and combat for each body, 143 clips a body);
  - `Hair/`: 23 male hair and 6 facial hair styles, 31 female hair styles, icons, `hair_manifest.json`;
  - `README.txt` and `CREDITS.md`.
- `Weapons/B8_Weapons.glb` (43 weapons, shields and tools).
- `Mobs/B8_Skeleton.glb`.
- `World/B8_Props.glb` (90 props) and `B8_BuildKit.glb` (36 building pieces).
- Every `.glb` has a `.glb.gz`. The local copies in `C:\Bacon8\priv\static\models` are current.
  Production gets them only with `sync-models-to-k8s.sh`, run by the owner.

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
| 2026-10-22 | **No camera-smoothing option.** Remote-desktop jumps are repaired by `mouse-filter.ts`; a local mouse is untouched. |
| 2026-10-21 | **Assets are ours or CC0.** Epic's content stays Unreal-only, and no paid UAL Pro/Source files from mirrors. **No DAZ-derived meshes**: the owner's two DAZ-based female files must not be used, so the female is built on MakeHuman (owner's choice, 2026-10-21). |
| 2026-10-23 | **Asset rule widened on purpose: ours, CC0, or licensed for commercial use, credited, with the source files never redistributed.** Licensed sources (Substance .sbsar and the like) live in the gitignored shared library `C:\Bacon8\library\` with a licence table; only what we bake from them ships, and it goes on the credits page. The DAZ and Epic exclusions above still stand. |
| 2026-10-23 | **Substance materials are baked in Blender** with Adobe's Substance 3D add-on (`b8_substance.py`). The library's unverified files aren't used until their source is recorded; files that can't be used legally are deleted. |
| 2026-10-21 | The female should be **stunning**. She is editable in Blender (`RaysSpaceSim/SourceAssets/Characters/B8Human/B8_Female_MPFB.blend`) so the owner can sculpt her later. |
| 2026-10-23 | **No clothes in character creation.** New characters start in **cream bikini underwear**. |
| 2026-10-23 | **Underwear is equipment**: a top and a bottom, separate items, layered under clothes and armour, and removable. They are ordinary 3D gear: no content warnings around them. |
| 2026-10-23 | **At least five underwear sets for sale from an NPC merchant.** The old clothes meshes become **cloth armour**. |
| 2026-10-23 | **EverQuest currency**: platinum, gold, silver and copper. |
| 2026-10-23 | **Throw Stone is removed**: it was only a test from the old web-lobby game. |
| 2026-10-23 | **R is reserved for interactions** (NPCs now; doors and the like later). Right-clicking a merchant with the cursor free still works too. |
| 2026-10-23 | **Body sliders take their cues from Black Desert Online**: more control over the chest (call it "chest", not "bust"), glutes ("glutes", not "seat"), waist and limbs. |
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
- `Combat`: HP/MP, PvP flags, respawning (spells come later; Throw Stone is retired).
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
- `lobby-audio.ts`: sound.

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
  same weights from the look's sliders (13 on the male; 28 on the female since stage G). A morph that moves joints (`Shoulders_Broad`)
  moves the bones too (`joint_offsets` in the manifest).
- **Wardrobe** (female v3). Worn items come from the gear (`under_top`, `under_bottom`,
  `chest`, `legs`, `feet`), not the look. Each is a garment mesh plus a design: a packed
  texture (shade, trim, accent, cut-out) tinted with the item's three colours. The male shows
  his built-in shorts for underwear until he gets the same treatment.
- **After the animation** (`postAnimate`): the posture correction and relaxed fingers on
  empty hands. Each bone starts from what the animation left (a bone no clip keyed this frame
  still holds last frame's output, which once compounded 7 degrees a frame until she stood on
  her head). Clips load through `fixForearmTwist` (see §7).

## 5. The humans and other art

**Built by** `RaysSpaceSim/SourceAssets/Pipeline` (Blender's Python module, headless). Its
README has every script, source and run order.

- **Male**: v2 (`build_humans2.py`) on Blender Studio's CC0 base mesh, with procedural hair
  (`build_hair.py`). *He is next for the MakeHuman treatment.*
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

**The shared library** (2026-10-23, `C:\Bacon8\library`, gitignored, see its README):
- `textures/`: 85 CC0 PBR texture sets at 2K (62 from ambientCG, 23 from Poly Haven): fabrics,
  leathers, woods, bricks, roof tiles, rock, ground, grass, metal, plaster, paving and more,
  each with `meta.json`; `textures/LICENSES.md` lists them. Credit both sites when used.
- `substance/`: 17 Substance materials whose licence is known (Allegorithmic, Adobe, TextureCan).
  The other 247 had no recorded source and were deleted on the owner's instruction, with 5
  restricted military camo patterns and 4 duplicates. `library/substance/LICENSES.md` is the licence table;
  `RaysSpaceSim/SourceAssets/Pipeline/b8_substance.py` bakes `verified/` to WebP texture sets
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

In rough priority order.

**The female (keep polishing; the owner wants her stunning):**

- Hairlines are better with the scalp decals, but some styles (ponytail, long) still read as
  painted at the temple.
- Some hair shells are low-poly (long01). LongWavy is 15.5k vertices; consider an LOD.
- The Mindfront lashes are about 19.8k vertices per character: hide or swap them for cards
  beyond a few metres.
- Face polish candidates:
  - slightly larger eyes, eye-scale ~0.12 in `LOOKS["v2"]`;
  - brow options (Mindfront brows look best but are ~10-20k vertices);
  - skin sheen or subsurface in three.js;
  - eye catchlights.
- The tee's trim band is tiny (a low-poly garment). The camisole's trim is large (lace edges).
- More outfits: skirts (Skirts 01) and dresses (Dress 01) are CC0 and fit her. Adding a dress
  needs a slot rule (a dress replaces top and bottom) in `appearance.ts`/`.ex` and
  `human-factory.ts`.

**The male:** rebuild on MakeHuman the same way: body, MakeHuman male hair (short01-04,
afro01, culturalibre_hair_02/05), and male clothes from the same packs. Then both bodies share
one pipeline.

**Game (from BACON8.md's debt list, moved here):**

- The skill tree itself (Q E F Z X), armour beyond cloth, more merchants, and groups with
  shared loot.
- **The male's animation packs** still carry the bad forearm-twist tracks (the client repairs
  them on load) and the old dagger guard: his source blend (`b8_humans2.blend`) isn't on the
  development PC. Rebuild them with the male's MakeHuman rebuild.
- **The male has none of the new body sliders** (female-only in `appearance.ts` and
  `Appearance`); he gets them with the same treatment.
- The female's **hair** GLBs weren't re-fitted for the joint offsets (only `Shoulders_Broad`
  moves joints, so hair is unaffected for now).
- **The male**: underwear on him is interim (his built-in shorts, tinted; nothing for the
  top). He needs the v3 wardrobe after the MakeHuman rebuild.
- Existing characters lose their old creator outfit and get the linen set and 1 gold at their
  next login.
- Throw Stone's spell rows stay in the games DB (retired in code). A migration to delete them
  needs the owner's OK.
- PvP reach is checked against Presence positions (up to 100 ms old), with 0.8 m slack.
- Ctrl+W still closes the tab: browsers don't let pages intercept it.
- The village's colliders are client-side only (the server checks speed, not walls).
  Creatures don't collide with anything.
- Creature and PvP hits write the player's HP to the games DB on every hit; batch them if
  fights get big.
- `/models` serves `.glb.gz` only when present and newer than the `.glb`: make them whenever
  models change (`gzip -k -9`).
- The client has a few pre-existing TypeScript errors under `npm run type-check` (implicit
  `any`s); it bundles fine.

**Assets still wanted:** weapon animations per weapon type, finished and polished (see
`RaysSpaceSim/SourceAssets/Characters/ANIMATION_ROADMAP.md`), and a building system for the 36
kit pieces.

## 8. Picking up the torch

1. Read this file, then `plugins/bacon_world/README.md`, then BACON8.md §6 and §9.
2. `git status` in `C:\Bacon8`. Anything uncommitted belongs to the newest prompt in
   `handoff/`. Has Claude Code run it? Its commit message says so.
3. For art work, start from `RaysSpaceSim/SourceAssets/Pipeline/README.md`. Fetch the sources
   it lists, then rebuild in the cloud session and deliver with a new handoff prompt.
4. Record new owner decisions in §3 and update §2 and §7 before you stop.

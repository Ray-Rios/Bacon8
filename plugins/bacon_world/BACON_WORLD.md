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

Last update: **2026-10-27**.

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

## 2. State on 2026-10-27

> **Hub note from Claude Code, 2026-10-25.** Everything listed below up to and including the
> 24f delivery (skill tree, stable, game cards, the Gem) is **committed and deployed**, and
> so is the hub half of the 25a sound delivery (`575aac6`). Wording below that says "not yet
> deployed" for older items is stale. The player's personal glass colour now reaches this
> game's windows through `--bwg-*` CSS variables (set by `assets/js/glass_theme.ts` and the
> root layout; unset on the default theme, so the game keeps its own look). The Frosted and
> preset colours on /profile work again (a custom tint used to override them).

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

**Delivered 2026-10-27 (b), uncommitted** (`handoff/CLAUDE_CODE_PROMPT_2026-10-27b.md`): **from the owner's first ride on
the Kraken: diving, a roaming boss, and two-handed weapons started over.**

- **Two-handed weapons, from scratch** (`two-hand.ts`, `human-factory.ts` `twoHandDrive`). The owner: the male's
  two-handed positions were "messed up beyond all repair", his arms twisting and contorting in the swings. The
  library's two-handed clips no longer move the arms at all. Each two-hander's guard and swings are poses of the
  *weapon* (where the grip is, which way the haft and the edge point, how far the torso turns and leans), eased
  between; every frame both hands are put on it: the main hand at the grip, the off hand up the haft (`HOLD.off`),
  each hand turned by the weapon's own frame (so a wrist can't wring through 180 degrees), each arm by an IK that
  keeps the elbow a true hinge toward its pole, the forearm's and the upper arm's roll shared with their twist
  bones, the clavicle lifted when the hands go overhead. Swords, axes and mauls: a middle guard, a falling cut, a
  rising cut, an overhead; spears and halberds: two thrusts and a sweep; the quarterstaff: a jab and a swing. The
  legs keep their clips (standing still, the old swing's footwork). The fishing pole keeps its own guard. Both
  bodies; checked in the harness at rest, walking and through every swing.
- **Diving**: in deep water **C** swims down (to just over the bottom), **Space** swims up, and at the surface Space
  jumps out. Under the surface the world turns a murky blue-green and closes in. The server takes positions down
  to the bottom (`Terrain.bottom_units/3`).
- **Mounts swim**: any mount in deep water swims (the drakes no longer walk on it): a drake low in the water at
  half its pace, its back at the waterline; the Kraken at its 22 m/s; both dive with C and rise with Space.
- **The boss Kraken is half as big again** (2.1 times the model: the mantle stands ~23 m out of the water; reach
  16 m, specials' ranges 33-39 m, the maelstrom drags 9 m) and **roams the deep water on its own** (`roam`:
  anywhere deep within 300 m of its spawn, a new heading when the deep water ends; a chase ends back where it
  began).
- **The Kraken model**: whole fins (webbed between the rays, no holes or torn fringe), a higher saddle; the mount
  is a little bigger (0.4) with the rider up on its head, not in it. **The Tentacle Lash animates** (it had picked
  arms that didn't exist).
- Tests: 695 Elixir (1 new), 92 JS (4 new).

**Delivered 2026-10-27 (a), uncommitted** (`handoff/CLAUDE_CODE_PROMPT_2026-10-27a.md`): **the Kraken, a second
boss and a mount, and mounts that fight.** The owner's brief: a kraken in the middle of Crater Lake, "the stuff of
nightmares", highly detailed like Baconator, sold in the store as a mount that can't fly but swims very fast; and
every mount should attack (the dragons breathe fire and claw; the Kraken's moves were left to us). His reference
art only set the mood: the design is ours.

- **The model** (`library/pipeline/scripts/build_kraken.py`, `kraken_shape.py`, `kraken_skin.py`; built headless in
  Blender like the dragon): a towering, ragged mantle with a crest of spines, thorns, torn bony fins full of holes and
  old wounds (gashes, claw rakes, sucker-ring scars, barnacle crusts); a head with heavy lids over two great gold eyes
  with slit pupils (on their own bones: they follow their target) and clusters of small red eyes; a lamprey maw, three
  rings of hooked teeth round a black beak; eight webbed arms with two zigzag rows of suckers on stalks and hooks at
  their tips; two 17 m hunting tentacles ending in hooked, serrated clubs with a bone blade and a barb. Bioluminescent
  spots (lines down the arms and flanks, rings round the eyes, lures round the maw, glowing arm tips) are an emission
  map the client pulses. About 98k triangles (44k of body, the rest teeth, hooks, spines and fins), 4096/2048/512 maps
  (WebP in the GLB), 124 bones, no clips:
  `Mobs/B8_Kraken.glb` on the models volume.
- **It moves itself** (`kraken-view.ts`, `KrakenRig`, the same API as the dragon's rig): every arm writhes on its own
  phase; swimming gathers them into a spear and pulses the mantle; one-shots for lash, slam, grab, squeeze, ink,
  maelstrom, roar, hit and death (it sinks). Effects: an ink cloud and a whirlpool on the water.
- **The boss** (`BaconWorld.Mobs.Spawns` "kraken", level 16, 1.4 times the model's size, so the mantle stands ~15 m out
  of the water): it lives in the deep middle of the crater's lake (`kraken_deep`, Crater Lake only) and never leaves
  deep water (`aquatic`). Unlike every other creature it goes for swimmers (riders in the air are still out of reach).
  Its arms lash and slam (11 m); every 9-13 s a **special**, wound up so you can see it coming: **grab** (a tentacle
  seizes its target, holds you fast 3.5 s and squeezes each second), **ink** (a cone: your screen goes black for a few
  seconds) and **maelstrom** (everyone within 24 m is battered and dragged toward it; the long windup is the time to
  swim clear). Specials are a new, general mechanism (`specials` on a kind); the client applies their effects to
  whoever they hit (held, blinded, dragged). Loot: ink sacs, abyssal hooks, its beak (rare), and sometimes an Abyssal
  Harpoon, a Krakenfang Cutlass or a Barnacled Buckler.
- **Fighting while swimming is allowed now** (it was refused in (d)): the Kraken is out in the deep water.
- **The Abyssal Kraken mount** (`BaconWorld.Mounts` "abyssal_kraken", $25, scale 0.3): can't fly; 22 m/s in deep water
  (a quarter more sprinting), a slow 4 m/s heave on land. `ensure_store_products/0` creates its store product, off.
- **Mounts fight**: while riding, the attack buttons are the mount's moves (`"mount_attack"`, creatures only):
  drakes **Claw Swipe** (left) and **Fire Breath** (right: a 10 m cone, up to six creatures); the Kraken **Tentacle
  Lash** (left, a wide sweep) and **Maelstrom** (right: everything within 7.5 m is battered and held 3 s). Everyone
  sees the move.
- Sounds: the Kraken uses the dragon's recordings pitched down. Real CC0 water sounds (a big splash, a whirlpool, a
  wet slap, ink) are still wanted.
- Tests: 694 Elixir (9 new), 88 JS (3 new).

**Delivered 2026-10-26 (d), uncommitted** (`handoff/CLAUDE_CODE_PROMPT_2026-10-26d.md`): **swimming, camps
across Crater Lake, and dismounting on hills**, from the owner's first walk on the terrain.

- **Dismounting on a hill was refused** ("land first"): the server judged "in the air" by height above
  0, the old flat ground. It now measures from what's underneath (the terrain or the water's surface,
  `BaconWorld.Terrain.surface_units/3`), as the move checks and the creatures already did.
- **Swimming.** Water deeper than wading (1.2 m) is open: you float at the surface (the swim clips are
  authored with the body hanging from the waterline), slower (2.2 m/s, 3.4 sprinting), with no
  jumping, crouching, fighting or fishing, and splashes instead of footsteps. Everyone else sees the
  swim clips (motion flag 8). Only the map's margin stops you now (and the Millpond, a reedy pond).
  Creatures don't swim: they stop at the water's edge and leave swimmers alone.
- **Camps across the zone** (for the time being, until the owner places creatures in game): the three
  by the village, plus the North Graves, the Shore Ruins, the East Barrow, the Hollow Graves, the
  Plateau Ruins, the Crater Road Barrow, the High Ruins and the Western Barrow, harder the further out
  (140 m to 1.3 km), each on a flat, dry spot picked from the heightfield. **Baconator's lair** is on the
  high plateau north-east of the crater, about 2 km from town (nothing near the crater itself is flat
  enough for it). Without the terrain the old four camps stay.
- The owner saw creatures that hit him but were invisible, until a hard refresh: a tab running old
  scripts against the new server (the harness draws them correctly on the terrain). Production reloads
  such tabs itself (`Bacon8Web.StaticReload`).
- Tests: 685 Elixir (3 new), 85 JS (1 new).

**Delivered 2026-10-26 (c), committed** (`4089384`, `956fb33`; `handoff/CLAUDE_CODE_PROMPT_2026-10-26c.md`): **the starter zone
is a real landscape: Crater Lake.** The owner made it in World Creator (4096 m square, heights
-306 to +689 m, sea at 0, exported as a 16-bit RAW) and asked for it in game with the village on the
flat by the bay.

- **The pipeline**: `library/pipeline/scripts/terrain_build.py <raw> <out>` turns the RAW into the game's
  files (`World/Terrain/` on the models volume): heights on a 2 m grid for the server
  (`crater_lake_h.bin`), the same packed small for the browser (`crater_lake_hd.bin`, 2-D differences,
  3 MB gzipped, `.gz` beside it), and the water bodies on a 4 m grid (`crater_lake_w.bin`: the sea,
  Crater Lake, two ponds). It moves the map so **the town's centre is the game's origin and its ground
  is height 0** (the bay flat at map pixel 2456, 3824, 17 m above the sea), flattens the town's pad
  (flat to 70 m, blending back to the land by 150 m) and carves the Millpond's bowl. So the village, the
  camps, the merchants and the spawn keep their coordinates; only "how high is the ground" changed.
  The sea is at -17 m in game; the bay starts 287 m west of the square.
- **The server** (`BaconWorld.Terrain`) reads the heights and water grids (lazily, once, 7 ms) and
  answers height, water and walkable questions. `BaconWorld.Water` follows it: the sea, Crater Lake,
  the Upper Pond and the Little Pond are wherever the ground is below the sea's level (named in the
  combat log when you cast); the walkable world is the map minus a 40 m margin, no deeper than wading
  (1.2 m). Moves are checked against the ground under them (climbing is limited, falling never is, so a
  fall from the crater's rim isn't snapped back), and creatures judge "flying" by height above the
  ground. **Without the terrain files** (tests, an install that hasn't synced the models) everything
  falls back to the flat round island.
- **The browser** (`terrain.ts`, `terrain-world.ts`): the page carries the terrain's description
  (`data-terrain`), the hook loads the heights before building the village, and every piece of the
  village stands on the ground (houses as a whole, camp patches draped over it). The ground is drawn as
  32 x 32 chunks of 128 m whose detail follows the camera (2 m between vertices close by, up to 32 m
  far off, skirts hiding the seams) and painted by slope and height: grass, dirt on the steeper bits,
  rock on cliffs, sand where the waves reach, snow above about 480 m, from the CC0 surface sets. One
  water plane at the sea's level is the sea and every lake. Feet, the camera, creatures, merchants
  and the target ring follow the ground; the camera sees 5.7 km, fog from 450 m to 2.6 km.
- Checked in the harness: the village on its pad with the crater behind it, the bay, the ponds, an
  aerial view. Tests: 682 Elixir (6 new), 84 JS (4 new). **Not checked in a real game** (walking,
  creatures on slopes, fishing in Crater Lake, a mount over the crater).

**Delivered 2026-10-26 (b), committed** (`67414f8`, `handoff/CLAUDE_CODE_PROMPT_2026-10-26b.md`): **guard poses for
two-handers, the owner's bug list, and the sea, the Millpond and fishing.**

- **Two-handers held like weapons, not hugged.** The 25c fix put the left hand back on the haft, but the
  owner was right that the *poses* were wrong: the clips' idles hold the greatsword, maul and battle axe
  inside the waist, bend the spear arm until the elbow breaks, and run the staff through his legs. Now,
  while a two-hander is drawn and neither hand is swinging, `human-factory.ts` blends (over ~0.2 s) into
  a guard pose from `TWO_HAND_GUARDS`: where the right hand goes and where the weapon points, in units of
  the body's own pelvis-to-neck height (so it fits both bodies and every slider). Greatsword: forward
  and up at chest height. Axe and maul: across the body, head high on the left. Spear and halberd:
  levelled forward at the hip, elbows down. Staff: across the body at chest height, clear of the legs.
  The arm is solved by two-bone IK (`ik2`) with the elbow pole down, out and back, then `twoHandGrip`
  places the left hand as before. Swings still play the clips untouched. Checked in the harness on
  both bodies from the front, the side and three-quarters: no clipping.
- **Screenshots no longer open the Esc menu.** Taking a screenshot (PrintScreen, Snipping Tool, Game Bar)
  takes the browser's focus, which drops the pointer lock, and the game read every lost lock as Esc. A
  lost lock now waits 160 ms and opens the menu only if the window still has focus, wasn't hidden or
  blurred around then, and PrintScreen wasn't pressed in the last 1.5 s (`lockLossWasEsc`, 4 tests).
- **Esc clears the target first**, then (pressed again) opens the menu. A target that dies, despawns or
  **respawns** is dropped, so a respawned creature is no longer quietly re-targeted.
- **Skill points update on level-up** without a refresh (`refreshSkills`).
- **The skill window drags smoothly**: it moves by its title bar only (a drag anywhere used to move the
  window *and* pan the tree, which read as snapping to a grid), with compositing hints.
- **Casting no longer freezes the game.** Every spell added a PointLight on impact and removed it after;
  in three.js a change in the number of lights recompiles every lit material in the scene, which was
  the 2-5 s stall (Recall too). Three pooled lights are now added once at intensity 0 and borrowed; the
  spark and roots materials are shared and no longer disposed (disposing the last user of a shader
  also forces a recompile next time).
- **Looting the EverQuest way:** an empty corpse says "You find nothing on X's corpse." and opens no
  window. **G takes everything** from the nearest corpse without a window; the window opens only for
  what didn't fit (inventory full). Left-click still opens the window for a corpse with items.
- **No more hard refreshes after a deploy.** No LiveView ever asked `static_changed?`, and the game's
  unfingerprinted files (sounds, pictures, plugin scripts) were cached for a year. A hub `on_mount`
  hook (`Bacon8Web.StaticReload`) reloads the page on the next navigation once the static files have
  changed, and plain static files are kept an hour, then revalidated (digested `app.js`/`app.css` stay
  immutable). BACON8.md has the hub side.
- **The sea, the Millpond and fishing.**
  - **The island ends at 150 m** (`BaconWorld.Water`, mirrored by `water.ts` with the same rules and
    tests on both sides). A sand beach slopes from under the grass's edge into a sea that runs to the
    horizon, with a bobbing swell and foam at the waterline; nobody walks past 151.5 m (client clamp;
    the server refuses a move that ends further out than it started, so anyone already out there can
    still walk home). The grass disc is now 141 m.
  - **The Millpond**, a 24 x 16 m pond 50 m north-west of the square (-31, -40), with a mud bank,
    reeds, lily pads and an angler's gap on its east bank. Its edge is a collider.
  - **Old Bram, Angler** stands on that bank and sells the **fishing pole** (30 copper; two-handed,
    a staff-set item with its own guard pose and a procedural model with a cork grip and reel).
  - **Fishing**: with the pole in hand, face the water from the bank or the beach and press **R** to
    cast; the bobber flies out up to 10 m. A bite (3.5-12 s later, timed by the server) pulls the
    bobber under with a splash: press **R** within 1.8 s to reel in (80% chance to land it). Moving,
    dying or putting the pole away ends it. The pond and the sea have their own catches: perch, brook
    trout, mud carp, a rare **golden carp** and old boots; mackerel, striped bass, red snapper, a rare
    **silver tuna** and kelp. Fish stack to 20 and sell to merchants (icons rendered in Blender by
    `library/pipeline/scripts/fishing_icons.py`, shipped in `priv/static/icons/`).
  - Sounds reuse the CC0 drip and loot recordings for now; real surf and splash recordings are a
    follow-up (the CC0 sites are blocked from the build machines).
- Tests: 676 Elixir (14 new for water and fishing), 80 JS (8 new).

**Delivered 2026-10-25 (c), uncommitted** (`handoff/CLAUDE_CODE_PROMPT_2026-10-25c.md`): **two-handed grips,
fourth time, found by measuring instead of tuning.** The owner: the male "STILL does not hold ANY 2 handed
weapon correctly". Rendered in the harness and measured: **the male's clips already hold every two-hander
with the left grip within 1 mm of the haft.** What broke it was `twoHandGrip` itself: after the posture
and shoulder corrections moved the arms, it forced the left hand to the fixed `HOLD.off`, which on the
axe, maul and greatsword is on the wrong side of the right hand (+0.32 m where the clip has -0.16 m: the
arms crossed, the left reaching past the right) and on the spear and halberd beyond his reach (0.45 m
asked, 0.37 m reached: the left arm locked straight across the chest). Now `readClipGrip` measures where
the clip puts the left grip along the haft before any correction, and the IK puts it back there;
`HOLD.off` is only the fallback for a clip whose left hand isn't on the haft (more than 8 cm off).
Checked on both bodies, all six two-handers, idle and every swing: the left grip stays within about
1 cm of the haft at the clip's spacing. 72 JS tests pass.
**Lesson:** the earlier rounds checked "is the hand on the haft line" and passed; nobody checked *where*
on the haft. Check spacing and both arms, from three sides, before calling a grip fixed.

**Delivered 2026-10-25, uncommitted** (`handoff/CLAUDE_CODE_PROMPT_2026-10-25a.md`): **the sound pass.**
The owner: *"multiple ambient sound tracks ... a wide range of sound effects ... sound immersion
needs to be world-class, but not overdone, loud or jarring."* Placed sound (pan, distance,
low-pass, a voice cap, a master compressor), spell schools, dragon and mount voices timed to their
animations, flight wind, hard landings, lair and high-altitude beds, rare ambient details, music
by mood (menu, 7 day, 3 night, 3 lair, boss) with long rests between tracks, and soft UI
roll-overs and clicks. All CC0 (OpenGameArt, Kenney), loudness-normalised per category by
`library/pipeline/scripts/audio/build_audio_v2.py`. Code: `lobby-audio.ts` (rewritten, old API
kept), `audio-mix.ts` (new, tested), hooks in `dragon-view.ts`, `mobs-view.ts`, `mounts.ts`,
`game-world.ts`, `skills-world.ts`, `world-character-ui-scene.ts`. The same handoff gives
RaysSpaceSim its whole soundscape (RAYSSPACESIM.md).

**Delivered 2026-10-24 (sixth), uncommitted** (`handoff/CLAUDE_CODE_PROMPT_2026-10-24f.md`): the skill tree, the stable,
the two-handed grips again and the dismount glitch, from the owner's testing of the fifth.

- **Two-handed grips (the male).** The off hand's place on the haft now comes from the weapon
  (`items.ts` `HOLD[...].off`, metres along the haft from the main hand: axe and maul 0.32,
  spear 0.45, halberd 0.42, staff 0.5, greatsword -0.13), not from the clip. The clip-derived
  side flipped on the muscular male, which put his left hand off the butt, at his hip.
- **The stable**: Rowena Ashby, Stablemaster (`merchants.ex` kind `"stable"`), at a new paddock
  next to the plaza (fences, hay, water). R opens the stable window (`stable-ui.ts`):
  every mount, which you own, "Ride this one", and a Buy link to the store for the rest.
  The choice is saved (`settings["mount"]`) and M summons it; before, the newest purchase won
  (and the first, red, for admins).
- **The dismount glitch.** Dismounting in the air left the player falling where the server's
  movement checks rejected him and kept correcting him (the vibration). Now M refuses while
  airborne (client, and the server above 2.5 m: reason `airborne`), and for 8 s after a
  dismount the server still validates moves against the mount's limits.
- **The skill tree** (K), Path of Exile style: one tree for everyone (`skill_tree.ex`), stored
  in `bacon_world_skill_trees` (new migration) and edited at **/admin/bacon_world/skills**
  (drag spells, skills and buffs from a palette onto nodes; add, move, join, delete nodes;
  Save validates; "Reset" restores the shipped tree). The shipped tree: **Recall** at the
  centre (learned by everyone at level 1) and six branches: Minor Healing, Fireball, Vigor
  (+10 HP), Insight (+10 MP), Entangling Roots, Spin Attack. Each level from 2 gives one point;
  a node can be learned when it touches one you have.
- **Abilities** (`abilities.ex`, `skills.ex`, `skill_events.ex`): spells have mana, cast times
  (moving interrupts), cooldowns and range; the server resolves them. Recall goes to the bind
  point (`settings["bind"]`; nothing sets it yet, so the zone's spawn). Heal (self or the
  targeted player), Fireball (a travelling bolt), Roots (6 s; a boss gets a third), Spin
  Attack (every enemy within reach, 360 degrees). Buffs add to max HP/MP (and melee/spell %).
- **Hotbars**: skills go on Q E F Z X (the special-attack slots); spells on a new **spell bar,
  two rows of ten, bottom right** (1-0 and Shift+1-0), movable like the other windows. Drag
  from the tree window onto a slot; learning a node puts it on a free slot. Saved per
  character (`settings["hotbars"]`). Effects in `spell-fx.ts`; the icons are emoji for now.
- **Its card on /games** (a hub feature, BACON8.md §9): a card with a front (Baconator's head)
  and a back (his eye, the details, Play) that turns over on hover. The files are in
  `priv/static/card/`; admins change it on the new **/admin/bacon_world** page.

**Delivered 2026-10-24 (fifth), uncommitted** (`handoff/CLAUDE_CODE_PROMPT_2026-10-24e.md`): the boss, the mounts and flight, from the owner's request for "more
monsters", a dragon boss named Baconator, and dragons to ride and fly.

- **The skeletons, the owner's question.** There is one human skeleton *definition*, the B8
  skeleton (67 bones, `b8_skel.py` / `b8_skeleton.json`; same names and hierarchy for both). Each
  body has its own *fit* of it (rest proportions and orientations, `mh_rig.py`), so the
  animation packs are baked per body (`Humans/Anims/B8_Female_*`, `B8_Male_*`). The skeleton
  creatures use the male's fit and packs. New human-shaped monsters can do the same. The dragon has
  its own rig (below), and the boss and the mounts share it.
- **The old rigs, removed** (moved to `tmp/_to_delete/2026-10-24_old_rigs/`, since deleting needs the
  owner's OK): the four old skeleton packs (`priv/static/models/Mobs/Anims/*`, the folder is left
  empty), `build_humans2.py`, `b8_head.py`, `b8_garments.py`, `mhm_facial.py`, and the v2 male
  backup. `build_humans.py` stays, because it holds the shared helpers and the skeleton definition.
  Some code still points at files that are now gone, and it is left as it was: `build_anims.py`
  (`HUMANS`, the humans2 blend), `build_hair.py` and the `OLD` defaults in `mhf_finish.py` /
  `mhf_transfer.py`.
- **The dragon model** (original; the owner's reference art, which is Games Workshop's, set
  only the mood: big, red, horned, winged, breathing fire). It is built from code in three scripts:
  - `build_dragon.py` makes the rig, the clips, the assembly and the export.
  - `dragon_shape.py` makes the sculpt. The torso, neck, tail and skull are lofts. Muscle masses
    are laid over the bones: pectorals, flight muscles, deltoids, biceps and triceps, forearms,
    haunches, thighs with quads and hamstrings, calves, and neck muscles. A voxel remesh
    (2.5 cm) fuses them into one skin, a Taubin smooth blends the joins, and fields carve the eye
    sockets, nostrils and ribs. The jaw is a second, finer sculpt with a hard jawline edge, so the
    mouth opens. Parts are built at game resolution: ridged, twisted horns (a great pair, a
    second pair, cheek fans, jaw frills, brow horns, a crest), teeth with fangs, a forked tongue,
    hooked claws, dorsal blades, the wing bones with knuckles, membranes that sag between the
    fingers, and almond eyes.
  - `dragon_skin.py` makes the skin. The sculpt is decimated to the game mesh, which then takes
    its weights from the primitives and is baked in Cycles. The bake covers the form (normals),
    shingled Voronoi scales (finer on the head and toes), banded belly plates that run the length
    of the spine, a mouth, horn and claw gradients, membrane leather (veins, creases, pores),
    serpent eyes with glowing irises and a black slit, and roughness and AO.
  - The export has three materials: `Dragon_Skin` (a 4K atlas), `Dragon_Membrane` (2K,
    double-sided) and `Dragon_Eye` (emissive). Its WebP textures are put through meshopt.
  - The numbers: 54k triangles, 7.6 MB (7.0 MB gzipped; 4K skin WebP, roughness resized to 2K) on the web, and it builds in about 25 (the first full build took 45, with 48 AO samples; it's 16 now) minutes
    headless (`tmp/b8work/jobs/dragon_go.py`). It is 16.75 m long with a 21.4 m wingspan, and
    Baconator is 0.8 of that.
  - The rig (46 joints) and the 13 clips are the same as in the first cut: Idle, Walk, Run, Fly,
    Hover, Glide, Bite, Claw, TailSwipe, Breath, Roar, Hit and Death.
- **Baconator** (`spawns.ex`) is level 12, 1,400 HP plus 50 per level, and lives in his own camp,
  Baconator's Lair (92, 42 m; `world-dressing.ts` `lair`). The lair is scorched ground ringed by
  crags, with a hoard of coins, gems and a chest behind him, bones, dead trees, braziers and a
  waystone.
  - His moves are bite, claw and tail (the tail hits for ×0.8).
  - He also breathes fire every 13 to 18 s: a 17 m cone (±32°) after a 1.05 s windup ("rears back
    and draws a deep breath!"), so you can dodge it. It hits everyone in the cone.
  - Reach and body radius are per kind, and he leashes at 55 m. He ignores and drops players who
    fly over 6 m up.
  - He respawns in 20 to 30 minutes.
  - Loot: dragon scales, Baconator's fangs, and a chance at the Emberforged Longsword, the
    Dragonbone Greataxe and the Scaleplate Shield. Their icons are `W_DragonScale` and
    `W_DragonFang`, rendered with the dragon's own materials (`build_dragon_icons.py`).
- **Mounts** (`BaconWorld.Mounts`, entitlement kind `bacon_world_mount`) are three drakes:
  Ember, Verdant and Frost. They are the dragon at 0.38 scale and are hue-shifted in the client
  (`hueShift` in `dragon-view.ts`, from the boss's colours to the mount's).
  - Speeds: 10 m/s on the ground (Shift ×1.5) and 17 to 18 m/s in the air (Shift ×1.6).
  - Store prices: $15, $15 and $18. The store items are created inactive by
    `BaconWorld.Mounts.ensure_store_products/0` and stay hidden until the owner publishes them.
    Admins ride all three for testing.
  - Controls: **M** (or `/mount [id]`, `/dismount`) climbs on and off. You can't fight from the
    saddle, and dying drops you off.
  - Riders sit astride (the `Sitting_Idle_Loop` clip with the thighs turned out). They are
    seated on the saddle bone each frame (`mounts.ts`). Everyone sees mounts through the zone
    presence and `zone_mount`.
- **Flight, like RaysSpaceSim**: on a mount that flies, **double-tap Space** to take off or land
  (within 0.28 s, as `JumpDoubleTapSeconds` in `CosmicFlightComponent.h`).
  - W and S follow the camera's pitch (look down and press W to dive), A and D strafe level,
    Space climbs and C dives. There are no rolls.
  - Altitude is capped at 120 m. The server allows a mounted speed of 45 units/s and heights up
    to 160 units on a flier. Motion bit 4 tells others you fly, and the dragon plays Hover, Fly or
    Glide.
- **Two-handed grips (the owner, 2026-10-24: "every 2 handed weapon I picked up is wrong" on the
  male).** The clips place both hands for the library's mannequin. On each body's own fit, and
  with the male's longer clavicles and arms, his left hand ended up 15 cm off the haft (the
  female was about 4 cm off). `human-factory.ts` `twoHandGrip` now runs a two-bone IK on the left
  arm whenever a two-handed weapon is held, idle and swings alike. It puts the left grip
  (`weapon_l`) on the haft line (`weapon_r`'s +Y), as far from the main hand as the clip had the
  hands apart (at least a hand's width). It keeps the elbow in its plane, turns the hand along
  the haft, and eases in and out (`CharacterAnimator.armSets()` now returns `two`). Checked in
  the harness on both bodies with the spear, maul, quarterstaff and greatsword, idle and swings.
- Tests: `mobs_test.exs` gained the boss's five tests (61 tests, all pass, warnings as errors),
  and `flight.test.ts` was added (68 JS tests, all pass; the bundle and type-check are clean).

**Delivered 2026-10-24 (fourth), committed** (`c8597cd`, `handoff/CLAUDE_CODE_PROMPT_2026-10-24d.md`, with the
third, below), from the owner's look at the third:

- **His upper body leaned back**: `spine_deg` is now [-24, -4, 0] (the chest's 14 degrees went;
  the lumbar fix stays). His neck now sits ~5 cm ahead of the pelvis, as hers does.
- **His hands** weren't relaxed: they rested on his thighs, bent forward at the wrist, fingers
  splayed over the leg. Empty arms now hang 6 degrees out, the wrist is straightened
  (`free_hand_deg` [-20, 8, -12]) and his fingers curl more than hers (`relaxed_hand`).
- **Torch**: his elbow was tucked and the torch leaned in. The torch arm goes 12 degrees out at
  the shoulder and 18 at the elbow, so it is held upright at his side like hers.
- These are new `posture` fields in `human-factory.ts`: `arm_out` {what the arm does: [upper,
  fore, keep hand?]} (what the arm does comes from the new `CharacterAnimator.armSets()`:
  'free', the held item's set such as 'torch', 'two_hand', 'swing'; two-handers and swings get
  nothing), `free_hand_deg` and `relaxed_hand`. The female has none of them, so she's unchanged.
- **Shoulders narrower**: a new male morph, `Shoulders_Narrow` (MakeHuman shoulder distance
  -1.0, v-shape -0.3 against his look's 0.3 / 0.5; the arms come in 44 mm by joint offsets),
  and his Shoulders slider now runs -1..1 (Narrow..Broad; 0 is his approved look). The
  female's stays 0..1 (`minFor` in `appearance.ts`, a clamp in `appearance.ex`). His whole body
  was rebuilt for it (`mfull.cmd`); his hair and facial hair GLBs have no Narrow key yet, which
  only shows on long styles at the narrow end.

**Delivered 2026-10-24 (third), committed** (`c8597cd`, `handoff/CLAUDE_CODE_PROMPT_2026-10-24c.md`):

- **The male's lower back and shoulders** (owner, 2026-10-24). Both came from the library
  clips, not the mesh: the idles arch the lumbar (the "S" from pelvis to upper back, with the
  crease above the pelvis) and draw both clavicles back about 30 degrees, which on his long
  clavicles (17.5 cm to her 11.4) put his arms behind the torso and his shoulders up. His
  manifest now has a posture like hers, `{"pelvis_tilt_deg": 30, "spine_deg": [-24, -6, 14],
  "clavicle_deg": [18, 6]}` (her values left his lumbar arched; the spine became [-24, -4, 0] in
  the fourth delivery). `clavicle_deg` is new in
  `human-factory.ts` (shoulders forward, down; any body may use it; the female has none, so she
  is unchanged). Written by `mhm_build.py`; `Male.json` and `out/mh/male/B8_Male.json` patched
  in place (no rebuild needed: it is manifest data).
- **Skeleton creatures on the new male**: `build_skeleton.py` now rigs on the MakeHuman male's
  armature, moving its hand-placed pieces (skull, ribs, pelvis, vertebrae) by the old rig's
  landmarks, so it fits his proportions. `mobs-view.ts` plays his packs
  (`Humans/Anims/B8_Male_Anims_*`); `Mobs/Anims/` is no longer loaded (delete it once the owner
  agrees). The model is meshopt now (72 KB, was 250).
- **The hand axe's bit faced backward** (owner's screenshot). The one-handed swings lead with
  the weapon bone's -Z and the weapons file puts the striking side on +Z, so every one-handed
  weapon with one striking side needs `roll: 180` in `HOLD` (`items.ts`), as the scimitar and
  cutlass already had: now the hand axe and war hammer too (and the hatchet, machete and
  builder's hammer, in the weapons file but not yet items). **Rule for new weapons**: a new
  single-sided one-hander goes in `HOLD` with roll 180; two-handers need none (their swings
  were refitted to +Z).

**Delivered 2026-10-24 (second), committed** (`3e8c225`, `handoff/CLAUDE_CODE_PROMPT_2026-10-24b.md`):

- **Loot click bug**: left-clicking the corpse you were already looting opened the game menu.
  The click grabbed the mouse and the loot window let it go at once; both pointer-lock events
  then arrived reading "unlocked", and the second looked like the browser's Esc. The
  controller now only acts on a real lock change, a left click on a corpse no longer grabs
  the mouse (`lockOnClick`), and clicking the corpse you're looting does nothing.
- **Player names**: Bacon8's blue (`#247DF1`), red (`#E62929`) with PvP on, black outline kept,
  for you and for others (the PvP flag now rides in the zone presence). The target window
  uses the same colour. The font is a plain bold Arial-style sans, like old EverQuest's.

**Committed 2026-10-24** (`handoff/CLAUDE_CODE_PROMPT_2026-10-24a.md`): **the male
rebuilt on MakeHuman**, like her (section 5): body and skin (the legs' red calmed), wardrobe
shells and MakeHuman garments, the stage-G body sliders except the chest shaping, 18 MakeHuman
hair styles (his old style ids alias to them), his six facial hair styles refit to the new
head, and his animation packs rebuilt on his rig (no fanned fingers). The skeleton creatures
keep the old male packs (`Mobs/Anims`), since they're built on the old skeleton. The site's
Credits page names MakeHuman (a migration). Models are staged; they ship together with the
code. The owner's check found the skeletons work as before.

**Delivered 2026-10-23 (eighth), committed** (`handoff/CLAUDE_CODE_PROMPT_2026-10-23h.md`):
the sun and moon now sit in the sky (far along their direction from the camera, not 55 units
from the plaza); the site's navbar/taskbar toggle works (state on `<html>`, which LiveView
doesn't patch); moved windows come back where they were after logging in again (they were
placed while the game's layer was still 0 x 0).

The seventh (`handoff/CLAUDE_CODE_PROMPT_2026-10-23g.md`) moved the asset pipeline to
`library/pipeline` and deleted the v1 humans (done).

**Delivered 2026-10-23 (sixth)** (`handoff/CLAUDE_CODE_PROMPT_2026-10-23f.md`):

- **Respawn bugs**: the zone's presence now gets your spawn position the moment you respawn
  (creatures kept attacking the spot where you died until you moved, and you kept dying), and
  you respawn clear of other players. A move that takes you away from a player you overlap is
  allowed (before, two players on one spot couldn't separate).
- **No centre dot** with the mouse captured.
- **Movable windows** (`window-drag.ts`): drag any window (player, target, hotbar, inventory,
  loot, merchant, chat) by its title or an empty spot; positions are saved per browser; the Esc
  menu's "Reset windows" puts them back.
- **Left drag with the cursor free turns the camera** around the character (she keeps facing
  her way), and letting go doesn't capture the mouse or pick a target.
- **The male, started**: MakeHuman sources fetched into `library/makehuman` and a first male
  look (`mh_female.LOOKS["m1"]`) rendered for the owner's review; see section 7.

**Delivered 2026-10-23 (fifth)** (`handoff/CLAUDE_CODE_PROMPT_2026-10-23e.md`), from the
owner's play-testing:

- **Melee arcs**: 90 degrees for one-handers, 110 for two-handers (was 150), and nothing behind
  you is hit however close (anything within 35% of the reach used to count).
- **Daggers stand in the one-handed sword's idle** (both arms breathe alike; the authored
  dagger idle held the dagger arm still and the elbows out), and the stab and slash start
  and end in it.
- **Two-handers**: the battle axe and maul are held near the end of the haft (client `HOLD`,
  the haft no longer hangs between her legs); the swings were refitted with the striking side
  leading the cut (the axe hit with its flat); and grips now turn the shortest way between
  keys (`b8_anim.lerp_grip`; the weapon twirled near the end of the heavy).
- **The scimitar and cutlass** are turned 180 degrees about the handle (they cut with their
  back).
- **Merchant window**: right-click to buy, right-click a bag item to sell (the sell slot is
  gone), and the list keeps its scroll position.

**Delivered 2026-10-23 (fourth)** (`handoff/CLAUDE_CODE_PROMPT_2026-10-23d.md`), from the
owner's testing of the two-handed weapons:

- **Weapon grips refitted on the female** (`b8_clips.py`, new `b8_gripfit.py`): the spear's left
  hand no longer reaches behind her back (right hand rear at the hip, left hand forward, the
  shaft sliding through it in thrusts); the **quarterstaff is held two-handed** across the body
  in its idle (it used the one-handed magic-staff rest, the left hand held in the air, and
  grabbed the staff mid-swing) with a new two-handed heavy, `QStaff_Sweep`; the two-handed sword
  in a middle guard (her arms had been locked straight); **dual daggers ready at the sides** like
  the one-handed sword. Wrists under 10 degrees in every guard. Her packs were rebuilt.
- **Idle hands**: the relaxed curl roughly halved, the thumb opened.
- **Posture**: pelvis tucked 24 degrees with spine_01 turned back by the same, `spine_deg`
  [-24, -9, 9]: the lower back flattens without the S-curve and the crease above the pelvis
  (the earlier [6, -11, -13] arched the lumbar again).
- **Credits page**: a migration adds "Surface textures: ambientCG and Poly Haven, CC0 1.0" to
  `/pages/credits` if it isn't there (owner's request).

**Delivered 2026-10-23 (third)** (`handoff/CLAUDE_CODE_PROMPT_2026-10-23c.md`):

- **Real surface textures on the untextured models.** None of the village props, building
  kit, weapons or the skeleton has UVs; their materials are plain colours named for what they
  are. `surface-textures.ts` maps each material name to a CC0 texture set (ambientCG and Poly
  Haven, from the shared library) and projects it triplanar in the mesh's own space (metres),
  with normal, roughness and ambient-occlusion maps, so no model was re-exported. Most
  materials keep their colour and gain the texture's pattern around it ("detail"); the kit's
  brick uses the texture's own colours. Stone walls, roof tiles, slate, thatch, planks, beams,
  rock, bark, straw, rope, canvas, cloth, leather, metals and bone are covered; glass, gems,
  potions, fire and paint stay plain.
- **The ground**: grass, dirt paths, the plaza (fan-laid paving), the plaza rim, the camp
  patches and the barrow mound use real textures, with large-scale variation to hide tiling.
- **24 texture sets** in `models/World/Textures/` (1K/512 WebP, 9.4 MB; `CREDITS.md` beside them).
- A **Textures** on/off button in the Esc menu (applies after a reload; off restores the old
  look with canvas noise).

The second 2026-10-23 delivery, committed, deployed and synced (`handoff/CLAUDE_CODE_PROMPT_2026-10-23b.md`):

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
  - `Male.glb` (MakeHuman, staged 2026-10-24) and `Female.glb` (MakeHuman v3, 2026-10-23), each with its `.json`;
  - `Wardrobe/`: the female's 36 packed design textures (`.webp`), `Wardrobe/Male/` his 10, and
    `icons/` for the 20 wearable items;
  - `Anims/`: the four animation packs (core and combat for each body, 143 clips a body);
  - `Hair/`: 18 male hair and 6 facial hair styles, 31 female hair styles, icons, `hair_manifest.json`;
  - `README.txt` and `CREDITS.md`.
- `Weapons/B8_Weapons.glb` (43 weapons, shields and tools).
- `Mobs/B8_Skeleton.glb` (rigged on the MakeHuman male since 2026-10-24; plays his packs), and
  `Mobs/Anims/` (the old male packs, no longer loaded).
- `World/B8_Props.glb` (90 props) and `B8_BuildKit.glb` (36 building pieces); `World/Textures/`:
  24 surface texture sets (`<set>_c/_n/_r.webp`) and `CREDITS.md`.
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
| 2026-10-27 | **The boss Kraken is 1.5 times its first size and roams the lake freely** (no set path). |
| 2026-10-27 | **Mounts attack.** The dragons breathe fire and claw; the Kraken's moves were ours to choose (Tentacle Lash, Maelstrom). |
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
  `chest`, `legs`, `feet`), not the look. Each is a garment mesh plus a design: a packed
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

In rough priority order.

**The Kraken (2026-10-27), to check in a real game:** its numbers (HP, damage, how often the specials
come, the maelstrom's pull) are first guesses; tune them after a fight. It needs real CC0 water sounds (a
big splash, a whirlpool's roar, a wet slap, an ink spurt). The model is ~98k triangles: fine for one boss,
but with many riders on Kraken mounts at once a lighter level of detail for the mount is worth building.
Being held and dragged are applied by the victim's client (as creature damage is), not enforced by the
server's move checks.

**World building in game (the owner's plan, 2026-10-26; decisions log):**

- **Placements are data.** A table (`bacon_world_placements`: zone, asset id, position, rotation, scale,
  owner, placed at) holds everything put in the world; the server validates and stores each placement,
  the zone's PubSub broadcasts it, and every client draws it (instanced by asset). The village that
  `world-dressing.ts` builds in code today becomes the first rows (an import), so it can be edited the
  same way. Colliders come with each asset.
- **An asset catalogue** like the item catalogue: each placeable asset's model, footprint, collider,
  category (ground, building piece, rock, tree, bush, prop, creature spawn, NPC, binding stone) and the
  lowest role that may place it. **Admins set that per asset, in game** (a permissions view in build
  mode, stored in a table, not in code); guests never place anything; boss creatures and binding
  stones start admin-only. Placing and deleting check the role on the server, never only in the client.
- **Placing in game**: a build mode (a window listing what you may place), a ghost of the piece on the
  ground under the cursor (snapped to the terrain, and to the building kit's 3 m grid for building
  pieces), rotate, place. **Delete: anyone allowed to place that asset may delete any copy of it**,
  whoever placed it. No limits per player, no decay. Undo for a short while.
- **Ground types** are painted, not placed: a coarse grid over the zone (per 2 m cell: grass, dirt,
  stone, sand, farmland...) read by the terrain shader instead of its slope rule where painted.
- **Creatures and NPCs** become placed spawn points (kind, count, radius, respawn), read by
  `BaconWorld.Mobs.Spawns` from the table instead of its code; merchants the same.
- **Binding stones**: an admin-only asset. Using one (R) sets `settings["bind"]` (Recall and respawn go
  there); no placement by anyone else is allowed within its radius (about the town's: 70 m, a setting).
  The town's stone goes by the plaza.
- Answered by the owner (2026-10-26, decisions log): admins set permissions per item in game, guests
  get none, no limits, no decay, placing a kind means you may delete it.

**Terrain (2026-10-26, c):**

- The owner to walk it in game, and to confirm the map's orientation (the RAW's first row is taken as
  north, -z).
- **Sync `World/Terrain/` to production** with the owner's OK (`sync-models-to-k8s.sh`); until then
  production stays on the flat island (BaconWorld.Terrain finds no files and falls back).
- Painting is by rule (slope, height); World Creator's splat and scatter maps (a newer World Creator)
  would paint and plant it properly. No normal maps on the ground yet; distant chunks are plain.
- The land outside the village is empty: the in-game placement above is the plan for filling it.
- Creatures walk through hills (they follow the ground's height but ignore slopes) and stop dead at
  deep water rather than going round it. Server-side walls still don't exist (the village's colliders
  are client-side).
- Swimming: no diving, no breath, no underwater view (the camera stays above the surface); weapons
  stay in hand while swimming. A real CC0 stroke/splash recording would beat the drip.
- Crater Lake and the ponds use the lake catch table; Crater Lake could get its own fish.
- Zone lines (a ferry from the bay, a pass in the ridges) when there's a second zone.

**Water and fishing (2026-10-26, b):**

- The owner to try the guard poses, the sea, the Millpond and fishing in game; tune the poses in
  `TWO_HAND_GUARDS` (human-factory.ts) and the catches in `BaconWorld.Water` from what he says.
- Real CC0 recordings for surf, a cast, a splash and a reel (they reuse `sw_drip` and `loot` now).
- Catching is flat (80% on a timely reel): no fishing skill, bait or rod tiers yet. Cooking the fish.
- The sea is a wall: no swimming or boats. The lake's edge is a client-side collider, like the village's.
- Spell lights are pooled (three): a fourth effect at once just goes without a light. New effects should use
  `takeLight`/`giveLight` and shared materials, never add or remove lights or dispose shared materials.

**The skill tree (2026-10-24, sixth):**

- The owner to try it in game and grow the tree at /admin/bacon_world/skills. New *kinds* of
  ability (not just placing existing ones) need code: an entry in `abilities.ex` and its effect
  in `skill_events.ex` (and `spell-fx.ts`).
- A bind-point NPC or spot that sets `settings["bind"]` (Recall uses the zone spawn until then).
- Painted ability icons instead of emoji. (Cast sounds: done 2026-10-25 for fire, holy, nature
  and arcane; a new school needs a `cast_loop_<school>.mp3` and a `CAST_SCHOOL` entry.)
- Spell targeting of other players for harm (PvP fireball) isn't wired; heal works on players.

**Monsters and mounts (2026-10-24):**

- The owner to look at Baconator and the drakes in game (BACON_WORLD §2, fifth delivery); tune
  the sculpt in `dragon_shape.py` (muscle blobs, skull table `SKULL`, jaw `JAW`) and the skin in
  `dragon_skin.py` from what he says. Renders: `jobs/render_go.py <glb> <out> [clip:t] [shots]`.
- Mount store items: run `BaconWorld.Mounts.ensure_store_products/0` (owner's OK), then publish.
- More monsters: human-shaped ones on the male's or female's fit (like the skeletons), more beasts on
  the dragon rig (a wyvern or drake without wings is a material and a few shapes away).
- The rider's seat (`SEAT_DROP_M`) on very tall or short bodies; a saddle prop.
- Flying: no aerial combat yet; Baconator ignores fliers over 6 m.

**The male's posture** (done 2026-10-24, section 2; all of it is in `mhm_build.py`'s `POSTURE`):
tune it with the harness's `?tilt=`, `?spine=a,b,c`, `?clav=fwd,down`, `?arm=free:u,l;torch:u,l`,
`?fh=x,y,z` and `?relax=index:a,b,c,s;...` (either body; they override the manifest). Render side
views (`view=side&yaw=18` shows his idle in profile, `focus=spine_02&dist=2.9&az=250&el=0` the
lower back) of idle, walk and the stances. The female could take a smaller `clavicle_deg` if
her shoulders ever look set back; she hasn't had one.

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

**The male (rebuilt on MakeHuman 2026-10-24; the plan, all done):**

1. **The look** (done): `mh_female.LOOKS["m2"]`, approved by the owner as is (1.78 m,
   athletic, angular face).
2. **Body** (done): `B8_BODY=Male mhf_core.py` builds his skin (Toigo's light
   male skin, Skins 02 pack, greyed for tinting), eyes, brows (`eyebrow008`), Mindfront lashes
   01, the B8 skeleton and weights, and the 13 morph keys (the chest keys are his pectorals).
   Output `library/pipeline/out/mh/male_core.blend`. His skin paints red knees and shins:
   `calm=0.7` takes most of the colour out of the legs' and seat's detail.
3. **Wardrobe** (done, `mhm_build.py`): underwear bottoms (classic, boyshort), tank, shorts and
   trousers as body-derived shells; the MakeHuman tee, sweater, shoes and boots. Then
   `mhf_morphs.py` adds the waist, limb and glute-lift keys (body and garments).
4. **Hair** (done): 18 MakeHuman styles with scalp decals (`B8_BODY=Male mhf_syshair.py`).
   His old card styles alias to the closest (CrewCut to Short, Buzz to Crop, and so on). The
   six facial hair styles are his old ones refit to the new head (`mhm_facial.py`).
5. **Animation packs** (done, `B8_BODY=Male mhf_anims.py`): the same clips and grips as hers
   (the grips are in the clip specs, so `b8_gripfit.py` didn't need a rerun; they look right).
   **No A-pose fanned fingers** (the owner, 2026-10-23): every clip must key the fingers (the
   library bakes do; authored clips set a finger preset), and the client's relaxed hand covers
   empty hands.
6. **Client** (done): `Male.json` in her shape, his sliders (`appearance.ts`/`.ex`: only the
   chest shaping stays hers), the default male hair is `Short`, and existing male characters
   carry over through the hair aliases (their shape values use the same keys).

Sources (CC0) are in `C:\Bacon8\library\makehuman` (gitignored): the MPFB2 repository's data,
MakeHuman's system assets (the Ubuntu `makehuman-data` package and the community
`makehuman_system_assets` pack), and the community packs (hair01, shirts01, pants01, shoes01,
underwear01, suits01, eyebrows01, eyelashes01, skins01-03). Not every skin in the skins packs is
usable for us; the light Toigo skins are what's used.

**Game (from BACON8.md's debt list, moved here):**

- The skill tree itself (Q E F Z X), armour beyond cloth, more merchants, and groups with
  shared loot.
- **The skeleton creatures** share the male's packs (2026-10-24) but not his posture
  correction (it lives in `HumanInstance`), so they keep the clips' arched back and drawn-back
  shoulders; bones don't crease, so it reads fine. Old `Mobs/Anims/` awaits the owner's OK to
  delete. The halberd's sweep wasn't checked for which way its blade leads.
- The male's six facial hair styles are refits of the old procedural cards; MakeHuman has no
  CC0 beard set yet.
- The female's **hair** GLBs weren't re-fitted for the joint offsets (only `Shoulders_Broad`
  moves joints, so hair is unaffected for now).
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

**Surface textures (next):**

- The cloth armour and the underwear have design textures already; the leather and plate
  armour still to come should use the library's leathers and metals the same way.
- Move `pack.py` (library set to runtime WebP, with the means `SETS` needs) into
  `library/pipeline/scripts/` and generate `SETS` from it.
- Triplanar costs about ten texture reads per pixel on textured surfaces. Fine on desktop;
  if low-end machines struggle, the Esc menu's Textures switch turns it off. A cheaper path
  is baking UVs and textures into the GLBs in Blender (the Substance bake can do the same).
- Trees' leaves, food, paint and gems are untextured on purpose (they read as stylised).

**Assets still wanted:** weapon animations per weapon type, finished and polished (see
`library/pipeline/Characters/ANIMATION_ROADMAP.md`), and a building system for the 36
kit pieces.

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
  `under_top`, `under_bottom`, `chest`, `legs`, `feet`), `main`, `off`, `tilt`, `spine`, `clav`,
  `rest=1` (the bind pose), `mob=1` (the skeleton creature on the male's packs). `village.html?mode=dragon`
  (`scale`, `clip`, `t`, `tint=scales,membrane,eye`, `fly=1`, `yaw`) and `mode=lair` show the dragon
  and the lair. Each frame
  leaves `window.POS` (key bone positions, metres) for measuring. The harness's
  `catalog.json` is a copy of the items: add an item there before trying it.
- **Staging models**: copy into `priv/static/models/...`, make the `.glb.gz` (`gzip -9 -k -f`),
  back up what's replaced under `tmp/b8work/backup_models/`.
- **Deliver**: a `handoff/CLAUDE_CODE_PROMPT_<date><letter>.md` for Claude Code, and update
  §2/§7 here and the project's copies of this file and BACON8.md.

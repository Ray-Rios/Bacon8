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

Last update: **2026-11-01**.

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
- **Terrain Ground Mesh Integration** (2026-10-31 fix): When a 3D terrain heightfield is loaded (`hasTerrain` / `groundAt`), the old flat island ground geometry (the 141 m circle of grass, flat plaza, and dirt paths in `world-dressing.ts`), mob camp earth patches (`patch()`), barrow mound (`SphereGeometry`), warren burrow discs, and the scorched ground discs in Baconator's lair are completely bypassed so they do not collide or z-fight with the zone's new 3D terrain mesh. `WorldDressing` construction now awaits terrain heightfield readiness (`groundReady`) before laying out camps and props, preventing race conditions where props and camps were built at flat elevation Y=0.
- **Water**: wading to 1.2 m; deeper water is swum (slower, no jumping, fighting or fishing), **C** swims down and
  **Space** up. Mounts swim too. `water.ts` mirrors `BaconWorld.Water` with the same tests on both sides.
- **Fishing**: Old Bram, Angler, sells the pole; **R** casts and reels in; the Millpond and the sea have their own
  catches. The bobber is a curl of bacon (`crafted.ts`).
- **Sound**: placed sound (pan, distance, low-pass, a voice cap, a master compressor), spell schools, dragon and
  mount voices, beds and music by mood. CC0 sources, built by `library/pipeline/scripts/audio/build_audio_v2.py`.
- **Procedural Nature Sound & Ambient Integration (2026-10-31)**:
  - **Phase 1 (Audio Core & Asset Caching)**: Added `ambient-catalog.ts` mapping all 100 procedural WAV audio files in `/assets/audio/` across 5 categories (Rain & Storms, Wind & Foliage, Water & Ocean, Campfire & Crackles, Night Insects & Birds). Integrated Service Worker (`sw-game.js`) caching for `/assets/audio/` to guarantee zero-latency persistent disk caching on subsequent reloads. Extended `LobbyAudio` (`lobby-audio.ts`) and `audio-mix.ts` with transparent WAV decoding, ambient aliases, randomized audio pools, lazy on-demand bed loading (`ensureBed`), and decoupled volume scaling.
  - **Phase 2 (Water & Swimming Audio)**:
    - Shorelines & Lakes: dynamically blends `water_06_calm_sandy_beach_waves_loop` near ocean shorelines and `water_08_gentle_lake_lapping_loop` near lakes (Millpond, Crater Lake) in `tickAudio`.
    - Underwater Immersion & Muffling: when swimming and diving (`isSwimming && dive > 0`), fades in `water_10_underwater_submerged_ambience_loop` while dynamically sweeping an underwater low-pass filter (`BiquadFilterNode` down to 380 Hz) across surface effects, wind, combat, and music.
    - Water Movement & Splashes: walking in shallow water plays `water_17_water_wading_slosh` footsteps; swimming strokes trigger rhythmic splashes; jumping or falling into water plays `water_15_water_splash_medium_jump` or `water_16_water_splash_large_plunge` based on air time instead of ground thuds.
    - Fishing Audio: bobber cast lands with `water_14_water_splash_small_stone`, and fish bites trigger splash and tug cues.
    - Water Sweeteners: nocturnal frog croaks (`wildlife_17..18`), ocean wave washes (`water_11..13`), and cavern drips (`water_18..20`) dynamically scheduled based on player proximity to lakes and shores.
  - **Phase 3 (Campfires & Positional 3D Fire Audio)**:
    - Comprehensive fire detection in `tickAudio` across village campfires, goblin camps, Orc warcamps, and player-built campfires/braziers.
    - Blends `fire_01_cozy_campfire_steady_loop` near standard campfires, `fire_02_roaring_bonfire_loop` near Orc warcamps, and `fire_06_brushfire_crackle_wall_loop` inside Baconator's Lair.
    - Scheduled 3D fire sweeteners near fire sources: pine wood snaps (`fire_07..10`), spark crackle bursts (`fire_11..13`), and sap sizzles (`fire_14..15`).
  - **Phase 4 (Diurnal Wildlife & Foliage Atmosphere)**:
    - Diurnal clock synchronization with `SkySystem` wall-clock time $t$: blends `wildlife_04_dawn_forest_bird_chorus_loop` during dawn ($t \approx 0.22 - 0.32$), `wildlife_03_midday_cicada_drone_loop` during high noon ($t \approx 0.45 - 0.62$), and `wildlife_01_summer_night_cricket_chorus_loop` at night.
    - Biome wind beds: `wind_02_steady_forest_wind_loop` in woodlands, `wind_03_howling_canyon_wind_loop` in barrows/ruins/gorges, and `wind_06_mountain_summit_draft_loop` at high altitudes.
    - Foliage sweeteners: songbirds (`bird_song`) and woodpeckers (`woodpecker`) by day in woods, crickets (`night_cricket`) and owls (`owl`) by night, tree trunk/branch creaks (`tree_creak`), and tall grass swishes (`foliage_grass_step`) during meadow movement.
  - **Phase 5 (Dynamic Weather, Visual Atmosphere & Lethal Lightning)**:
    - 30-minute real-world synchronized weather cycle: Clear skies (18m) $\to$ Light Drizzle (`rain_drizzle`, 3m) $\to$ Steady Rain (`rain_steady`, 4.5m) $\to$ Thunderstorm (`rain_thunderstorm`, 3m) $\to$ Post-storm clearing (1.5m).
    - Shelter-aware attenuation: dynamically routes rain audio to `rain_canopy` under trees, `rain_tent` near camp tents, `rain_cabin` inside or near wooden village cottages, and open rain over fields.
    - **Lightweight Overhead Clouds (`weather-system.ts`)**: Single horizontal quad mesh (2,800m $\times$ 2,800m at Y=280m, 1 draw call, 2 triangles) dynamically following the camera. Uses a procedural multi-octave FBM dual-scrolling noise shader that smoothly shifts from soft daylight cirrus clouds to dark slate-grey storm thunderheads, illuminating with electric cyan-white bursts on lightning flashes without GPU overhead.
    - **Dynamic Raindrops (`weather-system.ts`)**: Camera-wrapping particle system (2,000 line streaks, 1 draw call) that wrap in a 50m $\times$ 50m $\times$ 32m bounding volume around the player. Streaks angle with storm winds; density and opacity scale with weather intensity and dynamically attenuate inside shelters (completely clear inside cabins).
    - **Sky Lightning Bolts**: Procedurally generated branching jagged lightning across cloud altitudes, flickering during storm peaks.
    - **Lethal Ground Strikes (Instant Overkill Death)**:
      - During thunderstorms (`rainIntensity >= 0.70`), ground lightning strikes threaten outdoor players every 14-25 seconds.
      - **Warning Telegraph (1.8s)**: A glowing 3.5m electric warning ring appears on the ground with pulsing cyan-yellow hues and crackling ground sparks, providing players time to sprint or evade.
      - **Strike Impact (0.24s)**: A massive vertical jagged bolt strikes straight down with an electric flash and `thunder_strike` audio boom.
      - **Lethal Radius (3.5m)**: If an outdoor player is caught inside the radius, they take extreme overkill damage (99,999) via `lightning_struck`, instantly killing and shattering their character!
    - **Extreme Damage & Character Shatter (`smash-fx.ts`)**:
      - When a character suffers death from overkill damage ($\ge \text{max\_hp}$, including lethal lightning or devastating hits), their character model explodes into physics debris pieces using `SmashFx.shatterCharacter`.
      - Traverses the character's clothing, gear, and body meshes, isolates parts, unsets skinning for instant rigid instanced rendering, and launches chunks with gravity, terrain collision/bouncing, rotation, settling, and fading, accompanied by crimson gore, spark, and dust puffs.
      - Server (`GameEvents.take_hit`) computes `overkill? = damage >= max_hp`, broadcasts `"shattered"` status in `zone_hp` for all clients in the zone, and pushes `character_died` with `shatter: true`. On respawn, character meshes cleanly restore visibility.
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
- **Smashing & Object HP** (2026-10-31):
  - Smash mode is moved out of build mode into an in-game combat toggle on the character's info bar (alongside PvP).
  - When Smash is toggled ON, players can damage and destroy placed objects with their weapons (melee & bows), spells, and skills. **Who may break what** (2026-11-01): the build-mode delete rule, i.e. what your role may place, and nothing within a binding stone's 100 m unless GM or admin (`Building.damage_placement/4`); a targeted piece must be in reach. Before, anyone could break anything from anywhere in the zone, the village, binding stones, camps and merchants included, and a broken placement is deleted for good. Placed objects show an HP bar in the target frame and trigger floating damage numbers on hit.
  - Every placed asset has hit points (default: 10 HP). Live health is tracked in `:bacon_world_placement_hp` ETS. Surviving hits broadcast `{:build_damaged, id, asset, new_hp, max_hp, amount}` and trigger dust and mesh jiggle; reaching 0 HP shatters the object into debris (`{:build_removed, id, asset, :smashed}`) via `smash-fx.ts` and removes it from the database.
  - Damaged placed objects naturally regenerate 10% of their max HP per tick (driven by `BaconWorld.BuildingRegen`, synchronized with `Tuning.get("regen_interval_ms")`). Surviving repairs broadcast `{:build_repaired, id, asset, new_hp, max_hp, healed_amt}` and smoothly update the target frame HP bar; reaching 100% cleans the entry from ETS.
  - Admins can configure each asset's max HP in-game via the build catalogue window (`AssetRule.hp`, table `bacon_world_asset_rules`), broadcasting `{:build_hp_rule, asset, hp}`.
  - In build mode, right-clicking an object now instantly shatters/destroys it (with debris FX) rather than silently vanishing it, but only if the player's account has permission to place/move that asset (`Building.delete/4` enforces `can_place?`).
- **Stacking & Snapping** (2026-10-31):
  - Objects stack on top of each other in build mode: pointing the cursor at an existing placed object raycasts its bounding box and sets the support height to the top surface (`box.max.y`), allowing floors, walls, crates, roofs, and props to stack vertically.
  - Snapping aligns pieces both vertically (stacking to the object's center and orientation, or 1.5m / 3m surface grid) and horizontally (proximity snapping to adjacent pieces and foundations, leveling elevations flush with each other). Holding `Alt` enables freeform placement at arbitrary positions and rotations.
- **Object Duplication & Multi-Object Side-by-Side Placement** (2026-10-31):
  - **Duplicate (`Shift + Left-Click`)**: In build mode, Shift+Left-Clicking any placed object (or Shift+Left-Clicking while an object is selected) grabs an exact copy of that object (inheriting asset, rotation, scale, elevation lift, and data) without moving or hiding the original object. Players can immediately stamp down duplicates nearby.
  - **Multi-Object Side-by-Side (`Shift + Scroll Wheel`)**: When holding any object, Shift+Wheel dynamically increases or decreases the number of items to place down side-by-side (1 to 10). Dynamic semi-transparent ghost previews display the entire row aligned along the piece's lateral axis (spaced by the asset's bounding width or modular 1.5m kit grid). Clicking places all pieces simultaneously, and Shift+Click commits the row while keeping another line ready in hand.
- **Picking placed things** (2026-10-30 fix): an InstancedMesh measures its bounds on the first raycast and keeps
  them. A piece placed or moved outside those bounds could not be clicked, so it could not be picked up.
  `placed-view.ts` now forgets the bounds on every write (`stale()`).
- **Building & Combat Performance Architecture** (2026-10-31):
  - In-game rules (`rules()`) and HP rules (`hps()`) are cached in `:persistent_term`, ensuring zero database queries during placement listing or combat damage calculations.
  - Placements are cached in ETS (`:bacon_world_placements_cache`), making `Building.get` and `Building.placement?` instant in-memory lookups.
  - AoE, spin, and cone smash attacks only execute if the player has Smash toggled ON, and query only bounded local coordinate boxes (`[x - r, x + r]`, `[z - r, z + r]`) in SQL rather than scanning the entire zone.
  - Natural HP regen operates directly on ETS state without database lookups during ticks.
  - LiveView account presence checking recognizes reconnections of the *same* character, preventing players from being locked out with "account is already logged in" after reconnects or reloads.
  - Removed obsolete `buildSetSmash` call in `buildExit`, allowing '`' and the close button ('✕') to close the build window without client exceptions.

- **Reference Nature & Rock Assets (Trees, Saplings, Stumps, Logs, Boulders, Ores, Crystals)** (2026-11-01):
  - Procedurally generated in Blender (`library/pipeline/scripts/build_props.py`, `b8_kit.py`) and integrated into `B8_Props.glb`:
    - **Trees**: Oak Tree (`TreeOak`), Pine Tree with pine cones (`TreePine`), Weeping Willow (`TreeWillow`), Gnarled Dead Tree (`TreeDead`), Birch Tree with white bark (`TreeBirch`), Enchanted Tree with bioluminescent cyan foliage and violet trunk (`TreeEnchanted`), Blossom Tree with warm amber trunk and glowing orange/coral foliage (`TreeBlossom`).
    - **Saplings & Stumps**: Sapling Oak (`SaplingOak`), Sapling Pine (`SaplingPine`), Sapling Birch (`SaplingBirch`), Mossy Stumps with shelf bracket fungi (`StumpMossy`), Hollow Decayed Stump (`StumpHollow`), Fallen Hollow Log (`LogHollow`), Clustered Fallen Logs with vines (`LogCluster`).
    - **Rocks & Minerals**: Angular Granite Boulders (`BoulderGranite`), Granite Boulder Cluster (`RockGraniteCluster`), Rounded Mossy Rocks with fern tufts (`RockMossy`), Mossy Rock Cluster (`RockMossyCluster`), Dark Ore Nodes with metallic gold veins (`OreDarkVein`), Hexagonal Crystal Clusters with point glow in blue, purple, and green (`CrystalsBlue`, `CrystalsPurple`, `CrystalsGreen`), Small Pebbles Scatter (`PebblesScatter`), Stepping Stones path set (`SteppingStones`).
  - Registered in `BaconWorld.Building` under `"Trees & plants"` and `"Rocks"`, available in build mode for all players with member rank or higher.
  - Surface triplanar detail textures and emissive glow mapping added in `surface-textures.ts` and `placed-view.ts`.

- **Modular Building Kit Expansion (Walls, Doors & Openings, Floors & Roads, Roofs, Stairs & Transitions)** (2026-11-01):
  - Procedurally generated in Blender (`library/pipeline/scripts/build_kit.py`, `b8_kit.py`) and integrated into `B8_BuildKit.glb` (141 pieces):
    - **Walls & Facades (32 pieces)**: Upgraded core stone and timber walls; added Coarse Cobblestone, Rough Granite, Sandstone Brick, Dry Stone, Ancient Mossy Stone, Fine Red Brick, Burnt Red Brick, Industrial Brick with coping, Plaster with exposed brick, Intact Timber-frame, Decayed Timber-frame, Ornate Tudor with chevrons, Horizontal Log Cabin walls with notched ends, Vertical Log Palisade, Thatch Mud wall with window, Reinforced Iron wall with cross-braces, Rusting Plate wall, Rough Wood wall, Horizontal Lap Plank wall, Intricately Carved Nordic knotwork wall, Decorative Marble wall with classical cornice, Plaster on Stone Base, Curved Stone Wall (90° quadrant), Angled Stone & Log Corners, T-junction Stone Wall, and Crumbled / Collapsed / Blasted Ruin walls.
    - **Openings, Portals, & Doors (27 pieces)**: Upgraded wooden doors, gates, and glazed windows; added Rustic Plank door with Z-brace, Heavy Iron-Studded door, Heavy Jail Bar door with lock plate, Arched Cathedral twin doors, Double Wooden Gate, Ornate Scrolled Iron Gate with spears, Dilapidated broken wood door, Sliding Barn Door on overhead iron rail, Spiked Iron Portcullis, Exterior Angled Cellar Hatch, Small Square Barred Stone Window, Arrow Slit Flared Embrasure, Circular Bullseye Leaded Window, Ornate Stained Glass Gothic Window, Leaded Diamond Glass Window, Standard 4-Pane Window, Double-Pane Mullioned Window, Ornate Carved Classical Archway, Hewn Timber Archway with knee braces, Red Brick Semicircular Archway, Deep Arched Stone Passageway, Ruined Broken Archway, and Dungeon Gate.
    - **Floors, Grounds, & Roads (24 pieces)**: Modular 3m × 3m tiles including Flat Dirt, Mud & Embedded Gravel, Patchy Grass, Lush Fern Grass with 3D fronds, Forest Floor Leaf Scatter, Desert Sand Dune ripples, Uneven Cobblestones, Fine Stone Paver flagstones, 45° Herringbone Brick Street pavers, Dungeon Flagstones, Rotting Decay Wood planks, Sturdy Parquet Timber tiles, Industrial Rusty Iron Grating, Broken Cobblestone Crater, Mossy Flagstones, Overgrown Stone Path, Cracked Parched Mud, Fired Clay Terracotta tiles, Patterned Inlaid Terracotta, and Worn Oriental Rug on Wood floor.
    - **Roofs (20 pieces)**: Upgraded Thatch, Tile, Shingle, and Ridge pieces; added Thatch Roof Peak & Corner Hip, Weathered Wood Shingle Slope & Peak, Ornate Carved Bargeboard Gable, Red Clay Spanish Barrel Tile Slope & Peak, Slate Shingle Slope & Valley, Corrugated Rusty Tin Metal Roof, Mossy Slate Roof, Damaged Shingle Roof with exposed rafters, Ruined Collapsed Thatch, Flat Stone Rooftop with parapet coping, Turquoise Verdigris Copper Spire Peak, and Overgrown Leafy Turf Living Roof.
    - **Verticality, Stairs, & Transitions (20 pieces)**: Upgraded straight wood and stone stairs and ladders; added Chipped Weathered Steps, Sweeping 90° Curved Stone Stairs, Grand Monumental Stone Staircase with balustrades, Welded Industrial Steel Channel Stairs with pipe rails, Steep Ship's Ladder Steps, Hemp Rope Ladder, Double-Width Wooden Ladder, Spiraling Stone Central Newel Stairs, Spiraling Wood Cantilever Stairs with balusters, Short Wood Cleated Ramp, Mud & Timber Retaining Ramp, Heavy Stone Ramp with curbs, Modular Scaffolding Base, Scaffolding Extension, and Scaffolding Platform with side access ladder.
  - Registered in `BaconWorld.Building` (`@kit`) in the `"Building"` category for build mode (press `` ` ``).
  - Triplanar surface detail textures and PBR shaders configured in `surface-textures.ts` for all 22 new kit materials.

### Combat and creatures

- Melee for both hands (arcs 90 degrees one-handed, 110 two-handed), looting EverQuest style (G takes everything),
  levels, coins, con colours, PvP with red names. Bows never run out of arrows (cone hit along the aim; arrows fly
  and stick for four seconds).
- **PvP & Smash Spells, Skills & Mount Attacks** (2026-10-31):
  - Spells and skills (projectiles, direct damage, AoE, cones, spins, strikes, and dash impacts) can now target and hit PvP-flagged opponents when both caster and target have PvP toggled ON.
  - Placed/buildable objects take smash damage when Smash mode is ON when hit by:
    - Direct combat skills (`strike`) either with a direct target or sweeping in an arc in front of the player.
    - Spin Attack (`spin`) hitting all buildable objects within the character's weapon and spin reach.
    - Frontal cones (`cone`) and AoE circles (`aoe`).
    - Dash arrival impacts (`dash`).
    - Mount special attacks: Drake Claw Swipe (left) and Fire Breath cone (right); Abyssal Kraken Tentacle Lash (left) and Maelstrom (right) damage placed objects in their reach and arc, and damage PvP players in the sweep.
  - Placed object queries utilize `Building.list/1` and round damage values to ensure clean, consistent damage against ETS-cached and database placements.
- **Spin Attack Stability & Animation** (2026-10-31 fix): Fixed LiveView crash on `spin_attack` execution caused by undefined `Melee.base_damage/2`. Implemented `Melee.base_damage/2` and routed damage roll through `Melee.roll_damage/5` with weapon damage, player level, and skill multipliers. Mapped spin attack animation to `Sword_Regular_B` and added `Sword_Regular_C` fallback alias in `anim-driver.ts`.
- **Spells and skills** (2026-10-30 expansion): **207 abilities** (`BaconWorld.Abilities`) — **Recall** + **100 spells** across ten schools of ten (*Fire, Frost, Storm, Arcane, Holy, Nature, Shadow, Blood, Earth, Water*, cast from the 2×10 spell bar, `1-0` and `Shift+1-0`) + **100 combat skills** across ten archetypes of ten (*Blade, Berserker, Blunt, Polearm, Rogue, Ranger, Guardian, Monk, Warlord, Survival*, on `Q E F Z X V`) + **6 passive stat buffs**.
  - **15 server-side effect types** (`BaconWorldWeb.SkillEvents`, `BaconWorld.Mobs.Brain`): `"recall"`, `"heal"` (direct + HoT ticks), `"damage"` (projectiles/beams + DoT, stun, root, slow, knockback, pull), `"drain"` (lifedrain / mana siphon), `"aoe"` (self- or target-centred circle AoE), `"cone"` (frontal breath / shockwave / barrage), `"chain"` (multi-target arc jumps), `"root"` (single-target or AoE hold), `"stun"` (single-target or AoE stun/incapacitate), `"shield"` (absorb barrier + temporary AC), `"buff_temp"` (combat stances, shouts, meditations), `"dash"` (forward leaps/charges/dives and backward disengage vaults, terrain-checked, with arrival slam), `"spin"` (360° whirlwinds), `"strike"` (cleaves, executes below 35% HP, bleeds, sunders, ranged shots), `"taunt"` (single or AoE challenge), and `"stat"` (passive buffs).
  - **Icons & palette** (`skill-tree-canvas.ts`, `skill-tree-editor.ts`): glossy school-coloured circular spell icons, rounded-square archetype skill icons, and golden buff icons with 65+ crisp SVG inner glyphs. The `/admin/bacon_world/skills` editor features a searchable **Grid / List** palette with **All / Spells / Skills / Buffs** filter tabs.
  - **3D visual effects** (`spell-fx.ts`): school-tinted cast auras, projectiles, beams, meteors, pillars, shockwave novas, frontal cones, jagged lightning/heal chains, protective ward spheres, dash/leap trails, 360° whirlwinds, weapon slashes, and taunt rings — all using shared materials and `LightPool` (`takeLight`/`giveLight`) so zero shaders compile during play.
- **Damage calculation & Armour AC mitigation** (`BaconWorld.Tuning`, `BaconWorld.Melee`, `BaconWorldWeb.GameEvents`):
  - **Hit Chance**: `clamp(0.84 + (AttackerLevel - DefenderLevel) × 0.04, 0.30, 0.96)`.
  - **Base Melee Roll**: `Weapon.dmg × U(0.75, 1.25) + floor(Level / 3)` (rounded, minimum `1`).
  - **Heavy Swing**: Two-handed right-click multiplies damage by `×1.50` (`heavy_mult`) and swing delay by `×1.35` (`heavy_delay_mult`).
  - **Critical Hits**: Melee `6%` (`melee_crit_chance`) for `×1.75` (`melee_crit_mult`); Spells `6%` (`spell_crit_chance`) for `×1.60` (`spell_crit_mult`), plus any active stance/buff crit bonus.
  - **Skill & Buff Multipliers**: Passive skill-tree nodes (`Might +5%`, `Arcana +5%`) and temporary combat buffs add `1 + pct / 100`.
  - **Armour Class (AC) Mitigation**: Sum of equipped items' `ac` across all worn & hand slots (`main`, `off`, `head`, `chest`, `legs`, `feet`, `under_top`, `under_bottom`) plus temporary AC buffs. Incoming creature and PvP hits are reduced by the hyperbolic curve `Reduction = AC / (AC + K)` where `K = 35` (`ac_half_point`, capped at `ac_max_reduction = 75%`), then absorbed by any active **Shield** barrier (`SkillEvents.absorb_shield/2`) before subtracting HP (minimum `1` damage when unshielded).
- **Character Stats Readout** (`Melee.stats_sheet/4`, `game-ui.ts`): the Inventory & Equipment (`I`) window includes a live **Character Stats** readout displaying Level, Armour Class (AC), Damage Reduction %, Active Absorb Shield, Main-Hand Weapon Damage Range (`min–max`), Heavy Swing Range, Delay & estimated DPS, Melee Hit % (even con), Melee Bonus %, Melee Crit % & multiplier, and Spell Bonus % & Spell Crit %.
- **World-Tuning Admin Tab** (`/admin/bacon_world/tuning`, `BaconWorldWeb.Admin.TuningLive`): live admin interface (also linked from `/admin/bacon_world` and `/admin/bacon_world/skills`) exposing all 18 combat, AC mitigation, creature scaling, and progression parameters (stored in `bacon_world_skill_trees` key `"tuning"` and cached in `:persistent_term`), complete with an interactive AC Mitigation Curve preview and full combat formula documentation.
- **Groups** (`BaconWorld.Groups`): up to 20, `/invite`, `/accept`, `/disband`, `/makeleader`, `/g`; experience is
  split by level (`Groups.shares/2`), loot by anyone in the killer's group, coins split among those near.
- **Creatures**: skeletons, giant and plague rats, goblins and goblin archers, orcs and orc warlords, and two
  bosses: **Baconator**, the dragon (level 12, his own camp on the plateau NE of the crater), and the **Kraken**
  (level 16, roams the deep water of Crater Lake; its specials are grab, ink and maelstrom, wound up so players can
  see them coming). Camps are placements now.
- **Mounts** (entitlement kind `bacon_world_mount`, sold in the Bacon Store; the stablemaster Rowena Ashby chooses
  one): three drakes that fly (double-tap Space, like RaysSpaceSim) and the Abyssal Kraken that swims. Riders fight
  with the mount's moves (claw and fire breath; tentacle lash and maelstrom). Drake flight altitude ceiling is zone-wide
  (100 m above the highest peak in the zone anywhere in the zone, e.g. 772 m on Crater Lake, enforced both on client and
  server `validate_ground_bounds`), allowing unrestricted flight over valleys, lakes, and crater rims.

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

### Loading, hitches and names (2026-10-30, not yet deployed)

- **Entering the world**: `fetch_mobs` (creatures, camps, placements, merchants, water; about 200 KB) used to
  give up after 5 s and draw an *empty* world: terrain only, with creatures that could hit you but weren't drawn.
  World entry also ran up to three times at once (each sent its own `fetch_mobs` and its own position heartbeat).
  Now: one entry at a time (`worldEntering`) and one heartbeat. `loadWorldState` waits 30 s a try, retries with
  backoff and never treats "no answer" as "nothing there". A "Loading the world..." note shows meanwhile. A creature
  the client doesn't know (`mobsView.onUnknown`), or a LiveView reconnect, triggers a resync (`resyncWorld`, at most
  every 8 s).
- **The map's edge**: the skirts along the map's own edge used to be vertical curtains with copied up-normals. They
  were painted and lit like flat grass, which made a streaky band round the perimeter. They are now a sloped rock
  apron (`APRON_RUN`, 0.7 m out per metre down) with outward normals. The map's four corners have a small wedge
  where two aprons don't meet.
- **First-use freezes** (a drake's first breath took seconds): three.js compiles a shader the first time a material
  kind is drawn. It also recompiles *every* lit material when the number of lights in the scene changes, and each
  breath used to add and remove its own light. Fixes: `light-pool.ts` (four lights added once, handed out and taken
  back; spells and breaths share it); `warmup.ts` (compiles a stand-in of every effect material kind against the
  scene's lights while the world loads); and `watchShaders()`, which logs `[bacon world] shader compiled during play:
  <type>` for any program built later. A new effect that shows that line needs a stand-in in `warmUp`.
- **Nameplates**: a name never gets smaller than 15 px on screen (it used to shrink into a few pixels). The texture is
  mipmapped, so far names don't shimmer, and they show to 90 m. Overlapping names are culled each frame: the nearer
  one wins, and the target always shows.
- **Game asset service worker** (2026-10-31, rewritten 2026-11-01): `/sw-game.js` (registered by `service-worker.ts`)
  keeps `/models/**`, `/audio/**` and `/fonts/**` in the browser's CacheStorage (`bacon-world-assets-v2`). A URL with
  `?vsn=` (every model URL) is answered from the cache with no network request; anything else from the cache at once
  and refreshed in the background at most hourly. **The first version never reached production**: the Dockerfile copies
  `priv/static` file by file and didn't list `sw-game.js`, so `/sw-game.js` was a 404 (both Dockerfile stages copy it
  now). It also re-downloaded every model in the background on every load. `window.bwCache.info()` / `.clear()`.
- **Ambient sounds** (2026-10-31, fixed 2026-11-01): 100 synthesized ambience files (kept: the owner dropped the
  real-recordings-only rule on 2026-11-01). They sat in
  `priv/static/assets/audio/` (91 MB), which the image never copied, so every one was a 404, and `lobby-audio.ts`
  re-requested a failed file every time the beds were re-mixed (four times a second): about 4,000 404s an hour on
  production. Now MP3 copies (mono, 96 kbit/s, 13 MB) in `priv/static/audio/world/ambient/<category>/`, and a file that
  failed once isn't asked for again that visit. The WAVs were deleted on 2026-11-01 (owner's OK).

### Human Characters, Wardrobe & Sliders Overhaul (2026-10-31, completed)

- **Unbaked Scars & Blemishes**: Body blemishes and battle scars are completely removed from the baked base character
  meshes and base skin textures (`b8_anatomy.py`). The base human models (`Female.glb`, `Male.glb`) are pristine athletic
  anatomy without baked scars or ridges. Scars/blemishes are optional selections in character creation (`appearance.ts`,
  `front-ui.ts`, `human-factory.ts`) with segmented options: `None`, `Cheek`, `Body`, `Battle`. They are rendered dynamically
  via custom Three.js shader injection (`b8skin1` with `b8ScarsMap` and `b8ScarsMix` uniforms) using unbaked overlay textures
  staged in `priv/static/models/Humans/Scars/` (`scars_cheek.webp`, `scars_body.webp`, `scars_battle.webp`).
- **Arm-Wraps as Purchasable Wrist Items**: The forearm, wrist, and bicep wraps are completely removed from base body meshes
  and skin albedo textures. A dedicated `"wrist"` gear slot is added across client and server (`items.ex`, `merchants.ex`,
  `wardrobe.ts`, `human-factory.ts`, `b8_shell.py`, `mhf_wardrobe.py`, `mhm_build.py`). `linen_arm_wraps` is available for purchase
  in-game from Tilda Threadwell the Clothier for 25 coins (+1 AC). The 3D geometry is cleanly segmented as `Wrist_Wraps` with
  authentic heavy canvas weave textures (`Wrist_Wraps__wrist_linen.webp` and `_n.webp`).
- **High-Realism Underwear & Clothing Revamp**: Completely overhauled all in-game underwear and clothing assets with authentic
  physically based fabric weaves and tactile normal relief (`b8_wardrobe_tex.py`, `b8_designs.py`). Added combined micro-ribbed
  knit and twill yarn weaves, double-needle flatlock topstitching with recessed tension troughs, elastic edge piping with gathering
  ripples, and crisp seam ambient occlusion. Rebaked all 16 female wardrobe designs and male wardrobe designs, staged into
  `priv/static/models/Humans/Wardrobe/`.
- **Compelling High-Detail Hair Assets Revamp**: Completely overhauled all 49 hairstyle assets (31 female, 18 male) in
  `mhf_syshair.py`. Added dynamic tangent-space strand normal map synthesis derived from directional opacity and luminance gradients,
  yielding round, 3D cylindrical hair fiber illumination instead of flat alpha ribbons. Calibrated material roughness (0.42)
  and specular IOR level (0.65) for natural, silky sheen. Rebuilt all GLBs, meshopt compressed, generated updated preview icons,
  and staged into `priv/static/models/Humans/Hair/` alongside `hair_manifest.json`.
- **Amplified Body Sliders**: Drastically increased the physical range of influence for all body and shape sliders. In
  `mhf_morphs.py`, displacement fields were doubled and amplified (~2.2x) across all key zones: `Chest_High`/`Chest_Low` (0.055m),
  `Chest_Wide`/`Chest_Close` (0.050m), `Waist_Narrow` (58.9mm), `Waist_Wide` (65.2mm), `Arms_Slim` (36.8mm), `Arms_Thick` (69.6mm),
  `Thighs_Slim` (43.9mm), `Thighs_Thick` (68.6mm), `Calves_Slim` (53.9mm), `Calves_Thick` (80.9mm), and `Glutes_Lift` (22.3mm).
  These amplified shape keys are baked directly into `Female.glb` and `Male.glb`, providing dramatic silhouette variation from
  svelte/runner frames to powerhouse/heavyweight builds while maintaining standard [0..1] normalized client weights.

### The v3 humans (2026-11-01)

Built by three new pipeline stages on top of stage G (`library/pipeline/scripts`, outputs in `out/mh_v3/`; jobs in
`tmp/b8work/v3/`: `v3body.cmd`, `v3face.cmd`, `v3hair.cmd`, `meshopt_v3.cmd`, then `stage_v3.py`):

- **H, `body_v3.py`**: the bodies subdivided once (Catmull-Clark on the limit surface; every shape key subdivided the
  same way through a key-less copy), 13,380 -> ~57k vertices (female) / ~53.5k (male), plus one flat extra level on the
  female's breasts before the smoothing. Weights, UVs, `_REGION` (nearest original vertex) and all sliders carry over.
  A second level on the face is opt-in (`B8_V3_FACE=1`): it nearly doubled the body.
- **H3, `face_v3.py`**: six face sliders as displacement fields around landmarks the script finds (eyes, nose tip, mouth,
  chin, jaw angles, cheekbones): `Cheekbones`, `Jaw_Square`, `Chin_Strong`, `Brow_Heavy`, `Lips_Full`, `Nose_Narrow`,
  on the body, brows and lashes, and on the male's six facial hair styles so beards follow. Client sliders: appearance.ts
  `cheekbones`, `jaw_square`, `chin`, `brow`, `lips`, `nose_width`; server: `Appearance` `@shapes`.
- **H2, `hair_v3.py`**: every hair style is now **grown**, not a MakeHuman proxy: roots planted inside a hairline on the
  scalp, strands combed (part, swept back, fringe, crown), pulled by gravity, kept out of the body (BVH) and off the
  face, cut, and turned into textured cards with volume normals; gathered styles run on into a ponytail, a three-lock
  braid or a bun. A scalp decal (dense to soft at the hairline) under each. 18 female styles (Cascade, Waves, SideSweep,
  HighPonytail, LowPonytail, Braid, TwinBraids, TopKnot, Bun, Bob, BobBangs, Lob, Pixie, Undercut, Curls, Afro,
  WarriorBraid, HalfUp) and 14 male (Buzz, Crew, SidePart, SlickBack, Pompadour, Undercut, Messy, Curly, Shoulder,
  LongTied, ManBun, Mohawk, Viking, Afro). Every retired style id maps to one of these (`aliases`). The strand atlas
  and its normal map are made by the script (numpy), so all of it is original.

### Garment parts: real clothes (2026-11-01, second pass)

The owner rejected the texture-painted underwear ("designed in MS paint... pixelated") and asked for photo-realistic
underwear, ten full sets of cloth armour and ten robes, all unique. Every worn item is now its own skinned GLB per body,
loaded like the hair (`Humans/Garments/<Body>/<id>.glb`), cut from the v3 body and dressed in photographed fabrics:

- **Generator** `library/pipeline/scripts/b8_garments.py` (Blender 5.1, `run_pipe.py`): panels are regions of the body
  cut along the zero line of a field drawn in its charts (torso: angle and "levels" from crotch to throat; breast: a
  geodesic map about the apex; legs and limbs: angle and distance along the bone; head: azimuth/elevation), fitted as a
  membrane held off a smoothed copy of the skin (nipples smoothed with a dome of their height, crotch and buttock cleft
  filled, so cloth bridges them), with a turned edge for thickness. Straps, bindings, piping, seams, lacing, ruffles,
  fringe, rings, sliders, hooks, bows, beads, buckles, belts, skirts (hung from the body's slice hulls, bridging the
  legs; pelvis/thigh weights), hats (lathes, brims, plumes), soles and hull-shell mittens are swept or built
  procedurally. Weights and every body morph come from the skin point under each vertex; big pieces are decimated to a
  budget. Previews and item icons are rendered in Eevee. Designs: `b8_garment_designs.py` (underwear) and
  `b8_armor_designs.py` (cloth armour, robes). Jobs: `tmp/b8work/garments/full_female.cmd`, `full_male.cmd`,
  `stage_garments.cmd` (meshopt into the models volume).
- **Fabrics** `b8_fabrics.py`: 44 CC0 photo-scanned sets from Poly Haven and ambientCG (`library/textures`, fetched
  2026-11-01 and logged in its LICENSES.md) made into `Humans/Fabrics/<fabric>_c|_n|_r.webp` (neutral grey for tinted
  fabrics, so one texture takes any item colour; `gain` brings the mean to the colour). Lace: two real lace scans,
  Rijksmuseum/The Met open-access CC0 photographs on Wikimedia Commons, keyed to alpha and tiled
  (`lace_chantilly`, `lace_garland`), drawn blended as a veil over the skin.
- **Client** `garment-parts.ts` (cover sets, masks; unit-tested), `garment-materials.ts` (fabric materials: role tint,
  sheen for satin/velvet, sheer opacity, lace blending), `human-factory.ts` (loads parts, binds them to the bones, sets
  morphs, hides skin under them and inner layers under outer ones, clips hair inside a hat), `wardrobe.ts` (`part`,
  `layer`; slots `hands` and `arms`; layers under 0, legs 2, chest 3, feet 4, arms 5, wrist 6, hands 7, head 8, robes 9).
  A part's extras carry `cover` (a voxel set of the body it hides, rest metres) and each vertex its skin point
  (`_ANCHOR`), so hiding needs no body ids and survives body rebuilds of the same shape.
  - **Items**: 19 underwear sets (ten cloth + four chainmail bikinis: `chain_iron`, `chain_brass`, `chain_steel`, `chain_gold` + five heroic plate bikinis: `plate_steel`, `plate_gold`, `plate_dark`, `plate_draconic`, `plate_mythril`; cloth 6c a piece, the metal bikinis 40-300c with AC 1-2; the male wears each set's bottom in his own cut: subligaculum, war-trunks, and plate war-girdles); 19 armour sets of seven pieces (ten cloth + four chainmail sets: `chain_iron`, `chain_steel`, `chain_gold`, `chain_dark` + five heroic heavy plate sets: `plate_steel` Knight's Vanguard Steel, `plate_gold` Paladin's Sacred Gilded, `plate_dark` Dreadlord Spiked Obsidian, `plate_draconic` Dragon Slayer Scale, `plate_mythril` Celestial Mythril Runed; ids `<set>_<slot>`, with sallets/greathelms/visors, fluted/winged/scale/runed cuirasses with faulds & tassets, spaulders/pauldrons, anatomical vambraces, articulated gauntlets, greaves & cuisses, and spurred sabatons; AC 28–43); ten robes (`<name>_robe`). Tilda sells them all. Migrations `20261101000001` (the morning's painted sets) and `20261101000002` (the old cloth armour) move owned items.
- **Chain Armor & Bikinis (2026-11-01, third pass)**: Re-created from high-detail references. Interlocking riveted 4-in-1 chainmail PBR sets (`chainmail`, `chain_iron`, `chain_steel`, `chain_brass`, `chain_gold`, `chain_dark`, `chain_rusted`) baked via `b8_fabrics.py` with metallic specular reflection, surface normal relief, and roughness maps. All 36 female and 32 male pieces are fully skinned 3D GLBs with shape keys and anchor attributes bound to the v3 character skeleton.
  - **Plate Mail Armor & Plate Bikinis (2026-11-01, fourth pass)**: Re-created from high-detail reference pre-renders. Features heavy metallic PBR plate materials (`plate_steel`, `plate_gold`, `plate_dark`, `plate_draconic`, `plate_mythril`, `metal_plate`) with specular metallicity, normal relief, and micro-roughness. Includes 5 heroic plate bikini sets (`plate_steel` Glorious Steel Plate, `plate_gold` Champion Gold Plate, `plate_dark` Dread Iron Spiked, `plate_draconic` Draconic Scale Plate, `plate_mythril` Mythril Runed Plate; female molded demi-cup plates, halter strapping, and leather/chain hip shields; male segmented plate war-girdles and armored subligacula) and 5 complete 7-piece heroic heavy plate armor sets (`plate_steel` Knight's Vanguard Steel, `plate_gold` Paladin's Sacred Gilded, `plate_dark` Dreadlord Spiked Obsidian, `plate_draconic` Dragon Slayer Scale, `plate_mythril` Celestial Mythril Runed; sallets/greathelms with closed visors and hidden hair, fluted heavy breastplates with faulds & tassets, articulated pauldrons, anatomical vambraces, hourglass gauntlets, greaves & cuisses with poleyns, and spurred sabatons; AC 28–43). All 45 female and 40 male pieces are fully skinned 3D GLBs bound to the v3 character skeleton with wardrobe icons in `Humans/Wardrobe/icons/`.

- **Plate, rebuilt as real plate (2026-11-01, Claude's review of the fourth pass)**: the fourth pass dressed the body in fitted cloth with a metal texture, and the five plate sets shared one mesh byte for byte. They are rebuilt in `library/pipeline/scripts/b8_plate_designs.py`: every plate is a shell fitted taut over the body and pushed out to the convex hull of its own cross-sections (a cuirass bridges the cleavage), given an inner face and a rolled rim, and **skinned rigidly** (one blend of bones for the whole plate, the average of the skin under it); articulation comes from overlapping lames, each rigid on its own (faulds, pauldron lames, finger lames, sabaton lames). Helmets are shells around the head's own distance field (`helm()`), with slits and openings cut in azimuth/elevation. Each set has its own silhouette: steel gothic and fluted (sallet, pointed sabatons), gold domed with a sun boss, wings and a winged great helm, dark keeled with saw-toothed edges, spikes, claws and a barbuta, draconic plate under overlapping scales with fins, talons and a horned visor, mythril slim with pointed edges, crescent pauldrons, inlaid lines and an open casque with a crest blade. The plate bikinis are rigid cups and plates too. Plate fabrics are tintable metals (`neutral` in `b8_fabrics.py`: luminance kept, mean set, the item colour tints it).
- **The jeweller's sets (2026-11-01, owner's rendering of ten polished pink bikinis)**: `jw_filament`, `jw_thorn`, `jw_diamond`, `jw_filigree`, `jw_celestial`, `jw_starfire`, `jw_lasso`, `jw_oceanic`, `jw_rose`, `jw_phoenix` (`b8_jewel_designs.py`; fabrics `polished` and `gloss`). Rosalind Gemcutter, behind the north-west market stall, sells a whole set (the female's top and bottom, the male's bottom) for **100 Gems** from the player's Bacon Store wallet (`BaconStore.Wallet.spend/3`, idempotent per click), not in the store. Each has a power (`BaconWorld.Powers`), carried by the bottom piece and applied in `BaconWorldWeb.GameEvents` on basic swings, kills and hits taken: Midas Ward, Thornbite, Brilliance, Silken Snare, Starlit Mind, Starfire, Long Lasso, Riptide, Bloom, Phoenix Rebirth.

- **Mail, redesigned (2026-11-01, owner: "yes, redesign the chain")**: `b8_chain_designs.py`. Mail is cut and fitted like cloth (it deforms with the skin); what stands on it (plates, rondels, splints, buckles, spikes) is rigid. Iron: a soldier's coif laced at the chin, a split hauberk over a quilted collar, belt and pouch, mail mittens, laced leather bracers, gartered chausses, turnshoes. Steel: a pointed bascinet with a mail aventail, a blue surcoat and sword belt, rondels and couters, splinted vambraces, plate-cuffed gauntlets, poleyns and shin plates, capped sabatons. Gold: a circleted coif, a white tabard with a gold sun, sun rondels, gilded spiral wraps, brass-cuffed gloves, gold splints. Dark: a veiled hood with a spiked cap, a short shirt over a lamellar skirt and a crossed harness, spiked spaulders, wraps with spikes, clawed gloves, strapped splints, fur-topped boots. The four mail bikinis are new too (iron triangles and thongs, coin-fringed brass, a steel bandeau, gilded halter with draped chains).
- **The jeweller's heels (2026-11-01, owner's rendering)**: `jw_<set>_shoes`, one per jeweller's set, 100 Gems each from Rosalind, power `swift` (Items `run_speed: 1.5`; `character-controller.ts` `runSpeed`, set each frame from the worn feet item; still under the server's speed check). Built by `b8_heels.py` on the flat-footed rest body with `heel` extras {deg, rise}: `human-factory.ts` `heelPose()` turns each foot toes-down about the world axis across it, turns the ball back so the toes lie flat, and lifts the body by `rise`; the stiletto is modelled tilted so it stands straight and just reaches the ground in that pose. The Blender previews use the same pose (`heel_pose`).
- **Gem purchases are recorded** (owner): `BaconWorld.Jeweller.buy/5` spends through `BaconStore.Wallet.spend/3` (one `spend` transaction: `game_slug` `bacon_world`, memo naming the set or heels and the character, reference `bacon_world_jewel`); the store's Purchases page (`/store/orders`) lists them under "Bought with Gems" (`Wallet.spends/2`). Tested end to end with a real wallet (`jeweller_test.exs`, `store_pages_test.exs`).

### Tests

The plugin's Elixir tests run with the hub's suite; the JavaScript tests run with
`plugins/bacon_world/assets/js/__tests__/run.sh` (121 pass on 2026-10-30). Look-checks are done in the three.js
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
| 2026-10-21 | ~~**Real recorded sounds** for grunts, landings, hits and swings (CC0 recordings), **not synthesized**.~~ Reversed 2026-11-01: synthesized sounds are fine (the owner kept the synthesized ambience). |
| 2026-10-22 | **Volume sliders**, not on/off switches, for effects, nature and music. |
| 2026-10-25 | **Sound is immersive but never loud or jarring**: several takes of everything, never the same take twice, minimum gaps, distance dulling, music that rests between tracks. ~~Real CC0 recordings, still not synthesized.~~ (reversed 2026-11-01) |
| 2026-10-22 | **No camera-smoothing option.** Remote-desktop jumps are repaired by `mouse-filter.ts`; a local mouse is untouched. |
| 2026-10-21 | **Assets are ours or CC0.** Epic's content stays Unreal-only, and no paid UAL Pro/Source files from mirrors. **No DAZ-derived meshes**: the owner's two DAZ-based female files must not be used, so the female is built on MakeHuman (owner's choice, 2026-10-21). |
| 2026-10-23 | **Asset rule widened on purpose: ours, CC0, or licensed for commercial use, credited, with the source files never redistributed.** Licensed sources (Substance .sbsar and the like) live in the gitignored shared library `C:\Bacon8\library\` with a licence table; only what we bake from them ships, and it goes on the credits page. The DAZ and Epic exclusions above still stand. |
| 2026-10-23 | **Substance materials are baked in Blender** with Adobe's Substance 3D add-on (`b8_substance.py`). The library's unverified files aren't used until their source is recorded; files that can't be used legally are deleted. |
| 2026-10-23 | **The asset pipeline lives in `C:\Bacon8\library\pipeline`** (moved out of RaysSpaceSim; not a git repository): `scripts/`, `Characters/` (the B8 skeleton and human blends), `Animations/`, `out/`. The v1 humans were deleted: their source files and the copies imported into Unreal. |
| 2026-10-23 | **The MakeHuman male look `m2` is approved as is.** Carry on with his rebuild; his animations must not show A-pose fanned fingers. |
| 2026-10-21 | The female should be **stunning**. She is editable in Blender (`library/pipeline/Characters/B8Human/B8_Female_MPFB.blend`) so the owner can sculpt her later. |
| 2026-10-23 | **No clothes in character creation.** New characters start in **cream bikini underwear**. |
| 2026-10-23 | **Underwear is equipment**: a top and a bottom, separate items, layered under clothes and armour, and removable. They are ordinary 3D gear: no content warnings around them. |
| 2026-10-23 | ~~**At least five underwear sets for sale from an NPC merchant.**~~ (superseded 2026-11-01: ten sets, below) The old clothes meshes become **cloth armour**. |
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
| 2026-10-31 | **Smash toggle outside build mode**: Smash is an in-game combat toggle on the player info bar, not a build-mode tool. All players can destroy placed objects using weapons, spells, and skills when Smash is ON. |
| 2026-10-31 | **Object HP and in-game Admin editing**: Placed objects have 10 HP by default. Admins can adjust asset HP in-game in the build catalogue. Right-click in build mode instantly shatters an object, strictly checked against placement permissions. |
| 2026-10-31 | **PvP spells and skills enabled**: Spells and skills now affect PvP-flagged players and placed objects (when Smash is ON). |
| 2026-10-31 | **Object HP regeneration**: Damaged placed objects naturally regenerate at 10% of their max HP per tick. |
| 2026-10-31 | **Object stacking and snapping**: Objects stack on top of each other in build mode, and snap both vertically (stacking) and horizontally (side-by-side) to existing objects; Alt allows freeform placement. |
| 2026-10-31 | **Slope step-down snapping and jump sound fix**: Characters moving downhill snap to terrain within a step-down threshold (0.6 m) so slopes don't flutter grounded state; jump grunts only trigger on active upward jumps (verticalSpeed > 1.0) and landing sounds require > 200 ms airtime. |
| 2026-10-31 | **Zone-wide flight altitude ceiling**: Drake mount flight height is no longer restricted to local ground elevation directly underneath; players can fly anywhere in the zone up to 100 m above the highest point in that zone (`hi: 672.0 m` on Crater Lake, ceiling = 772 m), or 100 m above high structures. |
| 2026-10-31 | **Combat & Building Performance & Stability Fixes**: Cached asset rules and HPs in `:persistent_term` and active placements in `:bacon_world_placements_cache` ETS; eliminated N-queries on `Building.list` and attacks; scoped AoE/cone smash checks to bounded SQL bounding boxes; prevented re-connecting the same character from triggering "account is already logged in"; fixed `TypeError` in `buildExit` enabling clean exit via '`' or close button. |
| 2026-10-31 | **Persistent Game Asset Service Worker**: Added `/sw-game.js` caching `/models/**`, `/audio/world/**`, and `/fonts/**` in browser `CacheStorage` with background auto-updating (Stale-While-Revalidate), eliminating asset re-downloads on page reloads. |
| 2026-10-31 | **Slash Commands & Zone Warping**: Added `/zone` (warps to default starting location of the current zone) and `/zone x,y,z` (warps to specified coordinates). Added `/loc` / `/pos` / `/where` (coordinates and heading), `/stuck` (safe warp to zone entrance), `/die` / `/suicide` / `/kill` (instantly slays character with shatter), `/roll [max]` (zone-wide dice roll), `/shout <msg>` / `/yell` (zone-wide broadcast), `/time` (server UTC & day/night status), `/weather [type]` (view/set weather), `/help` (command reference), and emotes (`/dance`, `/wave`, `/bow`, `/cheer`, `/clap`, `/sit`, `/point`). |
| 2026-10-31 | **Abyss / Void Death**: Falling below the world into nothingness (Y < -120 m or >25 m below terrain bottom) triggers a lethal kill event ("You fell into the abyss!"), shatters the character into physics debris, and respawns them at the safe zone entrance. |
| 2026-10-31 | **Combat Skills & Spin Attack PvP Hits**: Fixed Spin Attack and martial skills failing to damage other players in PvP. Fixed `spin_reach` calculation (previously evaluating to only 0.6 m instead of weapon reach + 4.2 m 360-degree radius), preserved target selection for `"none"`/directional skills, added `Melee.in_arc?` player detection for untargeted strikes/cleaves/dashes, and included `pvp_hits` in `cast_result`. |
| 2026-11-01 | ~~**Ten underwear sets replace all the old ones**: a plain linen starter and nine more sold by Tilda at **6 copper a piece** (top and bottom are separate items), each with its own cut and pattern (`library/pipeline/scripts/b8_underwear.py`); the male wears each set's bottom in a cut of his own. Retired sets owned by players move to the nearest new one (games migration `20261101000000`).~~ (superseded the same day by the garment parts, below) |
| 2026-11-01 | **No painted muscles or blemishes on the skin** (owner: "a TERRIBLE look"), and **smoother bodies**: the body sculpt below the head is gentler and smoothed, every body slider's shape is smoothed so maxed sliders don't go blocky, and the male's upper chest has more vertices (`b8_anatomy.py` `B8_SKIN_PLAIN`, `B8_SCULPT_BODY`; `body_v3.py` `smooth_keys`). |
| 2026-11-01 | **Synthesized sounds are allowed** (the 2026-10-21 and 2026-10-25 "not synthesized" rules are reversed) and **storm lightning stays lethal**. |
| 2026-11-01 | **Skill points can be taken back** (owner): right-click a learned node to unlearn it and get its point back; the footer's Reset (clicked twice) unlearns everything but the start. A node others hang from comes off only after them, so the rest stays joined to the start (`Skills.unlearn/2`, `Skills.reset/1`, `SkillTree.connected?/2`; events `skill_unlearn`, `skill_reset`). |
| 2026-11-01 | **v3 humans** (owner: "a v3 that is not embarrassing", denser breasts and face, better hair): see "The v3 humans" in §2. |
| 2026-11-01 | ~~Ten texture-painted underwear sets (`b8_underwear.py`)~~ (reversed the same day, owner: "I want photo-realistic underwear... STOP USING THE OLD SHIT DESIGNS"): **every garment is a real 3D part in photographed fabrics**: ten new underwear sets (6c each, a cotton starter), **ten full sets of cloth armour** (head, hands, arms, wrists, chest, legs, feet) and **ten robes**, all new designs. See "Garment parts" in §2. |
| 2026-11-01 | **Plate Mail Armor & Plate Bikinis**: Full suite of 3D heroic heavy plate armor and plate bikinis: 5 plate bikini sets (`plate_steel`, `plate_gold`, `plate_dark`, `plate_draconic`, `plate_mythril`) with male plate war-girdles/subligacula, and 5 complete 7-piece heroic plate armor sets covering all 7 equipment slots (`head`, `chest`, `arms`, `wrist`, `hands`, `legs`, `feet`) built through Blender 5.1 with PBR metallic plate materials (`plate_steel`, `plate_gold`, `plate_dark`, `plate_draconic`, `plate_mythril`, `metal_plate`). |
| 2026-11-01 | **Chain Armor & Chain Bikinis**: Full suite of 3D chainmail gear: 4 chain bikini sets (`chain_iron`, `chain_brass`, `chain_steel`, `chain_gold`) with male subligaculum/trunks, and 4 complete 7-piece chain armor sets (`chain_iron`, `chain_steel`, `chain_gold`, `chain_dark`) covering all 7 equipment slots (head, chest, arms, wrist, hands, legs, feet) built through Blender 5.1 with PBR metallic chain materials (`chainmail`, `chain_iron`, `chain_steel`, `chain_brass`, `chain_gold`, `chain_dark`, `chain_rusted`). |
| 2026-11-01 | **Plate is rigid plate** (owner chose the rebuild): Gemini's fitted-cloth plate (one mesh for five sets) is replaced by forged, rigidly skinned shells, every set its own design. See "Plate, rebuilt" in §2. |
| 2026-11-01 | **The jeweller's sets are sold in-game for Gems, not in the Bacon Store** (owner: "make them available to purchase from a merchant in-game for gems"): 100 Gems a set, each with its own power. |
| 2026-11-01 | **Retired leftovers deleted** (owner): the painted Wardrobe textures and the 28 icons of retired items are gone from the models volume; the Robin Hood Hat stays. |
| 2026-10-31 | **Rain Effect Optimization & Visual Refinement**: Overhauled weather rain and clouds for high performance. Reduced particle count from 2,000 to 360 drops within an 18 m local camera cylinder (eliminating distant white needles across mountains and reducing CPU/bus transfer by 82%), softened streak color and opacity (`0x6e889e`, 0.08–0.22 opacity), and bypassed the cloud plane during clear weather with 2-octave shader evaluation to eliminate GPU fillrate bottlenecks. |

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
- **Underwear sets** (2026-11-01): Linen (the starter), Ranger, Twist, Keyhole, Corset, Rose Lace, Crossfront,
  Asymmetric, Dragonscale and Runic, 6 copper a piece at Tilda's; cuts and patterns in `b8_underwear.py`, icons by
  `uw_icons.py`.
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
- **Effect lights are pooled (four, `light-pool.ts`, shared by spells and the drakes' breath).** A fifth effect at
  once goes without a light. New effects must take and give lights from `LightPool` and use shared materials.
  Never add or remove lights, and never dispose shared materials: either recompiles every lit material and freezes
  the game for seconds. Give a new material kind a stand-in in `warmup.ts`. The shader watchdog's console line says
  when one was missed.
- **Still possible first-use waits**: the first time a model is *downloaded* (a drake is 7 MB, a body 2-3 MB),
  that is a network wait, not a shader one. Preloading owned mounts' models and the commonest creatures at world
  entry would hide it.

**Smashing: how far it can go.** Today's bits are cosmetic: each client cuts the piece's own mesh on a grid and
throws the shells about. Possible next levels, cheapest first:

1. *Pre-fractured pieces*: cut each kind of piece once in Blender (Cell Fracture, Voronoi) in the asset pipeline,
   with inside faces and an inside material, saved as `<asset>_frac.glb`. `smash-fx.ts` would use those chunks when
   present and fall back to the grid cut.
2. *Real physics for the bits*: Rapier (WASM) or cannon-es on the client, so bits tumble, stack and collide with
   the ground, the walls and each other. Still client-only and cosmetic.
3. *Damage that lasts*: placements get HP on the server (by material: wood, stone), hits are server events (players,
   spells, a dragon's breath), and pieces show cracked or damaged states before they break. Structural rules (a roof
   falls when its walls go) would come after that. Only the destroyed state need ever be authoritative; the debris
   can stay client-side at every level.

The hit sounds borrow `bone_break` and `bone_collapse`; wood and stone breaking sounds are wanted.

**Sound.** Sounds still wanted (recorded or synthesized) for: surf, a cast, a splash, a reel, the Kraken's water (a big splash,
a whirlpool, a wet slap, ink), a bow's twang, an arrow's thud, rat squeaks, goblin chatter and orc grunts. The
placeholders reuse existing recordings (`sw_drip`, `loot`, the dragon's roars pitched down).

**Skills and fishing.** New *kinds* of ability need code (an entry in `abilities.ex`, its effect in `skill_events.ex`
and `spell-fx.ts`); placing existing ones on the tree is done in `/admin/bacon_world/skills`. A new spell school
needs a `cast_loop_<school>.mp3` and a `CAST_SCHOOL` entry. Ability icons are emoji. Catching is flat (80% on a
timely reel): no fishing skill, bait or rod tiers, and fish can't be cooked yet.

**Items and economy.** Armour beyond cloth; more merchants. Existing characters lose their old creator outfit and
get the linen set and 1 gold at their next login. Throw Stone's spell rows stay in the games DB (retired in code);
deleting them needs the owner's OK.

**Review of the 2026-10-30/31 changes (done 2026-11-01)**

- Fixed: the service worker and the ambience files never shipped (Dockerfile), the 404 storm, `/zone x,y,z` and
  `/weather` open to every player (now GMs and admins; `/stuck` for all), smash able to delete anything from anywhere,
  every smash hit re-reading the zone's placements from Postgres (`Building.cached/1`), the ETS caches owned by
  whichever player's process made them (now `BuildingRegen`), `view/2` crashing when the table was missing, the
  damaged-but-not-broken hit result never matching its callers, the rule caches leaking between tests, and five
  compile warnings (the commits never passed `--warnings-as-errors`).
- Owner, 2026-11-01: **lethal lightning stays** (a storm kills anyone outdoors in a 3.5 m ring every 14-25 s, decided by
  each client's own clock) and **the synthesized ambience stays**. Still open: `account_online_elsewhere?`
  now lets the same character in from a second tab (meant for reloads); the abyss check trusts the client's `y` (it can
  only kill itself).

**Characters (art)**

- v3 (2026-11-01) needs a look in the game: the hair is new geometry (cards up to ~70k vertices for braids; the
  female body ~57k). Things to watch: hair clipping the shoulders in animation (hair below the head is weighted to
  neck_01/spine_03), the scalp decal z-fighting at distance, and the body GLB size (~4x the old one; the service worker
  keeps it after the first load). The face of the MakeHuman base is unchanged; the six sliders sculpt it.

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

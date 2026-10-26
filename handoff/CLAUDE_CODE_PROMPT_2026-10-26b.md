# Claude Code prompt, 2026-10-26b: two-handed guards, the owner's bug list, the sea and fishing

Delivered by the cloud session, uncommitted. Read `plugins/bacon_world/BACON_WORLD.md` §2 (the
"2026-10-26 (b)" entry) and BACON8.md "On 2026-10-26" (the StaticReload item and invariant 18).

The owner reported: the male holds two-handers badly (spear elbow broken; greatsword, maul and axe
held inside the waist; the staff through his legs); a screenshot opens the Esc menu; Esc doesn't
clear the target and a respawned target is re-targeted; a hard refresh is needed after deploys;
skill points need a refresh after levelling; the skill window drags in jumps; spells freeze the
game for 2-5 s when they land; looting should skip the window for empty corpses and G should take
everything. And he asked for an ocean around the land, a fishing lake near town, and fishing.

**Another session's work may be in the tree.** Commit only the files below.

```
lib/bacon8_web/static_reload.ex                         new: reload a page whose scripts are from an earlier deploy
lib/bacon8_web.ex                                       on_mount Bacon8Web.StaticReload in :live_view
lib/bacon8_web/endpoint.ex                              "/" Plug.Static: unversioned files cached an hour, not a year
BACON8.md
plugins/bacon_world/BACON_WORLD.md
plugins/bacon_world/README.md
plugins/bacon_world/assets/js/human-factory.ts          TWO_HAND_GUARDS, ik2, twoHandGuard (incl. FishingPole)
plugins/bacon_world/assets/js/anim-driver.ts            armSets() reports the two-hander's set
plugins/bacon_world/assets/js/character-controller.ts   a lost pointer lock is Esc only if focus wasn't taken
plugins/bacon_world/assets/js/controls-math.ts          LOCK_LOSS_SETTLE_MS, lockLossWasEsc
plugins/bacon_world/assets/js/world-character-ui-scene.ts  Esc clears target first; R fishes; fish events; island clamp
plugins/bacon_world/assets/js/game-world.ts             target dropped on gone/respawn; skills refresh on level-up; loot/G; water wiring
plugins/bacon_world/assets/js/skills-world.ts           refreshSkills
plugins/bacon_world/assets/js/skills-ui.ts              title-bar drag only, compositing hints
plugins/bacon_world/assets/js/spell-fx.ts               pooled lights, shared materials (the freeze)
plugins/bacon_world/assets/js/items.ts                  icon_url; procedural FishingPole
plugins/bacon_world/assets/js/world-dressing.ts         ellipse colliders; grass disc 141 m
plugins/bacon_world/assets/js/water.ts                  new: water rules, sea/beach/lake views, bobber and line
plugins/bacon_world/assets/js/fishing-world.ts          new: the FishingWorld mixin
plugins/bacon_world/assets/js/__tests__/escape.test.ts  new (4)
plugins/bacon_world/assets/js/__tests__/water.test.ts   new (4)
plugins/bacon_world/lib/bacon_world/water.ex            new: BaconWorld.Water
plugins/bacon_world/lib/bacon_world/items.ex            fishing_pole, ten catches, icon_url
plugins/bacon_world/lib/bacon_world/merchants.ex        Old Bram, Angler
plugins/bacon_world/lib/bacon_world_web/fishing_events.ex  new: fish_cast / fish_reel / fish_stop
plugins/bacon_world/lib/bacon_world_web/play_live.ex    fishing events and timers; no moving out to sea
plugins/bacon_world/lib/bacon_world_web/game_events.ex  fetch_mobs sends the water layout
plugins/bacon_world/test/bacon_world/fishing_test.exs   new (14)
plugins/bacon_world/priv/static/icons/                  new: fishing_pole.png and the ten catches (128 px)
handoff/CLAUDE_CODE_PROMPT_2026-10-26b.md
```

`priv/static/site.webmanifest` may show as modified: its content equals HEAD (stat only). Leave it out.
A stale lock the cloud shell could not delete is in `.git/` (`stale-index-lock-claude-2026-10-26c`);
it is harmless, delete it. The icon script, `library/pipeline/scripts/fishing_icons.py`, is not in git.

**Second reader wanted on** `static_reload.ex` and the `endpoint.ex` cache change (they touch every
page), and on `validate_on_island/3` in `play_live.ex` (it may refuse moves).

Checked by the cloud session:
- `mix compile --warnings-as-errors`; **676 Elixir tests, 0 failures**.
- **80 JS tests** (bun + `node --test`); `tsc` over the changed files: no new errors (the old implicit-any
  ones remain).
- The guard poses in the three.js harness, male and female, front, side and three-quarter: no clipping.
- The water in the village harness: found and fixed three bugs (beach faces pointed down so it was
  culled, the pond's water lost the depth test to its bank, the foam sank under the swell). Rendered
  again after the fix: the beach, the pond's water, lily pads, reeds and the cast line all show. The
  foam ring was then moved 2.6 m inland to where the swell meets the sand (not re-rendered).

Not checked: anything in a real browser against the server (fishing end to end, StaticReload in a
release, the screenshot fix with a real Snipping Tool, the frame rate when spells land). Build and test
in Docker as usual, then play: hold each two-hander, take a screenshot, Esc with a target, level up
with the skill window open, drag it, cast Recall, loot an empty corpse and press G on a full one, buy
a pole from Bram at the Millpond and fish there and from the beach, try to walk into the sea.
No deploy until the owner says. No model sync is needed (icons ship with the plugin).

Existing characters standing beyond 151.5 m (unlikely) can still walk back in; only moves outward are refused.

Commit message (suggested):

```
Bacon World: two-handed guard poses, the sea and the Millpond with fishing, and the owner's bug list

Two-handers blend into guard poses (body-relative, two-bone IK) while not swinging. The island ends at
150 m in a sea; the Millpond lies north-west of the square with Old Bram selling fishing poles; R casts
and reels, bites timed by the server, catches by water. A screenshot no longer opens the menu; Esc
clears the target first; a respawned target is dropped; skill points update on level-up; the skill
window drags by its title bar; spell lights are pooled (adding lights recompiled every shader: the
freeze); G loots everything, empty corpses open nothing. Hub: open pages reload after a deploy
(Bacon8Web.StaticReload) and unversioned static files are cached an hour.
```

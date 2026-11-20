# Bringing the hub and every game up to date

On the development PC, in `C:\Bacon8`. Do the steps in order: the models first, then each game.
Nothing here deploys or touches production by itself. Steps marked **(owner)** happen only when the owner says.
Each game's notebook (`BACON8.md`, `BACON_WORLD.md`, `TEARS_OF_BABYLON.md`, `RAYSSPACESIM.md`, `CITY_BUILDER.md`)
says what is waiting on these steps. Last revised 2026-11-19.

## 0. Commit what is there

There are seven repositories. Run `git status` in each one before a build changes anything:

| Repository | Folder |
|---|---|
| hub | `C:\Bacon8` |
| art pipeline | `C:\Bacon8\art\pipeline` |
| Bacon World | `C:\Bacon8\plugins\bacon_world` |
| Tears of Babylon | `C:\Bacon8\plugins\tears_of_babylon` (Git LFS) |
| RaysSpaceSim (scripts, k8s) | `C:\Bacon8\plugins\rays_space_sim` |
| RaysSpaceSim (Unreal project) | `C:\Bacon8\plugins\rays_space_sim\unreal` (Git LFS) |
| City Builder (the plugin `city_planner`) | `C:\Bacon8\plugins\city_planner` |

The owner commits. The art pipeline is the one that matters most: it has no commit since 2026-11-14, and `hair\`
and `gltf\face_*.mjs` have never been committed.

## 1. The models (art pipeline → web → every game)

```
cd C:\Bacon8\art\pipeline
build.cmd --check      rem lists what is out of step; changes nothing
build.cmd
```

The build repairs the web clips and adds the shared eyes and the face keys where they are missing. It then converts
the web models three ways: for Godot (`art\build\godot`), for Unreal (`art\build\unreal`, PNG textures) and for Unity
(`art\build\unity`, without vertex colours or region ids). Changed files are copied into Tears of Babylon
(`godot\art\characters\shared\...`), RaysSpaceSim (`unreal\SourceAssets\Bacon8`) and City Builder
(`unity\Assets\StreamingAssets\B8`). It ends with a list of problems, and an empty list is what you want. If
`gltf\node_modules` is missing, run `npm ci` in `gltf` first. New hair styles are installed before the build
(art pipeline README, "Hair, where things stand").

## 2. The hub and Bacon World (the web)

- Tests, in throwaway Docker containers (nothing is installed on the PC): `C:\Bacon8\tools\win\hubtests.cmd`. Both
  `tmp\build_test.log` and `tmp\ex_test.log` must end with `EXIT 0`. The full suite is in BACON8.md §14.
- Bacon World's browser checks: `C:\Bacon8\tools\win\checks.cmd`. This runs the three.js harness in `plugins\bacon_world\tools\harness` and then Tears
  of Babylon's tests. Output: `tmp\js_test.log`.
- Bacon World's TypeScript unit tests are in `plugins\bacon_world\assets\js\__tests__`. Run them with Node's type
  stripping (`node --experimental-strip-types --test ...`).
- **(owner)** Deploy: `scripts/deploy-prod.sh`, which backs up both databases first.
- **(owner)** Models to the server: `scripts/sync-models-to-k8s.sh`. Never run it without the owner's word.

## 3. Tears of Babylon (Godot 4.7.2)

- Open `plugins\tears_of_babylon\godot` in Godot 4.7.2. It reimports the changed models, which takes a few minutes
  the first time after a build. To do the same headless, with the tests: `C:\Bacon8\tools\win\tob_check.cmd`.
  `tmp\tob_check.log` must end with `DONE 0`.
- Check by eye in the creator:
  - every body, including all 38 of the v1 female's hair styles;
  - the face and eye sliders;
  - with the eyeball button on, orbit the camera: the head should turn as far to the left as to the right.
- `WASAPI ... GetBufferSize` / `output_device` errors in the Output panel come from Windows' audio driver and are
  harmless.

## 4. RaysSpaceSim (Unreal)

1. Build the C++ first: close the editor and run `C:\Bacon8\tools\win\rss_full_build.cmd`. It waits for the editor to
   close. Status: `tmp\RSS_BUILD_STATUS.txt`. Log: `tmp\rss_full_build.log`. (Fixes go in C++, not in Blueprints.)
2. Import one body per editor session, because the editor runs out of GPU memory otherwise. Run each line from the
   Output Log's Python prompt, wait for `[import_b8] B8DONE`, then close the editor before the next:
   - `import import_b8; import_b8.main(["Female_v2"], parts=("body",))`
   - `import import_b8; import_b8.main(["Female"], parts=("body", "hair"))`
   - `import import_b8; import_b8.main(["Male"], parts=("body", "hair"))`
   - Still owed from 2026-11-13: `import import_b8; import_b8.main(["Male"], parts=("garments",))`
3. Hair imports stall for 12-25 minutes while shader permutations compile. That is normal; leave the editor alone.
4. Never start an import from a Slate tick callback. Never leave a UWorld bound in MCP Python and then load a level.
5. Check by eye in the creator: faces, hair, and the head turning equally to both sides.

## 5. City Builder (Unity 6.6)

- In Unity Hub, open `plugins\city_planner\unity` with 6000.6.9f1 (`ProjectSettings\ProjectVersion.txt`). It should
  open without Safe Mode and with an empty Console.
- Press Play and open the character creator. Check all three bodies, with hair and sliders, and make sure nothing is
  torn apart. If anything is wrong, put a screenshot and the Console text in `CITY_BUILDER.md`.
- The scanner's tests: `core-tests` (CITY_BUILDER.md §7).

## 6. Finish

- Write what was seen into each notebook, then commit each repository **(owner)**.
- Clearing out: `C:\Bacon8\tools\win\cleanup.cmd` **(owner)** empties `C:\Bacon8\_to_delete`. Read
  `_to_delete\<date>\MANIFEST.txt` first, because the deletion is permanent. The same script also deletes
  RaysSpaceSim's staged builds and runs `docker image prune -a` and `docker builder prune -a`, which remove every
  Docker image no container is using.

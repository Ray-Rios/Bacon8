# tools\win: the Windows launchers

Moved here from `tmp\` on 2026-11-19. Everything in this folder is a tool: kept, tracked, safe to rely on. `tmp\` is
now scratch only: logs, status files and `*_args.txt` (per-run input) stay there. Each launcher begins with
`call "%~dp0paths.cmd"`, which sets `GODOT`, `UE`, `UNITY` and `BLENDER` once. Change a program's location in
`paths.cmd` only. Godot still lives in `Downloads\`; moving it to `C:\Tools\Godot\4.7.2\` is the owner's call.

Paths in these files are absolute `C:\Bacon8\...`. Docker runs are throwaway containers; nothing is installed on the PC.
No secrets here (the test database's `POSTGRES_PASSWORD=postgres` is a throwaway).

## Launchers (log or output in `tmp\`)

| Launcher | What it runs | Log / output |
|---|---|---|
| `hubtests.cmd` | `build_test.cmd` then `ex_test.cmd` | `build_test.log`, `ex_test.log` (both end `EXIT 0`); `hubtests.done` |
| `build_test.cmd` | Hub `mix test` (build/other suites) in Docker with Postgres | `build_test.log` |
| `ex_test.cmd` | Bacon World's Elixir tests in Docker with Postgres | `ex_test.log` |
| `checks.cmd` | three.js harness (`plugins\bacon_world\tools\harness`), then `tob_check.cmd` | `js_test.log`, `JOB_STATUS.txt` |
| `wh_build.cmd` | bundles the harness (`plugins\bacon_world\tools\harness\build.mjs`) | `wh_build.log` |
| `cc_js.cmd [prefix]` | Bacon World's TypeScript tests (esbuild + `node --test`) in Docker | `cc_js.log` |
| `cc_mix.cmd` | Mix compile + tests in Docker | `cc_mix.log` |
| `cc_wasm.cmd` (+ `wasm_build.sh`) | builds `box3d.wasm` in the wasi-sdk image | `cc_wasm.log`, `wasm_out\` |
| `tob_check.cmd` | Godot headless import + `tests/run_tests.gd`; ends `DONE 0` when clean | `tob_check.log` |
| `gd_check.cmd` | Godot `--check-only` on a list of scripts | `gd_check.log` |
| `hair_shots.cmd` | Godot hair renders; reads `hair_shots_args.txt` (`<body> <v1\|v2> <Style,Style>`) | `hair_shots\`, `hair_shots.log` |
| `mouth_shots.cmd` | Godot mouth renders; reads `mouth_shots_args.txt` | `ms3\`, `mouth_shots.log` |
| `godot_chest.cmd` | Godot chest renders; optional `godot_chest_mode.txt` | `godot_chest\`, `godot_chest.log` |
| `godot_jiggle.cmd` | Godot jiggle renders | `godot_jiggle\`, `godot_jiggle.log` |
| `hairprev.cmd` | Blender hair previews (`art\pipeline\hair\preview.py`, `tmp\hairprev\jobs.json`) | `hairprev\preview.log` |
| `stance_shots.cmd` (+ `.py`) | Blender stance renders | `stance_shots.log`, `JOB_STATUS.txt` |
| `rss_full_build.cmd` | RaysSpaceSim `RSSEditor` build; waits for the editor to close; ends `EXIT 0` | `rss_full_build.log`, `RSS_BUILD_STATUS.txt` |
| `rss_compile.cmd`, `rss_build_compile.cmd` | per-file C++ compile checks (`-SingleFile`, editor can stay open) | `rss_compile.log`, `rss_build_compile.log` |
| `rss_rebuild.bat` | rebuilds after the editor closes, then reopens it (stashes source on failure) | `rss_build.log` |
| `unreal_names.cmd` | renames Unreal morph names in the Unreal copies | `unreal_names.log` |
| `cleanup.cmd` | empties `_to_delete`, RaysSpaceSim staged builds, prunes ALL unused Docker images | `cleanup.log` |
| `cleanup_space.cmd`, `disk_scan.cmd` (+ `.py`) | disk space cleanup / report | `cleanup_space.log`, `disk_scan.log` |
| `admin_space.cmd` | run as administrator: shrinks Docker's disk, sets the page file | console |
| `gtest.cmd` | **stale**: the 11-12 garment test; its output folder in `art\work\daz_female` is gone | `gtest.log` |

## Scheduled tasks (Task Scheduler, all `conhost.exe --headless cmd.exe /c <launcher>`)

These point at `tools\win\`: `B8_ccjs`, `B8_checks`, `B8_cleanup`, `B8_cleanup_space`, `B8_disk_scan`, `B8_ex_test`,
`B8_gd_check`, `B8_godot_chest`, `B8_godot_jiggle`, `B8_gtest`, `B8_hairprev`, `B8_hairshots`, `B8_hubtests`,
`B8_rss_build_compile`, `B8_rss_compile`, `B8_rss_full_build`, `B8_stance_shots`, `B8_tob_check`, `B8_wh_build`
(each runs the launcher of the same name; `B8_ccjs` = `cc_js.cmd`, `B8_hairshots` = `hair_shots.cmd`).
`B8_checks` and `B8_hairshots` are the ones in use. Run one with `schtasks /run /tn B8_hubtests`.
To re-point: `schtasks /change /tn "\B8_x" /tr "conhost.exe --headless cmd.exe /c C:\Bacon8\tools\win\x.cmd"`.
Other tasks: "Bacon8 backup" (03:10, `scripts\backup.ps1 -Destination D:\Backups`).

**Dangling (their one-off launchers went to `_to_delete\2026-11-19\tmp` on 2026-11-19):** `B8V2Uw`, `B8_after_v1`,
`B8_all_garments`, `B8_build_run`, `B8_chest_test`, `B8_commit_pipe`, `B8_crease`, `B8_disk_full`, `B8_disk_scan2`,
`B8_fast_check`, `B8_godot_jiggle_trace`, `B8_g_then_b`, `B8_paragon_out`, `B8_ready_blend`, `B8_tw_test`,
`B8_v1_garments`, `B8_v2_fast`, `B8_v2_rebuild`. Unregister them: `schtasks /delete /tn "\B8_x" /f`.

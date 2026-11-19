@echo off
call "%~dp0paths.cmd"
set G=%GODOT%
set LOG=C:\Bacon8\tmp\gd_check.log
cd /d C:\Bacon8\plugins\tears_of_babylon\godot
echo start %time% > %LOG%
for %%f in (scripts/fx/ragdoll.gd scripts/ai/creature.gd scripts/world/build_rules.gd scripts/world/build_mode.gd scripts/actors/third_person_player.gd scripts/combat/health.gd) do (
  echo == %%f >> %LOG%
  %G% --headless --path . --check-only --script res://%%f >> %LOG% 2>&1
)
echo DONE %time% >> %LOG%

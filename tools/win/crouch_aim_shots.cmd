@echo off
call "%~dp0paths.cmd"
set OUT=C:\Bacon8\tmp\crouch_aim_shots
if not exist %OUT% mkdir %OUT%
cd /d C:\Bacon8\plugins\tears_of_babylon\godot
"%GODOT%" --path . --script res://tools/crouch_aim_shots.gd -- %OUT% > C:\Bacon8\tmp\crouch_aim_shots.log 2>&1
echo DONE %errorlevel% >> C:\Bacon8\tmp\crouch_aim_shots.log

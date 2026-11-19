@echo off
call "%~dp0paths.cmd"
set G=%GODOT%
cd /d C:\Bacon8\plugins\tears_of_babylon\godot
set MODE=
if exist C:\Bacon8\tmp\godot_chest_mode.txt set /p MODE=<C:\Bacon8\tmp\godot_chest_mode.txt
%G% --headless --path . --import > C:\Bacon8\tmp\godot_chest.log 2>&1
%G% --path . --script res://tools/chest_shots.gd -- C:/Bacon8/tmp/godot_chest -1 %MODE% >> C:\Bacon8\tmp\godot_chest.log 2>&1
echo EXIT %errorlevel% >> C:\Bacon8\tmp\godot_chest.log

@echo off
call "%~dp0paths.cmd"
set G=%GODOT%
set LOG=C:\Bacon8\tmp\godot_jiggle.log
cd /d C:\Bacon8\plugins\tears_of_babylon\godot
echo start %time% > %LOG%
%G% --path . --script res://tools/jiggle_shots.gd -- C:/Bacon8/tmp/godot_jiggle >> %LOG% 2>&1
echo EXIT %errorlevel% %time% >> %LOG%

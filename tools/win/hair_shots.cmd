@echo off
call "%~dp0paths.cmd"
set G=%GODOT%
cd /d C:\Bacon8\plugins\tears_of_babylon\godot
set /p A=<C:\Bacon8\tmp\hair_shots_args.txt
%G% --headless --path . --import > C:\Bacon8\tmp\hair_shots.log 2>&1
%G% --path . --script res://tools/hair_shots.gd -- C:/Bacon8/tmp/hair_shots %A% >> C:\Bacon8\tmp\hair_shots.log 2>&1
echo EXIT %errorlevel% >> C:\Bacon8\tmp\hair_shots.log

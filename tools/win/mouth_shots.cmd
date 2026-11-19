@echo off
call "%~dp0paths.cmd"
set G=%GODOT%
cd /d C:\Bacon8\plugins\tears_of_babylon\godot
set /p A=<C:\Bacon8\tmp\mouth_shots_args.txt
echo start %time% > C:\Bacon8\tmp\mouth_shots.log
%G% --headless --path . --import >> C:\Bacon8\tmp\mouth_shots.log 2>&1
echo == shots %time% >> C:\Bacon8\tmp\mouth_shots.log
%G% --path . --script res://tools/mouth_shots.gd -- C:/Bacon8/tmp/ms3 %A% >> C:\Bacon8\tmp\mouth_shots.log 2>&1
echo DONE %errorlevel% %time% >> C:\Bacon8\tmp\mouth_shots.log

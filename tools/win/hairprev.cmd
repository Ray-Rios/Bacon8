@echo off
call "%~dp0paths.cmd"
"%BLENDER%" -b --factory-startup -P C:\Bacon8\art\pipeline\hair\preview.py -- C:\Bacon8\tmp\hairprev\jobs.json > C:\Bacon8\tmp\hairprev\preview.log 2>&1
echo DONE %errorlevel% >> C:\Bacon8\tmp\hairprev\preview.log

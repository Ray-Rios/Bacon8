@echo off
call "%~dp0paths.cmd"
cd /d C:\Bacon8\tmp\wh
node build.mjs > C:\Bacon8\tmp\wh_build.log 2>&1

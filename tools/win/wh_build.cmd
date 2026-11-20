@echo off
call "%~dp0paths.cmd"
cd /d C:\Bacon8\plugins\bacon_world\tools\harness
node build.mjs > C:\Bacon8\plugins\bacon_world\tools\harness_build.log 2>&1

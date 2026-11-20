@echo off
call "%~dp0paths.cmd"
echo Checks: RUNNING %date% %time% > C:\Bacon8\tmp\JOB_STATUS.txt
cd /d C:\Bacon8\plugins\bacon_world\tools\harness
node build.mjs > C:\Bacon8\tmp\js_test.log 2>&1
node tests.mjs appearance wardrobe two-hand escape >> C:\Bacon8\tmp\js_test.log 2>&1
echo EXIT %errorlevel% >> C:\Bacon8\tmp\js_test.log
call %~dp0tob_check.cmd
echo Checks: DONE %date% %time% > C:\Bacon8\tmp\JOB_STATUS.txt

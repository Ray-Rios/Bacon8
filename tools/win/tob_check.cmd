@echo off
call "%~dp0paths.cmd"
set G=%GODOT%
set LOG=C:\Bacon8\tmp\tob_check.log
cd /d C:\Bacon8\plugins\tears_of_babylon\godot
echo start %time% > %LOG%
%G% --headless --path . --import >> %LOG% 2>&1
echo == tests %time% >> %LOG%
%G% --headless --path . --script res://tests/run_tests.gd >> %LOG% 2>&1
echo DONE %errorlevel% %time% >> %LOG%

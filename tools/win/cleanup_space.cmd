@echo off
call "%~dp0paths.cmd"
python %~dp0cleanup_space.py > C:\Bacon8\tmp\cleanup_space.log 2>&1
echo Cleanup: DONE %date% %time%>> C:\Bacon8\tmp\JOB_STATUS.txt

@echo off
call "%~dp0paths.cmd"
python %~dp0disk_scan.py > C:\Bacon8\tmp\disk_scan.log 2>&1

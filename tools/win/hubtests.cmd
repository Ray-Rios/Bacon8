@echo off
call "%~dp0paths.cmd"
call %~dp0build_test.cmd
call %~dp0ex_test.cmd
echo HUBTESTS DONE > C:\Bacon8\tmp\hubtests.done

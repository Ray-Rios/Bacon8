@echo off
call "%~dp0paths.cmd"
echo Stance shots: RUNNING %date% %time%>> C:\Bacon8\tmp\JOB_STATUS.txt
"%BLENDER%" -b --factory-startup -P %~dp0stance_shots.py -- C:\Bacon8\tmp\stance_shots > C:\Bacon8\tmp\stance_shots.log 2>&1
echo Stance shots: DONE %date% %time%>> C:\Bacon8\tmp\JOB_STATUS.txt

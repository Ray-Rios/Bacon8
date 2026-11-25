@echo off
call "%~dp0paths.cmd"
set LOG=C:\Bacon8\tmp\cleanup.log
set ST=C:\Bacon8\tmp\JOB_STATUS.txt
echo Cleanup: RUNNING %time% > %ST%
echo start %date% %time% > %LOG%
set U=C:\Bacon8\plugins\rays_space_sim\unreal
rem (2026-11-22, the owner) not Intermediate\Build\Linux any more: it holds the dedicated server's compiled engine, and
rem removing it made the next deploy-game.sh recompile the server from scratch, about two hours
for %%d in ("%U%\Saved\StagedBuilds" "%U%\Saved\ClientBuild" "%U%\Saved\ServerBuild" "C:\Bacon8\tmp\tob_test" "C:\Bacon8\plugins\bacon_world\tools\harness\override_off" "C:\Bacon8\_to_delete") do (
  echo removing %%d >> %LOG%
  rmdir /s /q %%d >> %LOG% 2>&1
)
echo == docker >> %LOG%
docker image prune -a -f >> %LOG% 2>&1
docker builder prune -a -f >> %LOG% 2>&1
echo == the hourly VS installer task >> %LOG%
schtasks /query /fo LIST | findstr /i "TaskName.*VisualStudio" >> %LOG% 2>&1
python -c "import shutil;print('free GB',round(shutil.disk_usage('C:\\\\').free/1e9,1))" >> %LOG% 2>&1
echo ALLDONE %time% >> %LOG%
echo Cleanup: DONE %time% > %ST%

@echo off
call "%~dp0paths.cmd"
set LOG=C:\Bacon8\tmp\cleanup.log
set ST=C:\Bacon8\tmp\JOB_STATUS.txt
echo Cleanup: RUNNING %time% > %ST%
echo start %date% %time% > %LOG%
set U=C:\Bacon8\plugins\rays_space_sim\unreal
for %%d in ("%U%\Saved\StagedBuilds" "%U%\Saved\ClientBuild" "%U%\Saved\ServerBuild" "%U%\Intermediate\Build\Linux" "C:\Bacon8\tmp\tob_test" "C:\Bacon8\tmp\wh\override_off" "C:\Bacon8\_to_delete") do (
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

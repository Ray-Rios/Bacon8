@echo off
call "%~dp0paths.cmd"
rem Rebuilds RaysSpaceSim's editor once the editor has closed, then reopens it (run as a scheduled task,
rem so it outlives the editor). If the build fails, the uncommitted source changes are stashed
rem (git stash "b8 failed build") and the last committed source is built, so the editor still opens.
set P=C:\Bacon8\plugins\rays_space_sim\unreal
set LOG=C:\Bacon8\tmp\rss_build.log
echo waiting for the editor > "%LOG%"
:wait
tasklist /FI "IMAGENAME eq UnrealEditor.exe" | find /I "UnrealEditor.exe" >nul
if not errorlevel 1 ( ping -n 4 127.0.0.1 >nul & goto wait )
call "%P%\Scripts\stop_world_server.bat" >nul 2>&1
call %UE%\Engine\Build\BatchFiles\Build.bat RSSEditor Win64 Development -Project="%P%\RaysSpaceSim.uproject" -WaitMutex -architecture=x64 >> "%LOG%" 2>&1
if errorlevel 1 goto failed
echo BUILD_OK >> "%LOG%"
goto launch
:failed
echo BUILD_FAILED >> "%LOG%"
cd /d "%P%"
git stash push -m "b8 failed build" -- Source Plugins/Cosmos/Source >> "%LOG%" 2>&1
call %UE%\Engine\Build\BatchFiles\Build.bat RSSEditor Win64 Development -Project="%P%\RaysSpaceSim.uproject" -WaitMutex -architecture=x64 > C:\Bacon8\tmp\rss_build_restore.log 2>&1
echo RESTORED >> "%LOG%"
:launch
start "" "%UE%\Engine\Binaries\Win64\UnrealEditor.exe" "%P%\RaysSpaceSim.uproject" -skipcompile

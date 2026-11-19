@echo off
call "%~dp0paths.cmd"
rem Full RSSEditor build (RAYSSPACESIM.md 7c): waits for the Unreal editor to close (the DLLs are held while it runs).
set LOG=C:\Bacon8\tmp\rss_full_build.log
set U=C:\Bacon8\plugins\rays_space_sim\unreal
echo RSS full build: WAITING for the editor to close %time% > C:\Bacon8\tmp\RSS_BUILD_STATUS.txt
echo start %time% > %LOG%
:wait
tasklist /FI "IMAGENAME eq UnrealEditor.exe" | find /I "UnrealEditor.exe" > nul
if not errorlevel 1 (
  timeout /t 10 /nobreak > nul
  goto wait
)
echo RSS full build: BUILDING %time% > C:\Bacon8\tmp\RSS_BUILD_STATUS.txt
call "%UE%\Engine\Build\BatchFiles\Build.bat" RSSEditor Win64 Development -Project="%U%\RaysSpaceSim.uproject" -WaitMutex -NoHotReload >> %LOG% 2>&1
set RC=%errorlevel%
echo EXIT %RC% %time% >> %LOG%
if "%RC%"=="0" (echo RSS full build: DONE, OK - reopen the editor %time% > C:\Bacon8\tmp\RSS_BUILD_STATUS.txt) else (echo RSS full build: FAILED %RC% - see tmp\rss_full_build.log %time% > C:\Bacon8\tmp\RSS_BUILD_STATUS.txt)

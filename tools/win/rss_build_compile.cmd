@echo off
call "%~dp0paths.cmd"
setlocal enabledelayedexpansion
rem Compile check of the build-mode files (RAYSSPACESIM.md 7c), one at a time (-SingleFile: no DLL, the open editor untouched).
set LOG=C:\Bacon8\tmp\rss_build_compile.log
set U=C:\Bacon8\plugins\rays_space_sim\unreal
echo start %time% > %LOG%
for /f "usebackq delims=" %%F in ("C:\Bacon8\tmp\rss_build_files.txt") do (
  echo ==== %%F >> %LOG%
  call "%UE%\Engine\Build\BatchFiles\Build.bat" RSS Win64 Development -Project="%U%\RaysSpaceSim.uproject" -SingleFile="%U%\%%F" -WaitMutex -NoHotReload >> %LOG% 2>&1
  echo ==== EXIT !errorlevel! >> %LOG%
)
echo ALLDONE %time% >> %LOG%

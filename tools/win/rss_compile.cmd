@echo off
call "%~dp0paths.cmd"
rem Compile check of the changed RaysSpaceSim C++ files, one at a time against the editor target
rem (-SingleFile: compiles, writes no DLL, so the open editor is untouched).
set LOG=C:\Bacon8\tmp\rss_compile.log
set U=C:\Bacon8\plugins\rays_space_sim\unreal
echo RSS compile: RUNNING %time% > C:\Bacon8\tmp\RSS_COMPILE_STATUS.txt
echo start %time% > %LOG%
for %%F in (
  %U%\Source\RSS\B8\B8Outfitter.cpp
  %U%\Source\RSS\B8\B8LookComponent.cpp
  %U%\Source\RSS\B8\B8Creator.cpp
  %U%\Source\RSS\RSS.cpp
  %U%\Plugins\Cosmos\Source\Cosmos\Private\CosmicHUD.cpp
  %U%\Plugins\Cosmos\Source\Cosmos\Private\CosmicFlightComponent.cpp
  %U%\Plugins\Cosmos\Source\Cosmos\Private\CosmicDemoManager.cpp
  %U%\Plugins\Cosmos\Source\Cosmos\Private\CosmicMeleeComponent.cpp
  %U%\Plugins\Cosmos\Source\Cosmos\Private\CosmicWeaponsComponent.cpp
  %U%\Plugins\Cosmos\Source\Cosmos\Private\CosmicAbilityComponent.cpp
) do (
  echo ==== %%F >> %LOG%
  call "%UE%\Engine\Build\BatchFiles\Build.bat" RSS Win64 Development -Project="%U%\RaysSpaceSim.uproject" -SingleFile="%%F" -WaitMutex -NoHotReload >> %LOG% 2>&1
  echo ==== EXIT !errorlevel! %errorlevel% >> %LOG%
)
echo RSS compile: DONE %time% > C:\Bacon8\tmp\RSS_COMPILE_STATUS.txt

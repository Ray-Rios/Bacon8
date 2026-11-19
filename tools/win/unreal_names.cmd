@echo off
call "%~dp0paths.cmd"
set ST=C:\Bacon8\tmp\JOB_STATUS.txt
echo Unreal morph names: renaming the Unreal copies, started %date% %time% > %ST%
cd /d C:\Bacon8\art\pipeline\gltf
node unreal_morph_names.mjs C:\Bacon8\art\build\unreal\Humans C:\Bacon8\plugins\rays_space_sim\unreal\SourceAssets\Bacon8\Humans > C:\Bacon8\tmp\unreal_names.log 2>&1
findstr /c:"files" C:\Bacon8\tmp\unreal_names.log > nul && (echo Unreal morph names: DONE %date% %time% > %ST%) || (echo Unreal morph names: FAILED, see tmp\unreal_names.log > %ST%)

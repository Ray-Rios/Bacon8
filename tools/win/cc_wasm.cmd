@echo off
call "%~dp0paths.cmd"
set LOG=C:\Bacon8\tmp\cc_wasm.log
echo start %time% > %LOG%
docker run --rm -v "C:\Bacon8\plugins\rays_space_sim\unreal\Plugins\Box3DPhysics\Source\Box3D:/box3d:ro" -v "C:\Bacon8\plugins\bacon_world\native\box3d:/src:ro" -v "C:\Bacon8\tools\win:/t:ro" -v "C:\Bacon8\tmp\wasm_out:/out" ghcr.io/webassembly/wasi-sdk:wasi-sdk-25 sh /t/wasm_build.sh >> %LOG% 2>&1
echo EXIT %errorlevel% >> %LOG%
echo ALLDONE %time% >> %LOG%

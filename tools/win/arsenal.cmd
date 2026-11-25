@echo off
rem Bacon World's arsenal (2026-11-23): builds art\pipeline\scripts\build_arsenal.py with Blender (guns, energy
rem weapons, knives, nunchaku, flails) and puts B8_Arsenal.glb and its icons in art\models\Weapons. Then build.cmd
rem carries it to the games (the web copy into priv\static\models\Weapons), sync-models-to-k8s.sh uploads it.
call "%~dp0paths.cmd"
set "OUT=C:\Bacon8\art\pipeline\scripts\out\arsenal"
echo Building the arsenal (a few minutes; log: C:\Bacon8\tmp\arsenal.log)
"%BLENDER%" -b --factory-startup --python-exit-code 1 --python C:\Bacon8\art\pipeline\scripts\build_arsenal.py -- "%OUT%" > C:\Bacon8\tmp\arsenal.log 2>&1
if errorlevel 1 (echo FAILED: see C:\Bacon8\tmp\arsenal.log & exit /b 1)
if not exist "%OUT%\B8_Arsenal.glb" (echo FAILED: no B8_Arsenal.glb, see C:\Bacon8\tmp\arsenal.log & exit /b 1)
copy /y "%OUT%\B8_Arsenal.glb" C:\Bacon8\art\models\Weapons\B8_Arsenal.glb >nul
xcopy /y /q "%OUT%\icons\*.png" C:\Bacon8\art\models\Weapons\icons\ >nul
echo Done: art\models\Weapons\B8_Arsenal.glb and its icons. Next: build.cmd, then sync-models-to-k8s.sh and deploy-prod.sh.

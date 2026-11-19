@echo off
call "%~dp0paths.cmd"
set LOG=C:\Bacon8\tmp\gtest.log
set OUT=C:\Bacon8\art\work\daz_female\garments_test_1112
echo Garment test: RUNNING %time% > C:\Bacon8\tmp\JOB_STATUS.txt
call C:\Bacon8\art\pipeline\recipes\garments_v2.cmd %OUT%\Female_v2 uw_homespun_top+uw_velvet_top > %LOG% 2>&1
python C:\Bacon8\art\pipeline\recipes\garments_deliver.py %OUT% 2026-11-12t >> %LOG% 2>&1
cd /d C:\Bacon8\art\pipeline\gltf
node torso_width.mjs C:\Bacon8\priv\static\models\Humans\Female_v2.glb C:\Bacon8\priv\static\models\Humans\Garments\Female_v2\uw_homespun_top.glb C:\Bacon8\priv\static\models\Humans\Garments\Female_v2\uw_velvet_top.glb >> %LOG% 2>&1
echo Garment test: DONE %time% > C:\Bacon8\tmp\JOB_STATUS.txt

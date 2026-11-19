@echo off
call "%~dp0paths.cmd"
set LOG=C:\Bacon8\tmp\ex_test.log
cd /d C:\Bacon8
echo start %time% > %LOG%
docker network create bacon8chk >> %LOG% 2>&1
docker run -d --rm --name bacon8chk-pg --network bacon8chk -e POSTGRES_PASSWORD=postgres postgres:16 >> %LOG% 2>&1
timeout /t 8 /nobreak > nul
docker run --rm --network bacon8chk -v "C:\Bacon8:/app" -v bacon8_deps:/app/deps -v bacon8_build:/app/_build -w /app -e MIX_ENV=test -e DB_HOST=bacon8chk-pg elixir:1.19 sh -c "mix local.hex --force >/dev/null && mix local.rebar --force >/dev/null && mix deps.get >/dev/null && mix compile --warnings-as-errors && mix test plugins/bacon_world/test/bacon_world/appearance_test.exs plugins/bacon_world/test/bacon_world/inventory_test.exs plugins/bacon_world/test/bacon_world/item_studio_test.exs plugins/bacon_world/test/bacon_world/humans_test.exs" >> %LOG% 2>&1
echo EXIT %errorlevel% >> %LOG%
docker stop bacon8chk-pg >> %LOG% 2>&1
docker network rm bacon8chk >> %LOG% 2>&1
echo ALLDONE %time% >> %LOG%

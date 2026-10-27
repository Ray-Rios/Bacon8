<#
  The runner's own test run (runner.ps1 calls it after Claude's change; exit 0 = passed).
  Everything happens in throwaway Docker containers (BACON8.md: nothing is built on the dev PC):

    1. Elixir: a fresh Postgres, then `mix compile --warnings-as-errors` and `mix test` (the hub
       and every installed plugin).
    2. JavaScript, when the `bacon8-assets-check` image is there: the plugins' unit tests and a
       bundle of app.ts (a type or import error fails it).

  Its own Docker volumes (bacon8agent_*), so it never shares a build with a run of yours.
#>
param([string]$Repo = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..")).Path)

$ErrorActionPreference = "Continue"
$net = "bacon8agent"
$pg = "bacon8agent-pg"
$src = ($Repo -replace '\\', '/')

docker network create $net 2>&1 | Out-Null
docker rm -f $pg 2>&1 | Out-Null
docker run -d --rm --name $pg --network $net -e POSTGRES_PASSWORD=postgres postgres:16 | Out-Null
Start-Sleep -Seconds 6

docker run --rm --network $net -v "${src}:/app" -v bacon8agent_deps:/app/deps -v bacon8agent_build:/app/_build -w /app `
  -e MIX_ENV=test -e DB_HOST=$pg elixir:1.19 `
  sh -c "set -e; mix local.hex --force >/dev/null; mix local.rebar --force >/dev/null; mix deps.get >/dev/null; mix compile --warnings-as-errors; mix test"
$elixir = $LASTEXITCODE

docker stop $pg 2>&1 | Out-Null
docker network rm $net 2>&1 | Out-Null
if ($elixir -ne 0) { Write-Host "ELIXIR TESTS FAILED (exit $elixir)"; exit 1 }

docker image inspect bacon8-assets-check 2>&1 | Out-Null
if ($LASTEXITCODE -eq 0) {
  docker run --rm -v "${src}/plugins:/app/plugins:ro" -v "${src}/assets/js:/src_js:ro" -w /app/assets bacon8-assets-check `
    sh -c "set -e; rm -rf js && cp -r /src_js js && node scripts/gen-plugin-hooks.js; for t in /app/plugins/*/assets/js/__tests__/run.sh; do [ -f `$t ] && sh `$t; done; npx --no-install esbuild js/app.ts --bundle --outdir=/tmp/out --external:/fonts/* --external:/images/* --external:*.css --format=iife --target=es2020 --loader:.ts=ts --define:global=window --log-level=error"
  if ($LASTEXITCODE -ne 0) { Write-Host "JS TESTS OR BUNDLE FAILED"; exit 1 }
} else {
  Write-Host "(no bacon8-assets-check image: JavaScript not checked)"
}

Write-Host "ALL TESTS PASSED"
exit 0

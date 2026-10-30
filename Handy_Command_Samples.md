# Bacon8 Handy Command Samples

Cheat sheet for day-to-day work on this repo: Elixir/Phoenix, Docker, k3s/kubectl,
Postgres/Redis ops, and the RaysSpaceSim game server pipeline. See [README.md](README.md)

**Namespaces:** `bacon8-dev` (dev overlay, `deploy-dev.sh`) and `bacon8`
(prod overlay, `deploy-prod.sh`). Deployment name is always `bacon8-web` in both.
---

## 🔑 Prod secrets (first-time / rotation)

Generate before deploying prod, or `bacon8-start.sh` fails fast on boot. Place the values in `k3s/overlays/prod/secrets.yaml` (copy `secrets.example.yaml`, then change the DB password too):

```bash
mix phx.gen.secret 64        # SECRET_KEY_BASE
mix phx.gen.secret 32        # LIVE_VIEW_SIGNING_SALT
mix guardian.gen.secret      # GUARDIAN_SECRET_KEY
```
## 🧪 Elixir / Phoenix (mix)
```bash
mix deps.get
mix deps.clean --all
mix clean
mix compile
mix format                   # or: mix format --check-formatted (what `mix lint` runs)
mix ecto.create
mix ecto.migrate
mix ecto.drop
mix ecto.reset               # alias: drop + create + migrate + seed
mix setup                    # alias: deps.get + ecto.setup + assets.setup + assets.build
mix test                     # creates/migrates test DB first
mix lint                     # format check, eslint, tsc, credo --strict, sobelow, dialyzer
mix phx.server
pkill -f "mix phx.server"    # stop a stray local server
```

⚠️ **Games platform has its own Ecto repo** (`Bacon8.GamesRepo`, migrations
under `priv/games_repo/migrations`). `mix ecto.migrate` only touches the main repo —
games migrations need `mix ecto.migrate -r Bacon8.GamesRepo`.

### Assets

`mix assets.setup` / `assets.build` / `assets.deploy` and `mix lint`'s frontend
steps all shell out to `scripts/dev-assets.sh` (see [README.md](README.md#assets)).
**That script is currently missing from the working tree** — if the alias fails
with "No such file or directory", either restore it or run the npm scripts
directly from `assets/`:

```bash
cd assets
npm ci                       # or npm install
npm run build                # update-browserslist + build:css + build:js
npm run build:css            # Tailwind/PostCSS only — use this when only .css didn't load
npm run watch                # css + js watchers for local dev
npm run type-check
npm run lint                 # eslint + stylelint
npm run test:e2e              # Playwright
```

---

## 🐳 Docker

Prod/dev image build uses `Dockerfile.multistage` with `MIX_ENV` as a build arg
(this is what `deploy-dev.sh` / `deploy-prod.sh` / `new-prod-migrations.sh` do):

```bash
docker build -t bacon8:dev  -f Dockerfile.multistage --build-arg MIX_ENV=dev  .
docker build -t bacon8:prod -f Dockerfile.multistage --build-arg MIX_ENV=prod --progress=plain .
docker build --no-cache -f Dockerfile.multistage -t bacon8:prod --build-arg MIX_ENV=prod .
```

Cleanup (there is no `cleanup-docker.sh` in this repo — do it by hand):

```bash
docker images --filter=reference="bacon8*" -q | xargs -r docker rmi -f   # Bacon8 images only
docker container prune -f      # remove stopped containers
docker image prune -f          # remove dangling images
docker builder prune -f        # clean build cache

# ☢️ Nuclear (destroys ALL local images/containers/volumes, not just this project):
docker system prune -a -f --volumes
```

Compact the Docker Desktop WSL virtual disk after a big cleanup (PowerShell, run as Admin):

```powershell
$script = @"
select vdisk file="C:\Users\error\AppData\Local\Docker\wsl\disk\docker_data.vhdx"
attach vdisk readonly
compact vdisk
detach vdisk
exit
"@
$scriptPath = "$env:TEMP\compact_docker_vhdx.txt"
$script | Out-File -FilePath $scriptPath -Encoding ascii
diskpart /s $scriptPath

# Re-run capturing output/exit code if it silently no-ops (needs admin):
$p = Start-Process diskpart -ArgumentList "/s `"$scriptPath`"" -NoNewWindow -Wait -PassThru `
  -RedirectStandardOutput "$env:TEMP\diskpart_out.txt" -RedirectStandardError "$env:TEMP\diskpart_err.txt"
"ExitCode: $($p.ExitCode)"
Get-Content "$env:TEMP\diskpart_out.txt", "$env:TEMP\diskpart_err.txt"
([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
```

---

## ☸️ Kubernetes / k3s

### Deploy scripts (prefer these over raw kubectl)

```bash
./deploy-dev.sh                     # rebuilds image, applies k3s/overlays/dev, waits, streams logs
./deploy-prod.sh                    # backs up db/redis/certs, preserves PVCs, redeploys bacon8
./deploy-prod.sh --fresh            # wipes db PVC and restores from most recent backup
plugins/rays_space_sim/deploy-game.sh   # RaysSpaceSim: server image + client, rollout, launcher publish (see below)
./new-prod-migrations.sh            # rebuild image (no-cache), run k3s/jobs/run-migrations.yaml, restart web

kubectl apply -k k3s/overlays/dev
kubectl apply -k k3s/overlays/prod
```

### Everyday inspection

```bash
kubectl get pods -n bacon8-dev
kubectl get all -n bacon8
kubectl get pvc -n bacon8-dev
kubectl get events -n bacon8-dev --sort-by='.metadata.creationTimestamp' | tail -n 20
kubectl get certificates -n bacon8
kubectl get svc -n ingress-nginx -o wide
kubectl get configmap bacon8-config -n bacon8-dev -o yaml
kubectl get ingress -n bacon8-dev -o yaml
kubectl get endpoints bacon8-web -n bacon8-dev

kubectl describe deployment bacon8-web -n bacon8-dev
kubectl describe ingress bacon8-ingress -n bacon8

kubectl logs -f deployment/bacon8-web -n bacon8
kubectl logs -n bacon8 -l app=bacon8-web -f
kubectl logs -n bacon8 -l app=bacon8-web -f | grep -i "phx_join" --line-buffered   # LiveView join debugging
```

### Rollouts / scaling

```bash
kubectl rollout restart deployment/bacon8-web -n bacon8
kubectl rollout status  deployment/bacon8-web -n bacon8 --timeout=300s

kubectl scale deployment bacon8-web --replicas=0 -n bacon8 && sleep 5 && \
  kubectl scale deployment bacon8-web --replicas=2 -n bacon8

# Rebuild + rollout in one line (dev image name, not the tag deploy scripts use):
docker build --no-cache -f Dockerfile.multistage -t bacon8:dev --build-arg MIX_ENV=dev . && \
  kubectl rollout restart deployment/bacon8-web -n bacon8-dev
```

### Migrations (run through the release, not `mix`)

```bash
MSYS_NO_PATHCONV=1 kubectl exec -n bacon8 \
  $(kubectl get pods -n bacon8 -l app=bacon8-web -o name | head -1) \
  -- /app/bin/bacon8 eval "Bacon8.Release.migrate()"

# Or as a one-shot job (what new-prod-migrations.sh does):
kubectl apply -f k3s/jobs/run-migrations.yaml
kubectl wait --for=condition=complete job/run-migrations -n bacon8 --timeout=300s
kubectl logs job/run-migrations -n bacon8
kubectl delete job run-migrations -n bacon8 --ignore-not-found=true
```

### Nuking / rebuilding an environment

```bash
kubectl delete namespace bacon8-dev --ignore-not-found=true    # deletes everything incl. PVCs
./deploy-dev.sh

# Prod — deploy-prod.sh already preserves PVCs by default; only do this manually
# if you explicitly want a from-scratch prod namespace (⚠️ destroys the cluster's copy of the db):
kubectl delete namespace bacon8 --ignore-not-found=true && ./deploy-prod.sh --fresh
```

---

## 🎮 RaysSpaceSim game server (`deploy-game.sh`)

Separate pipeline from the Bacon8 app on purpose — see the big comment block at
the top of `plugins/rays_space_sim/deploy-game.sh` (it moved into the game's private
plugin on 2026-10-16). Tags are the game repo's git SHA (`-dirty-<UTC
timestamp>` if uncommitted), never `latest`. Deployed via the `HOLOSIM_IMAGE`
value in `k3s/overlays/prod/configmap.yaml`.

```bash
cd plugins/rays_space_sim
./deploy-game.sh                 # server + client for the current commit, roll out, publish to the launcher
./deploy-game.sh --build-only    # build server + client and tag; publish nothing
./deploy-game.sh --server-only   # build + smoke-test the server image; ship nothing
./deploy-game.sh --finish <tag>  # finish a run whose server image built but whose client did not
./deploy-game.sh --client-only   # build + publish a client for the LIVE server tag
./deploy-game.sh --publish-only  # re-publish the last staged client (no cook)
./deploy-game.sh --list          # show built tags and which one is live
./deploy-game.sh --smoke [tag]   # boot the image locally and show its log
./deploy-game.sh --set <tag>     # roll out a tag that is already built
./deploy-game.sh --codemap       # regenerate the code map only (no cook)
./deploy-game.sh --disable       # revert to the manual launch path
```

The day-to-day loop doesn't use it: compile, run the editor as a dev shard and PIE
(`plugins/rays_space_sim/unreal/RAYSSPACESIM.md` §2).

Build the editor target directly (or `plugins/rays_space_sim/unreal/Scripts/compile_editor.sh`):

```bash
"/c/UnrealEngine/Engine/Build/BatchFiles/Build.bat" RSSEditor Win64 Development \
  -Project="C:/Bacon8/plugins/rays_space_sim/unreal/RaysSpaceSim.uproject" -WaitMutex
```

⚠️ **Git Bash / MSYS gotcha:** never pass absolute POSIX paths as `docker`/`kubectl`
arguments (e.g. `--entrypoint /bin/true`) — MSYS rewrites them into Windows paths
and the container fails with a confusing "no such file" error. Drop the leading
slash or prefix the command with `MSYS_NO_PATHCONV=1`.

---

## 🐘 PostgreSQL (`postgres-ops.sh`)

Defaults: namespace `bacon8`, db `bacon8_prod`, user `postgres`. Override
with `NAMESPACE=bacon8-dev ./postgres-ops.sh ...` for dev.

```bash
./postgres-ops.sh backup                # dump to ./backups/db_backup_<timestamp>.sql
./postgres-ops.sh restore               # pick from backup list and restore
./postgres-ops.sh list                  # show all available backups
./postgres-ops.sh clean                 # remove old backups (keep 10)
./postgres-ops.sh connect               # psql shell
./postgres-ops.sh size                  # database sizes
./postgres-ops.sh logs                  # postgres pod logs
```

---

## 🔴 Redis (`redis-ops.sh`)

Default namespace `bacon8`.

```bash
./redis-ops.sh backup                    # BGSAVE + copy dump.rdb to ./backups
./redis-ops.sh restore                   # restore most recent backup
./redis-ops.sh monitor                   # live MONITOR of all Redis commands
./redis-ops.sh keys "chat:*"             # chat-related keys
./redis-ops.sh keys "player:*"           # player-related keys
./redis-ops.sh keys "session:*"          # session keys
./redis-ops.sh flush                     # ☢️ DANGEROUS: deletes ALL data, not guarded
```

---

## 📁 Uploads & static models sync

```bash
./sync-uploads-to-k8s.sh          # push local ./uploads -> bacon8-web pod (bacon8 ns)
./sync-uploads-from-k8s.sh        # pull uploads back down
./sync-models-to-k8s.sh           # push ./priv/static/models -> pod (large, 2.6GB+, may take 5-10 min)
```

---

## 🌐 Quick test links (dev)

| What | URL |
|---|---|
| App | http://localhost:4000 |
| Health check | http://localhost:4000/health |
| Services status | http://localhost:4000/admin/services |
| GraphQL | http://localhost:4000/api/graphql |
| GraphiQL (dev only) | http://localhost:4000/api/graphiql |
| Mailhog | http://localhost:8025 |

Auth smoke test:

```bash
curl -X POST http://localhost:4000/api/auth/register -H "Content-Type: application/json" \
  -d '{"email":"test@example.com","name":"TestUser","password":"SecurePass123!"}'

curl -X POST http://localhost:4000/api/auth/dev-verify -H "Content-Type: application/json" \
  -d '{"email":"test@example.com"}'          # dev only — must 404 in prod, see README security notes

curl -X POST http://localhost:4000/api/auth/login -H "Content-Type: application/json" \
  -d '{"email":"test@example.com","password":"SecurePass123!"}'
```

JS bundle / caching check:

```bash
curl -Ik https://localhost/assets/app.js
```

LiveView/WebSocket debugging:

1. Browser console should show `"✅ Phoenix LiveView connected"`.
2. Network tab → WS → confirm the `Upgrade` handshake succeeded.
3. Tail joins/channel activity: `kubectl logs -n bacon8 -l app=bacon8-web -f | grep -i "phx_join" --line-buffered`

---

## 🪟 Windows helpers

```powershell
# Find stray BEAM/Erlang/Node processes
Get-Process | Where-Object {$_.ProcessName -like "*beam*" -or $_.ProcessName -like "*erl*" -or $_.ProcessName -like "*node*"}
```

## 🩹 Misc fixes

```bash
# File corruption fix (recreate an empty tracked file)
rm file_name.ts && touch file_name.ts

# Fix a broken/detached github repo by re-pointing bookkeeping at a remote,
# without touching your working tree:
mv -v .git .git_old               # keep old git metadata around, just in case
git init
git remote add origin "${url}"
git fetch
git reset origin/master --mixed    # use origin/main if that's what the remote uses
```
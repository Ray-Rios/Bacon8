# Bacon8 command cheat sheet

The maintainer's commands: starting from scratch, the day-to-day, and what to run when
something is wrong in a running environment. Everything runs from Git Bash in `C:\Bacon8`
(the scripts in `scripts/` move to the repository root themselves, so they work from any folder).
[README.md](README.md) explains what Bacon8 is; [BACON8.md](BACON8.md) is the engineering reference.

| | Prod | Dev |
|---|---|---|
| Namespace | `bacon8` | `bacon8-dev` |
| Deploy | `scripts/deploy-prod.sh` | `scripts/deploy-dev.sh` |
| Deployment / pod label | `bacon8-web` / `app=bacon8-web` | the same |
| Databases | `bacon8_prod`, `bacon8_games_prod` | `bacon8_dev`, `bacon8_games_dev` |

Git Bash rewrites absolute POSIX paths in arguments (`/app/bin/bacon8` becomes a Windows path).
Prefix those commands with `MSYS_NO_PATHCONV=1`.

---

## 1. Starting from scratch

**Needs:** Docker Desktop with Kubernetes (or k3s), `kubectl`, Git Bash. Nothing is built on the host:
Elixir, Node and the assets are built inside the image.

```bash
# 1. Secrets (never committed). Copy the examples and fill them in; change the database password too.
cp k3s/overlays/prod/secrets.example.yaml k3s/overlays/prod/secrets.yaml
docker run --rm elixir:1.19 sh -c 'mix local.hex --force >/dev/null; mix phx.gen.secret 64; mix phx.gen.secret 32; mix phx.gen.secret'
#    -> SECRET_KEY_BASE, LIVE_VIEW_SIGNING_SALT, GUARDIAN_SECRET_KEY. Also copy ingress.example.yaml and
#       mailhog-auth-secret.example.yaml. The start script refuses to boot without the secrets.

# 2. Deploy. On an empty cluster it restores the newest dumps in backups/ (see section 4).
scripts/deploy-prod.sh

# 3. Models and uploads are not in the image; push them (the models are 2.6 GB, 5-10 minutes).
scripts/sync-models-to-k8s.sh
scripts/sync-uploads-to-k8s.sh --replace-production-uploads     # only when you mean to replace prod's uploads

# 4. Check it.
kubectl get pods -n bacon8
curl -s http://localhost:8080/health      # after: kubectl port-forward -n bacon8 deploy/bacon8-web 8080:4000
```

The game (RaysSpaceSim) has its own pipeline, section 6.

---

## 2. Day to day

### Build and test (always in Docker; there is no local Elixir)

```bash
export MSYS_NO_PATHCONV=1      # Git Bash: stops it rewriting -w /app into a Windows path

# Compile with warnings as errors
docker run --rm -v "$PWD:/app" -v bacon8_deps:/app/deps -v bacon8_build:/app/_build -w /app -e MIX_ENV=dev elixir:1.19 \
  sh -c 'mix local.hex --force && mix local.rebar --force && mix deps.get && mix compile --warnings-as-errors'

# Tests need only Postgres (full recipe: BACON8.md section 14)
docker network create bacon8chk
docker run -d --rm --name bacon8chk-pg --network bacon8chk -e POSTGRES_PASSWORD=postgres postgres:16
docker run --rm --network bacon8chk -v "$PWD:/app" -v bacon8_deps:/app/deps -v bacon8_build:/app/_build \
  -w /app -e MIX_ENV=test -e DB_HOST=bacon8chk-pg elixir:1.19 \
  sh -c 'mix local.hex --force && mix local.rebar --force && mix deps.get && mix test'
docker stop bacon8chk-pg && docker network rm bacon8chk

sh plugins/bacon_world/assets/js/__tests__/run.sh         # Bacon World's JS tests (its own container)
```

Games-platform migrations live in a second repo: `mix ecto.migrate -r Bacon8.GamesRepo`
(production runs both through the release, section 3).

### Deploy

```bash
git status                       # the deploy builds from the WORKING TREE: no one else's half-finished work
scripts/deploy-prod.sh           # backs up both databases, redis and certificates, rebuilds, redeploys, runs migrations
scripts/deploy-prod.sh --fresh   # DANGER: wipes the database volume and restores the newest backup
scripts/deploy-dev.sh            # the dev namespace
scripts/new-prod-migrations.sh   # rebuild and run only the migrations job, then restart web
scripts/sync-models-to-k8s.sh    # after changing priv/static/models (only when told to)
```

`deploy-prod.sh` deletes the namespace before it builds the image (the volumes survive), so a failing
build means downtime. Compile first, and check the Dockerfile's `COPY` lines if you removed or moved files.

### Look at it

```bash
kubectl get pods -n bacon8
kubectl logs -f deploy/bacon8-web -n bacon8 -c bacon8
kubectl logs -n bacon8 -l app=bacon8-web --since=15m | grep -iE "error|exception|\[warning\]"
kubectl top pod -n bacon8                                  # CPU and memory
kubectl rollout restart deploy/bacon8-web -n bacon8        # restart without a rebuild
kubectl rollout status  deploy/bacon8-web -n bacon8 --timeout=300s
```

---

## 3. Something is wrong: investigate and fix

### The site does not load or a pod will not start

```bash
kubectl get pods -n bacon8                                 # Pending / CrashLoopBackOff / Init:Error?
kubectl describe pod <pod> -n bacon8                       # events at the bottom: image pull, volume, probe failures
kubectl logs <pod> -n bacon8 -c bacon8 --previous          # why the last run died
kubectl logs <pod> -n bacon8 -c wait-for-migrations        # stuck in Init: migrations pending or failing
kubectl get events -n bacon8 --sort-by=.metadata.creationTimestamp | tail -20
kubectl get ingress,svc,endpoints -n bacon8                # no endpoints = no ready pod
kubectl get certificates -n bacon8                         # TLS
```

Common causes: a missing or placeholder secret (the start script exits at once); a pending migration;
Postgres or Redis not ready yet; the image was not rebuilt after a change.

### Run code inside the running app

```bash
MSYS_NO_PATHCONV=1 kubectl exec -it -n bacon8 deploy/bacon8-web -c bacon8 -- /app/bin/bacon8 remote   # IEx on the live node
MSYS_NO_PATHCONV=1 kubectl exec -n bacon8 deploy/bacon8-web -c bacon8 -- /app/bin/bacon8 eval "Bacon8.Release.status()"
MSYS_NO_PATHCONV=1 kubectl exec -n bacon8 deploy/bacon8-web -c bacon8 -- /app/bin/bacon8 eval "Bacon8.Release.migrate()"
```

### Database

```bash
scripts/postgres-ops.sh connect      # psql shell (bacon8_prod; set DB_NAME=bacon8_games_prod for the games database)
scripts/postgres-ops.sh size         # database sizes
scripts/postgres-ops.sh logs         # Postgres pod logs
NAMESPACE=bacon8-dev scripts/postgres-ops.sh connect       # any of these against dev
```

A migration that fails halfway leaves the web pod in `Init`. Read its log (above), fix the migration,
redeploy. To roll one back: `Bacon8.Release.rollback(Bacon8.Repo, <version>)` through `eval`.

### Back out a bad deploy

The image is built locally as `bacon8:prod`, so `kubectl rollout undo` brings back nothing different.
Check out the last good commit and run `scripts/deploy-prod.sh` again. If the data is damaged, restore:
`scripts/postgres-ops.sh restore` (pick a dump). Every deploy writes one to `backups/` first.

### Redis, plugins, the game

```bash
scripts/redis-ops.sh keys "chat:*"           # also "player:*", "session:*"
scripts/redis-ops.sh monitor                 # live command stream; Ctrl+C to stop
scripts/redis-ops.sh backup | restore
#   scripts/redis-ops.sh flush  deletes EVERYTHING and is not guarded.

# A plugin missing from the site: it must be in BACON8_ACTIVE_PLUGINS (k3s/overlays/prod/configmap.yaml)
# and switched on at /admin/plugins.
kubectl get pods -n raysspacesim                                  # the game's world server and holo-sim instances
kubectl logs -n raysspacesim deploy/rss-world-server --tail=100
```

### Files and uploads

```bash
scripts/sync-uploads-from-k8s.sh             # pull production's uploads down to ./uploads (does not touch prod)
scripts/sync-uploads-to-k8s.sh --replace-production-uploads   # the opposite: replaces prod's. Pull first.
```

### Backups

```bash
powershell -ExecutionPolicy Bypass -File scripts/backup.ps1 -Destination D:\Backups   # everything git does not hold
scripts/postgres-ops.sh backup | list | clean        # dumps in ./backups (clean keeps the newest 10)
```

---

## 4. Secrets, in short

`k3s/overlays/*/secrets.yaml`, `ingress.yaml` and `mailhog-auth-secret.yaml` are gitignored: keep it so.
Rotate `GAMES_SERVER_API_KEY` if an image leaks (it acts as any user through the games API). Never paste a
secret into a chat, a commit or a log.

---

## 5. Docker housekeeping

```bash
docker images --filter=reference="bacon8*"
docker image prune -f && docker builder prune -f           # dangling images, build cache
docker system df                                           # what is using the disk
```

After a big cleanup, shrink Docker Desktop's WSL disk (PowerShell as Administrator; quit Docker Desktop first):

```powershell
wsl --shutdown
$f = "$env:TEMP\compact.txt"
"select vdisk file=`"$env:LOCALAPPDATA\Docker\wsl\disk\docker_data.vhdx`"`nattach vdisk readonly`ncompact vdisk`ndetach vdisk`nexit" | Out-File $f -Encoding ascii
diskpart /s $f
```

---

## 6. RaysSpaceSim (the game)

Its own pipeline, in its private plugin. The day-to-day loop (compile, run the editor as a dev shard, PIE) is in
`plugins/rays_space_sim/unreal/RAYSSPACESIM.md` section 2.

```bash
cd plugins/rays_space_sim
./deploy-game.sh --list          # built tags and which one is live
./deploy-game.sh                 # server + client for the current commit, roll out, publish to the launcher
./deploy-game.sh --build-only    # build and tag, publish nothing
./deploy-game.sh --set <tag>     # roll out (or roll back to) a tag that is already built
./deploy-game.sh --codemap       # regenerate the code map only; it reaches the site with the next deploy-prod.sh
# the rest (--server-only, --client-only, --publish-only, --smoke, --finish, --disable): the header of deploy-game.sh

plugins/rays_space_sim/unreal/Scripts/compile_editor.sh    # build the editor target
```

Close the editor before a cook, and stop the world server (`Scripts/stop_world_server.bat`) before a build.

---

## 7. Odds and ends

```powershell
# Stray BEAM / Erlang / Node processes
Get-Process | Where-Object { $_.ProcessName -match 'beam|erl|node' }
```

```bash
# Re-point a broken git checkout at its remote without touching the working tree
mv .git .git_old && git init && git remote add origin "<url>" && git fetch && git reset origin/main --mixed
```

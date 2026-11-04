#!/usr/bin/env bash
# Rotate Bacon8's production secrets (BACON8.md §17). Run from the repo root on the development
# PC, in Git Bash, with kubectl pointed at the production cluster:
#
#   scripts/security/rotate-secrets.sh --dry-run all       # what it would do, changes nothing
#   scripts/security/rotate-secrets.sh app tokens games-key db
#   scripts/security/rotate-secrets.sh stripe smtp mailhog # values you get elsewhere, typed in
#
# What each one rotates:
#   app        SECRET_KEY_BASE, LIVE_VIEW_SIGNING_SALT   everyone is signed out; reset links die
#   tokens     GUARDIAN_SECRET_KEY                       game clients and launchers sign in again
#   games-key  GAMES_SERVER_API_KEY                      hub and RaysSpaceSim; restart world servers
#   db         DB_PASSWORD                               the Postgres role first, then the secret
#   stripe     STRIPE_SECRET_KEY, STRIPE_WEBHOOK_SECRET  roll them in the Stripe dashboard first
#   smtp       SMTP_PASS                                 change it at the mail provider first
#   mailhog    the Mailhog page's login (htpasswd)
#   all        app tokens games-key db (the ones it can make itself)
#
# It never prints a secret. New values are made with openssl and written straight into the
# gitignored secrets files (k3s/overlays/prod/secrets.yaml,
# plugins/rays_space_sim/k3s/raysspacesim-secrets.yaml, k3s/overlays/prod/mailhog-auth-secret.yaml),
# after a copy of each goes to tmp/secrets-backup/<time>/ (gitignored; delete it once the site
# works). Then it applies them and restarts the web pods. It does not touch .env.stripe.
set -euo pipefail

DRY=0
WHAT=()
for a in "$@"; do
  case "$a" in
    --dry-run) DRY=1 ;;
    all) WHAT+=(app tokens games-key db) ;;
    app|tokens|games-key|db|stripe|smtp|mailhog) WHAT+=("$a") ;;
    -h|--help) sed -n '2,27p' "$0"; exit 0 ;;
    *) echo "Unknown: $a (see --help)" >&2; exit 2 ;;
  esac
done
[ ${#WHAT[@]} -gt 0 ] || { sed -n '2,27p' "$0"; exit 2; }

NS=bacon8
HUB=k3s/overlays/prod/secrets.yaml
RSS=plugins/rays_space_sim/k3s/raysspacesim-secrets.yaml
MAILHOG=k3s/overlays/prod/mailhog-auth-secret.yaml
[ -f "$HUB" ] || { echo "No $HUB here: run this from the repo root." >&2; exit 1; }
command -v openssl >/dev/null || { echo "openssl is needed (Git Bash has it)." >&2; exit 1; }
command -v kubectl >/dev/null || { echo "kubectl is needed." >&2; exit 1; }

STAMP=$(date +%Y%m%d-%H%M%S)
BACKUP="tmp/secrets-backup/$STAMP"
say() { echo "• $*"; }
run() { if [ $DRY = 1 ]; then echo "  (dry run) $*"; else "$@"; fi; }

backup() {
  [ -f "$1" ] || return 0
  if [ $DRY = 0 ]; then mkdir -p "$BACKUP/$(dirname "$1")"; cp "$1" "$BACKUP/$1"; chmod 600 "$BACKUP/$1" 2>/dev/null || true; fi
}
for f in "$HUB" "$RSS" "$MAILHOG"; do backup "$f"; done
[ $DRY = 1 ] || say "backups in $BACKUP (delete when the site works again)"

# set_key FILE KEY VALUE: a shell function, so VALUE is on no process's command line; awk gets it
# through its environment. Keeps the file's line endings.
set_key() {
  local file=$1 key=$2 val=$3
  [ $DRY = 1 ] && { echo "  (dry run) would set $key in $file"; return; }
  grep -q "^[[:space:]]*$key:" "$file" || { echo "$key isn't in $file: add a line for it first." >&2; exit 1; }
  local tmp="$file.tmp.$$"
  KEY="$key" NEWVAL="$val" awk '{
      cr = sub(/\r$/, "")
      if ($0 ~ "^[[:space:]]*" ENVIRON["KEY"] ":") { match($0, /^[[:space:]]*/); $0 = substr($0, 1, RLENGTH) ENVIRON["KEY"] ": \"" ENVIRON["NEWVAL"] "\"" }
      printf "%s%s\n", $0, (cr ? "\r" : "")
    }' "$file" > "$tmp"
  mv "$tmp" "$file"
}

hex() { openssl rand -hex "$1"; }
ask() { # ask PROMPT: reads without echo into NEWVAL
  [ $DRY = 1 ] && { NEWVAL=dry; return; }
  local again
  read -r -s -p "$1: " NEWVAL; echo
  read -r -s -p "Again: " again; echo
  [ -n "$NEWVAL" ] && [ "$NEWVAL" = "$again" ] || { echo "They differ or are empty; nothing changed for this one." >&2; exit 1; }
  case "$NEWVAL" in *\"*|*\\*) echo "Quotes and backslashes aren't supported in these values." >&2; exit 1 ;; esac
}

RESTART_WEB=0; APPLY_RSS=0; APPLY_MAILHOG=0
for w in "${WHAT[@]}"; do
  case "$w" in
    app)
      say "SECRET_KEY_BASE and LIVE_VIEW_SIGNING_SALT (everyone will be signed out)"
      set_key "$HUB" SECRET_KEY_BASE "$(hex 48)"
      set_key "$HUB" LIVE_VIEW_SIGNING_SALT "$(hex 16)"
      RESTART_WEB=1 ;;
    tokens)
      say "GUARDIAN_SECRET_KEY (game clients sign in again)"
      set_key "$HUB" GUARDIAN_SECRET_KEY "$(hex 48)"
      RESTART_WEB=1 ;;
    games-key)
      say "GAMES_SERVER_API_KEY (the hub's and RaysSpaceSim's, the same value)"
      NEWVAL=$(hex 32)
      set_key "$HUB" GAMES_SERVER_API_KEY "$NEWVAL"
      if [ -f "$RSS" ]; then set_key "$RSS" GAMES_SERVER_API_KEY "$NEWVAL"; APPLY_RSS=1; else say "no $RSS: put the same key wherever your game servers read it"; fi
      unset NEWVAL
      RESTART_WEB=1 ;;
    db)
      say "DB_PASSWORD: changing the Postgres role's password first"
      DBUSER=$(kubectl get configmap -n "$NS" -o jsonpath='{.items[*].data.DB_USERNAME}' | awk '{print $1}')
      DBUSER=${DBUSER:-postgres}
      NEWVAL=$(hex 24)
      if [ $DRY = 1 ]; then
        set_key "$HUB" DB_PASSWORD x
        echo "  (dry run) would ALTER ROLE $DBUSER in deploy/postgres, then set DB_PASSWORD"
      else
        # through stdin, so the password is on no command line; the container trusts its own socket
        printf "ALTER ROLE \"%s\" WITH PASSWORD '%s';\n" "$DBUSER" "$NEWVAL" \
          | kubectl exec -i -n "$NS" deploy/postgres -- psql -U "$DBUSER" -d postgres -v ON_ERROR_STOP=1 -q
        set_key "$HUB" DB_PASSWORD "$NEWVAL"
        say "the role has its new password; running pods keep their open connections until the restart below"
      fi
      unset NEWVAL
      RESTART_WEB=1 ;;
    stripe)
      say "Stripe: roll the secret key and the webhook signing secret in the dashboard first"
      ask "New STRIPE_SECRET_KEY"; set_key "$HUB" STRIPE_SECRET_KEY "$NEWVAL"
      ask "New STRIPE_WEBHOOK_SECRET"; set_key "$HUB" STRIPE_WEBHOOK_SECRET "$NEWVAL"; unset NEWVAL
      say "update .env.stripe on this PC yourself (nothing here opens it)"
      RESTART_WEB=1 ;;
    smtp)
      ask "New SMTP_PASS (already changed at the mail provider)"; set_key "$HUB" SMTP_PASS "$NEWVAL"; unset NEWVAL
      RESTART_WEB=1 ;;
    mailhog)
      if command -v htpasswd >/dev/null; then HTP=(htpasswd); else HTP=(docker run --rm -i httpd:2.4 htpasswd); fi
      ask "New Mailhog password (user admin)"
      if [ $DRY = 0 ]; then
        # the Secret's `data:` holds the htpasswd line base64-encoded
        LINE=$(printf '%s' "$NEWVAL" | "${HTP[@]}" -niB admin | head -1)
        set_key "$MAILHOG" auth "$(printf '%s\n' "$LINE" | base64 | tr -d '\n')"
      else
        set_key "$MAILHOG" auth x
      fi
      unset NEWVAL LINE
      APPLY_MAILHOG=1 ;;
  esac
done

say "applying the secrets"
run kubectl apply -n "$NS" -f "$HUB"
[ $APPLY_RSS = 1 ] && run kubectl apply -f "$RSS"
[ $APPLY_MAILHOG = 1 ] && run kubectl apply -n "$NS" -f "$MAILHOG"
if [ $RESTART_WEB = 1 ]; then
  say "restarting the web pods with the new values"
  run kubectl rollout restart deployment/bacon8-web -n "$NS"
  run kubectl rollout status deployment/bacon8-web -n "$NS" --timeout=300s
fi
say "done. Check the site, sign in, then delete $BACKUP."
[ $APPLY_RSS = 1 ] && say "RaysSpaceSim world servers and Holo-sims read the key when they start: restart the running ones."
exit 0

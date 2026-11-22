Moved word for word from BACON8.md (§17) on 2026-11-19; BACON8.md keeps a short summary and links here.

## 17. Rotating secrets

Written 2026-11-04 (owner: "I need a good pw and key rotation strategy including commands to run"),
after a cloud working copy of the secrets files was made by mistake and deleted unread. No secret's
value appears in this file or in the repo; the secrets files are gitignored (§6).

**When:** right away after any exposure (a file copied somewhere it shouldn't be, a laptop lost, a
helper or contractor leaving, a key pasted into a chat or log); otherwise on the schedule below.
Rotate one group at a time and check the site between groups, so a broken step has one cause.

**How:** `scripts/security/rotate-secrets.sh`, from the repo root in Git Bash with kubectl on the
production cluster. It backs the secrets files up to `tmp/secrets-backup/<time>/` (gitignored), makes
new values with `openssl rand`, writes them into the files without printing them, applies them and
restarts `bacon8-web`. Values from a provider are typed in (hidden, twice), never on the command line.
Always `--dry-run` first.

| Secret | What changing it costs | How often | How |
|---|---|---|---|
| Stripe secret key, webhook signing secret | nothing for buyers if done in order | after exposure; yearly | Stripe dashboard: Developers → API keys → **Roll key** (choose an expiry of an hour or so for the old one), and Webhooks → the endpoint → **Roll secret**; then `rotate-secrets.sh stripe`. |
| `GAMES_SERVER_API_KEY` | RaysSpaceSim world servers fail until restarted with the new key | after exposure; every 6 months | `rotate-secrets.sh games-key` (hub and RaysSpaceSim secret together), then restart the world servers. |
| `DB_PASSWORD` | a few seconds of failed queries while the pods restart | after exposure; yearly | `rotate-secrets.sh db`: `ALTER ROLE` in Postgres through `kubectl exec`, then the secret. Postgres's own data volume keeps working. |
| `GUARDIAN_SECRET_KEY` | game clients and launchers sign in again | after exposure; yearly | `rotate-secrets.sh tokens` |
| `SECRET_KEY_BASE`, `LIVE_VIEW_SIGNING_SALT` | everyone is signed out; password-reset and confirmation links already sent stop working | after exposure only (or yearly, at a quiet hour) | `rotate-secrets.sh app` |
| `SMTP_PASS` | mail fails between the two steps | after exposure; when the provider asks | change it at the mail provider, then `rotate-secrets.sh smtp` |
| Mailhog page login | — | after exposure; yearly | `rotate-secrets.sh mailhog` (uses `htpasswd`, or a throwaway `httpd` container if it isn't installed) |
| `VAPID_*` (Web Push) | every phone and browser has to turn notifications on again | **only if the private key leaked** | `mix bacon8.gen.vapid` (§16) and paste both halves into the secret; then tell people to re-enable notifications. |
| Cloudflare tunnel token (§18) | the tunnel drops until the new token is in | after exposure | Zero Trust → the tunnel → Refresh token; `kubectl delete secret cloudflared-token -n bacon8`, re-create it (k3s/cloudflared/README.md step 2), `kubectl rollout restart deployment/cloudflared -n bacon8`. |
| Feedback runner token, any other API tokens | the runner stops until updated | after exposure | make a new one where it was issued, revoke the old one, update where it's used. |
| Admin accounts' passwords | — | after exposure; whenever someone leaves | `/forgot-password` or the profile page; long and unique, from a password manager. |
| GitHub, Cloudflare, registrar, Stripe and email *accounts* | — | check yearly | unique passwords in a password manager, two-factor on (an app or a security key, not SMS), recovery codes kept offline. These protect everything above. |

A suggested order after an exposure: Stripe, games key, database, tokens, app secrets, SMTP, Mailhog.
Each line is one command group:

```sh
scripts/security/rotate-secrets.sh --dry-run all stripe smtp mailhog   # read what it will do
scripts/security/rotate-secrets.sh stripe        # after rolling both in the Stripe dashboard
scripts/security/rotate-secrets.sh games-key     # then restart RaysSpaceSim's world servers
scripts/security/rotate-secrets.sh db
scripts/security/rotate-secrets.sh tokens
scripts/security/rotate-secrets.sh app           # signs everyone out
scripts/security/rotate-secrets.sh smtp mailhog  # after changing the mail password at the provider
kubectl get pods -n bacon8                       # all Running; then sign in, buy nothing, send a test mail
```

When the site works: delete `tmp/secrets-backup/` (it holds the old values), and in Stripe make sure
the old key has expired. If a step goes wrong, copy the file back from the backup, `kubectl apply` it,
and restart (`kubectl rollout restart deployment/bacon8-web -n bacon8`); for `db`, the old password must
also go back into Postgres (`ALTER ROLE`), since the script changed it there first.

---


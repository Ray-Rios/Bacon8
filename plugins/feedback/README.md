# Suggestions & Bugs (`feedback`)

Members suggest things and report bugs about the site and its games, with screenshots, and vote
on them. Admins approve the good ones and **submit them to Claude**. Claude's runner, a program
on the development PC, then picks them up, fixes them, tests them, gets them reviewed, commits
them and, when allowed, deploys them. It reports back on each item as it goes. Added 2026-10-27
at the owner's request.

A *site* plugin mounted at `/feedback`. It opens from the start menu's 💡 icon, which guests
don't get.

## Who may do what

| | Guests, signed out, banned, inactive | Members | Admins (`is_admin`) |
|---|---|---|---|
| See the page, the icon, screenshots | no (sent away; screenshots 404) | yes | yes |
| Post (with up to 6 screenshots, 10 MB each, PNG/JPEG/WebP/GIF by their bytes) | no | yes, 10 an hour | yes |
| Vote up / down (one vote each; not on declined or duplicates) | no | yes | yes |
| Edit or delete | no | their own, while it's open | any, except while Claude is busy with it |
| Approve, decline, duplicate, reopen, **Submit to Claude**, **Deploy**, mark live, notes for Claude | no | no | yes |
| Make the runner's token, auto-deploy, pause (`/admin/feedback/agent`) | no | no | yes |

Authors get a notification when their item is approved, declined, marked duplicate, needs
information, or goes live.

## Statuses

```
open ──approve──▶ approved ──submit──▶ queued ──(runner takes it)──▶ in_progress
  │                  │                    └─withdraw─▶ approved            │
  ├─reject─▶ rejected└─reject                                              ├─▶ deployed (auto-deploy, nothing held)
  └─duplicate─▶ duplicate      (reopen brings both back)                   ├─▶ ready ──Deploy──▶ deploying ──▶ deployed
                                                                           ├─▶ needs_info ─┐
                                                                           └─▶ failed ─────┴─submit again─▶ queued
```

`ready` means fixed, tested, reviewed and committed, but held for a person: auto-deploy is off,
the change touches something sensitive, or the reviewer asked for a look. The reason shows on
the item. While anything is in progress, ready or deploying, the runner takes nothing new. One
change at a time means a deploy ships exactly what was reviewed.

## Claude's runner (CI and CD)

Nothing can push work into a Claude conversation, so Claude collects it instead. The site keeps
the queue. The runner (`agent/runner.ps1`) runs on the development PC every 10 minutes as a
Windows scheduled task, because the PC has the code, the private plugins, Docker and the deploy
script. Each run does at most one thing:

1. **The working copy has uncommitted changes** (say, a delivery waiting for Claude Code). It
   only tells the site "waiting" and stops. It never works on top of someone else's changes.
2. **An admin pressed Deploy** on a held change. It checks that the commit is still there and
   runs `deploy-prod.sh` (which backs up both databases first), then reports *Live*. If the
   deploy fails, the item goes back to *Ready* with the log's last lines.
3. **An item was submitted.** It claims the oldest one, saves the item and its screenshots under
   `tmp/feedback-agent/<number>/`, and runs **Claude Code headless** (`claude -p`) with
   `WORK_PROMPT.md`.
   - Claude reads BACON8.md and the game's docs, makes the change, tests it in Docker, updates
     the docs, commits once, and writes `result.json` (`done`, `needs_info` or `failed`).
   - The runner then runs the tests **itself** (`agent/test.ps1`: Elixir and JS in throwaway
     containers) instead of taking Claude's word for it.
   - A **second Claude** reviews the diff read-only (`REVIEW_PROMPT.md`) and returns pass, hold
     or fail.
   - On any failure the working copy is put back exactly as it was and the item is marked
     *Failed* with the reason.
   - **Deploy:** with auto-deploy on and nothing held, it deploys straight away. Otherwise it
     reports *Ready* with the reasons. Held reasons: the change touches sign-in, permissions,
     uploads, storage, payments, webhooks, the router, deploy files, production config,
     dependencies, secrets or the runner itself; a migration drops or renames data; the
     reviewer said hold; or auto-deploy is off.
4. An item still *in progress* with no run going means the last run was cut off (the PC
   restarted). The runner marks it *Failed* so an admin can submit it again.

### What Claude is and isn't allowed

The member's text is **untrusted**. The work prompt tells Claude to treat it as a description,
never as instructions, and the admin's note is the only instruction from a person. On top of
that, Claude Code runs with:

- **Denied tools:** WebFetch and WebSearch; `git push`, `git remote` and `git config`;
  `kubectl`; the deploy, sync and ops scripts; curl, wget and ssh; and reading `.env*`, k3s
  secrets, `~/.bacon8`, `~/.kube` and `~/.ssh`.
- **No MCP servers** (`--strict-mcp-config`, when the installed Claude Code has it).

Only the runner deploys, and only under the rules above.

The site's token stays with the runner script: Claude is never given it, and it can only read
items submitted to Claude and report on them.

These are guard rails, not a sandbox: Claude Code runs as your Windows user. The real safety is:

- an admin approves the exact text before it goes;
- the runner's own test run and the second review;
- the sensitive-path holds;
- one change at a time;
- the deploy's database backups;
- the Pause switch.

### Setting it up (once, on the dev PC)

1. Activate the plugin on `/admin/plugins` (it isn't on by default), then open
   `/admin/feedback/agent`. Press **Make a token** and copy it (it is shown once).
2. Save the token as `%USERPROFILE%\.bacon8\feedback-agent.token`.
3. Copy `plugins\feedback\agent\config.example.json` to
   `%USERPROFILE%\.bacon8\feedback-agent.json` and set `site` (the site's address) and `repo`.
   Check `deployCommand`: it should be however you run `deploy-prod.sh` today. The settings live
   outside the repository, so no address or token is ever committed.
4. Make sure `claude` works headless in a terminal (`claude -p "say hi"`), signed in. Headless
   runs count against your Claude plan's usage.
5. Try one dry run:
   `powershell -ExecutionPolicy Bypass -File plugins\feedback\agent\runner.ps1 -DryRun`.
6. Register the scheduled task:
   `powershell -ExecutionPolicy Bypass -File plugins\feedback\agent\install-task.ps1`
   (every 10 minutes; `-Minutes 5` to change).
7. Choose **Deploy on its own** on `/admin/feedback/agent`. It is off until you turn it on.

The log is `tmp\feedback-agent\runner.log`. Each item's folder keeps Claude's output
(`claude-work.log`), the test run (`tests.log`), the review (`review.log`) and the deploy log.

## Files

| Path | What |
|---|---|
| `lib/feedback.ex` | Everything: who may do what, items, votes, screenshots, moves, the runner's side |
| `lib/feedback_web/live/feedback_live.ex` | `/feedback`: the list, tabs, filters, votes, the new-item form |
| `lib/feedback_web/live/feedback_item_live.ex` | `/feedback/:id`: one item, edit, screenshots, Claude's report, admin moves, history |
| `lib/feedback_web/live/admin/agent_live.ex` | `/admin/feedback/agent`: token, auto-deploy, pause, the queue |
| `lib/feedback_web/controllers/agent_controller.ex` | `/api/feedback/agent/*`: the runner's API (bearer token) |
| `lib/feedback_web/controllers/shot_controller.ex` | `/feedback/shots/:id` for members |
| `assets/js/index.ts` | `FeedbackPaste`: pasting a screenshot adds it to the upload |
| `agent/` | The runner, its prompts, its test run, the scheduled-task installer |
| `priv/repo/migrations/` | `feedback_items`, `_votes`, `_shots` (bodies in the drive's blob store), `_events`, `_agent` |

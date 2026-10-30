<#
  Claude's runner for Suggestions & Bugs (plugins/feedback/agent/README.md).

  Run by a Windows scheduled task every few minutes (install-task.ps1). Each run does at most one
  thing, then exits:

    * the working copy has uncommitted changes      -> says so to the site and stops (it never
                                                       works on top of someone else's changes)
    * an admin pressed Deploy on a held change      -> deploys it, reports live (or back to ready)
    * the last run stopped part way (in progress)   -> reports it failed, so an admin can resubmit
    * a change is waiting for Deploy                -> nothing (one change at a time)
    * an item was submitted to Claude               -> takes it: Claude Code fixes it and commits;
                                                       this script runs the tests itself, has a
                                                       second Claude review the diff, and either
                                                       deploys (auto-deploy on, nothing held) or
                                                       reports it ready for Deploy. Any failure
                                                       puts the working copy back as it was.

  The site's token is read by this script only and never shown to Claude. Settings:
  %USERPROFILE%\.bacon8\feedback-agent.json (see config.example.json); nothing about this PC or
  the site lives in the repository.
#>
[CmdletBinding()]
param(
  [string]$Config = (Join-Path $env:USERPROFILE ".bacon8\feedback-agent.json"),
  # Do everything except calling Claude and deploying: prints what it would do. For checking a setup.
  [switch]$DryRun
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0

# ------------------------------------------------------------------ settings

if (-not (Test-Path $Config)) { throw "No settings file at $Config. Copy plugins\feedback\agent\config.example.json there and fill it in." }
$cfg = Get-Content $Config -Raw -Encoding UTF8 | ConvertFrom-Json

function Setting($name, $default) {
  if ($cfg.PSObject.Properties.Name -contains $name -and $null -ne $cfg.$name -and "$($cfg.$name)" -ne "") { return $cfg.$name }
  return $default
}

$Site       = ([string](Setting "site" "")).TrimEnd("/")
$Repo       = [string](Setting "repo" "C:\Bacon8")
$TokenFile  = [Environment]::ExpandEnvironmentVariables([string](Setting "tokenFile" "%USERPROFILE%\.bacon8\feedback-agent.token"))
$ClaudeExe  = [string](Setting "claude" "claude")
$Model      = [string](Setting "model" "")
$WorkMin    = [int](Setting "workMinutes" 90)
$ReviewMin  = [int](Setting "reviewMinutes" 20)
$TestCmd    = [string](Setting "testCommand" "powershell -NoProfile -ExecutionPolicy Bypass -File plugins\feedback\agent\test.ps1")
$DeployCmd  = [string](Setting "deployCommand" "`"C:\Program Files\Git\bin\bash.exe`" -lc ./scripts/deploy-prod.sh")
$DeployMin  = [int](Setting "deployMinutes" 45)

if ($Site -eq "") { throw "Set `"site`" in $Config (the site's address, e.g. https://example.org)." }
if (-not (Test-Path $TokenFile)) { throw "No token file at $TokenFile. Make a token on /admin/feedback/agent and save it there." }
$Token = (Get-Content $TokenFile -Raw).Trim()

$AgentDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$WorkRoot = Join-Path $Repo "tmp\feedback-agent"
New-Item -ItemType Directory -Force -Path $WorkRoot | Out-Null
$LogFile = Join-Path $WorkRoot "runner.log"

function Log($msg) {
  $line = "{0}  {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $msg
  Add-Content -Path $LogFile -Value $line -Encoding UTF8
  Write-Host $line
}

# ------------------------------------------------------------------ one run at a time

$Lock = Join-Path $WorkRoot "runner.lock"
if (Test-Path $Lock) {
  $age = (Get-Date) - (Get-Item $Lock).LastWriteTime
  if ($age.TotalMinutes -lt ($WorkMin + $ReviewMin + $DeployMin + 30)) { Write-Host "Another run is going (lock $([int]$age.TotalMinutes) min old)."; exit 0 }
  Log "Removing a stale lock ($([int]$age.TotalMinutes) min old)."
}
Set-Content -Path $Lock -Value $PID

# ------------------------------------------------------------------ the site

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Api($method, $path, $body = $null) {
  $headers = @{ Authorization = "Bearer $Token"; Accept = "application/json" }
  $uri = $Site + $path
  if ($null -ne $body) {
    $json = $body | ConvertTo-Json -Depth 6
    return Invoke-RestMethod -Method $method -Uri $uri -Headers $headers -ContentType "application/json; charset=utf-8" -Body ([Text.Encoding]::UTF8.GetBytes($json)) -TimeoutSec 60
  }
  return Invoke-RestMethod -Method $method -Uri $uri -Headers $headers -TimeoutSec 60
}

function Report($item, $status, $summary = $null, $commit = $null, $hold = $null, $note = $null) {
  $body = @{ status = $status }
  if ($summary) { $body.summary = Clip $summary 20000 }
  if ($commit) { $body.commit = $commit }
  if ($hold) { $body.hold_reason = Clip $hold 2000 }
  if ($note) { $body.note = Clip $note 2000 }
  if ($DryRun) { Log "[dry run] would report #$($item.number) -> $status"; return }
  $r = Api "Post" "/api/feedback/agent/items/$($item.id)/report" $body
  Log "Reported #$($item.number): $status"
  return $r
}

# UTF-8 without a byte-order mark (Windows PowerShell's -Encoding UTF8 writes one).
function WriteText($path, $text) { [IO.File]::WriteAllText($path, [string]$text, (New-Object Text.UTF8Encoding($false))) }

# A field of a parsed JSON object, or $default when it isn't there (strict mode would throw).
function Prop($obj, $name, $default = $null) {
  if ($null -ne $obj -and $obj.PSObject.Properties.Name -contains $name) { return $obj.$name }
  return $default
}

function Clip($s, $n) { $s = [string]$s; if ($s.Length -gt $n) { return $s.Substring(0, $n) + "`n[...cut]" } return $s }
function Tail($s, $lines = 60) { return (([string]$s) -split "`r?`n" | Select-Object -Last $lines) -join "`n" }

# ------------------------------------------------------------------ git

function GitOut([string[]]$gitArgs) {
  $out = & git -C $Repo --no-optional-locks @gitArgs 2>&1
  if ($LASTEXITCODE -ne 0) { throw "git $($gitArgs -join ' ') failed: $out" }
  return ($out -join "`n").Trim()
}

function Dirty { return (GitOut @("status", "--porcelain")) -ne "" }

function PutBack($base) {
  # The tree was clean when the run started, so this returns it exactly to that state:
  # Claude's commits and edits go, ignored files (deps, _build, tmp) stay.
  & git -C $Repo reset --hard $base 2>&1 | Out-Null
  & git -C $Repo clean -fd 2>&1 | Out-Null
  Log "Working copy put back to $($base.Substring(0, 10))."
}

# ------------------------------------------------------------------ running things

# Runs a command line in the repo with a time limit; stdin from a file (or none). Returns
# @{ code; out } (stdout and stderr together).
function Run($commandLine, $minutes, $stdinFile = $null) {
  $psi = New-Object Diagnostics.ProcessStartInfo
  $psi.FileName = "cmd.exe"
  $inner = $commandLine
  if ($stdinFile) { $inner = "$commandLine < `"$stdinFile`"" }
  $psi.Arguments = "/d /s /c `"$inner 2>&1`""
  $psi.WorkingDirectory = $Repo
  $psi.UseShellExecute = $false
  $psi.RedirectStandardOutput = $true
  $psi.StandardOutputEncoding = [Text.Encoding]::UTF8
  $psi.CreateNoWindow = $true
  $p = [Diagnostics.Process]::Start($psi)
  $task = $p.StandardOutput.ReadToEndAsync()
  if (-not $p.WaitForExit($minutes * 60 * 1000)) {
    & taskkill /PID $p.Id /T /F 2>&1 | Out-Null
    return @{ code = -1; out = (Clip $task.Result 200000) + "`n[timed out after $minutes minutes]" }
  }
  $p.WaitForExit()
  return @{ code = $p.ExitCode; out = $task.Result }
}

$ClaudeHelp = ""
function ClaudeSupports($flag) {
  if ($script:ClaudeHelp -eq "") { $script:ClaudeHelp = (Run "`"$ClaudeExe`" --help" 2).out }
  return $script:ClaudeHelp -match [regex]::Escape($flag)
}

# Claude Code, headless, with the prompt on stdin. $tools: what it may use without asking (in
# headless mode anything else is refused). Never the network tools, never deploying or pushing.
function Claude($promptFile, $minutes, [string[]]$allowed, [string[]]$denied, $maxTurns) {
  $parts = @("`"$ClaudeExe`"", "-p", "--output-format", "text", "--permission-mode", "acceptEdits")
  # Claude Code 2.1.199 does not list --max-turns in its --help: pass it only when listed.
  if (ClaudeSupports "--max-turns") { $parts += @("--max-turns", "$maxTurns") }
  if ($Model -ne "") { $parts += @("--model", $Model) }
  $parts += "--allowedTools"; $parts += ($allowed | ForEach-Object { "`"$_`"" })
  $parts += "--disallowedTools"; $parts += ($denied | ForEach-Object { "`"$_`"" })
  if (ClaudeSupports "--strict-mcp-config") {
    # No MCP servers (the Unreal editor, Blender, Docker's browser): plain files and a shell only.
    $empty = Join-Path $WorkRoot "no-mcp.json"
    Set-Content -Path $empty -Value '{"mcpServers":{}}' -Encoding ASCII
    $parts += @("--strict-mcp-config", "--mcp-config", "`"$empty`"")
  }
  return Run ($parts -join " ") $minutes $promptFile
}

$NeverAllowed = @(
  "WebFetch", "WebSearch",
  "Bash(git push:*)", "Bash(git remote:*)", "Bash(git config:*)",
  "Bash(kubectl:*)", "Bash(helm:*)", "Bash(k3s:*)",
  "Bash(./scripts/deploy-prod.sh:*)", "Bash(bash scripts/deploy-prod.sh:*)", "Bash(sh scripts/deploy-prod.sh:*)", "Bash(./scripts/deploy-dev.sh:*)",
  "Bash(./scripts/sync-models-to-k8s.sh:*)", "Bash(./scripts/sync-uploads-to-k8s.sh:*)", "Bash(./scripts/postgres-ops.sh:*)", "Bash(./scripts/redis-ops.sh:*)",
  "Bash(curl:*)", "Bash(wget:*)", "Bash(ssh:*)", "Bash(scp:*)", "Bash(Invoke-WebRequest:*)", "Bash(Invoke-RestMethod:*)",
  "Read(./.env*)", "Read(./k3s/**/*secret*)", "Read(~/.bacon8/**)", "Read(~/.kube/**)", "Read(~/.ssh/**)",
  # git hooks run later, when the owner commits; Claude's own settings and the token folder are not its to edit
  "Edit(./.git/**)", "Write(./.git/**)", "Edit(./.claude/**)", "Write(./.claude/**)", "Edit(~/.bacon8/**)", "Write(~/.bacon8/**)", "Edit(~/.claude/**)", "Write(~/.claude/**)"
)

# ------------------------------------------------------------------ what's sensitive

# A change touching any of these is never deployed on its own (BACON8.md: security-sensitive
# changes get a second reviewer; deploy files and secrets are the owner's).
$Sensitive = @(
  @{ re = '(^|/)(auth|accounts|security|permissions)(/|\.ex$)|user_auth|guardian|safe_path|uploads_guard|plugs/'; why = "sign-in, permissions or request plumbing" },
  @{ re = 'upload|storage|drive/'; why = "file uploads or storage" },
  @{ re = 'bacon_store/|payment|stripe|wallet|webhook'; why = "payments or webhooks" },
  @{ re = '^k3s/|^Dockerfile|deploy|\.sh$|^config/(prod|runtime)\.exs$|^\.github/'; why = "deploy files or production config" },
  @{ re = '^mix\.(exs|lock)$|package(-lock)?\.json$'; why = "dependencies" },
  @{ re = 'secret|\.env'; why = "secrets" },
  @{ re = '^plugins/feedback/agent/'; why = "the runner itself" },
  @{ re = '^\.claude/|(^|/)CLAUDE\.md$|^\.gitignore$|^\.git'; why = "Claude's own instructions or git settings" },
  @{ re = 'router\.ex$|endpoint\.ex$'; why = "the router or endpoint" }
)

function SensitiveReasons($files) {
  $why = @()
  foreach ($f in $files) {
    foreach ($s in $Sensitive) { if ($f -match $s.re -and $why -notcontains $s.why) { $why += $s.why } }
  }
  return $why
}

function DropsData($base) {
  $diff = GitOut @("diff", "$base..HEAD", "--", "*migrations*")
  return $diff -match '(?im)^\+.*\b(drop|remove|rename|delete_all|truncate)\b'
}

# ------------------------------------------------------------------ steps

function DoDeploy($item, $reason) {
  if (Dirty) { Report $item "ready" $null $null "The working copy has uncommitted changes; deploy after they're committed." "Deploy waited: uncommitted changes on the PC."; return }
  if (Prop $item "commit") {
    & git -C $Repo merge-base --is-ancestor $item.commit HEAD 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { Report $item "failed" "Commit $($item.commit) isn't in the working copy any more, so there's nothing to deploy." $null $null; return }
  }
  if ($DryRun) { Log "[dry run] would deploy #$($item.number) ($reason)"; return }
  Log "Deploying #$($item.number) ($reason)..."
  $r = Run $DeployCmd $DeployMin
  WriteText (Join-Path $WorkRoot "deploy-$($item.number).log") $r.out
  if ($r.code -eq 0) {
    Report $item "deployed" $null $null $null "Deployed ($reason)."
  } else {
    Report $item "ready" $null $null "The deploy failed (exit $($r.code)); nothing else changed. Last lines:`n$(Tail $r.out 25)" "Deploy failed."
  }
}

function DoWork($item, $autoDeploy) {
  $base = GitOut @("rev-parse", "HEAD")
  try {
    DoWorkInner $item $autoDeploy
  } catch {
    Log "Error while working on #$($item.number): $($_.Exception.Message)"
    if ((GitOut @("rev-parse", "HEAD")) -ne $base -or (Dirty)) { PutBack $base }
    try { Report $item "failed" "The runner hit an error and put the working copy back: $($_.Exception.Message)" } catch { Log "Couldn't report: $($_.Exception.Message)" }
  }
}

function DoWorkInner($item, $autoDeploy) {
  $dir = Join-Path $WorkRoot ("{0}" -f $item.number)
  if (Test-Path $dir) { Remove-Item -Recurse -Force $dir }
  New-Item -ItemType Directory -Force -Path $dir | Out-Null

  # The item and its screenshots, for Claude to read.
  WriteText (Join-Path $dir "item.json") ($item | ConvertTo-Json -Depth 6)
  $n = 0
  foreach ($shot in $item.shots) {
    $n++
    $ext = switch ($shot.content_type) { "image/jpeg" { "jpg" } "image/webp" { "webp" } "image/gif" { "gif" } default { "png" } }
    Invoke-WebRequest -Uri ($Site + $shot.url) -Headers @{ Authorization = "Bearer $Token" } -OutFile (Join-Path $dir ("screenshot-$n.$ext")) -UseBasicParsing -TimeoutSec 120 | Out-Null
  }

  $base = GitOut @("rev-parse", "HEAD")
  $rel = "tmp/feedback-agent/$($item.number)"
  $prompt = (Get-Content (Join-Path $AgentDir "WORK_PROMPT.md") -Raw -Encoding UTF8).Replace("{{DIR}}", $rel).Replace("{{NUMBER}}", "$($item.number)").Replace("{{TITLE}}", $item.title)
  $promptFile = Join-Path $dir "prompt.md"
  WriteText $promptFile ($prompt)

  if ($DryRun) { Log "[dry run] would have Claude work on #$($item.number) with $n screenshot(s)"; return }

  Log "Claude is working on #$($item.number): $($item.title)"
  $work = Claude $promptFile $WorkMin @("Read", "Edit", "Write", "Glob", "Grep", "Bash", "TodoWrite") $NeverAllowed 400
  WriteText (Join-Path $dir "claude-work.log") ($work.out)

  $resultFile = Join-Path $dir "result.json"
  $result = $null
  if (Test-Path $resultFile) { try { $result = Get-Content $resultFile -Raw -Encoding UTF8 | ConvertFrom-Json } catch { $result = $null } }
  if ($null -eq $result) {
    PutBack $base
    Report $item "failed" "Claude stopped without finishing: it wrote no result.json (exit $($work.code)), so nothing was committed and the working copy was put back. This is not a retry in progress. What Claude last said:`n$(Tail $work.out 30)`n`nSubmit it again to try again."
    return
  }

  if ((Prop $result "outcome") -ne "done") {
    PutBack $base
    $status = if ((Prop $result "outcome") -eq "needs_info") { "needs_info" } else { "failed" }
    Report $item $status (Prop $result "summary" "")
    return
  }

  $commits = [int](GitOut @("rev-list", "--count", "$base..HEAD"))
  if ($commits -lt 1 -or (Dirty)) {
    PutBack $base
    Report $item "failed" ("Claude said it was done but " + $(if ($commits -lt 1) { "made no commit" } else { "left changes uncommitted" }) + " (the working copy was put back)" + ". Its summary:`n" + (Prop $result "summary" ""))
    return
  }
  $head = GitOut @("rev-parse", "HEAD")

  # The tests, run here and not taken on Claude's word.
  Log "Running the tests for #$($item.number)..."
  $test = Run $TestCmd 60
  WriteText (Join-Path $dir "tests.log") ($test.out)
  if ($test.code -ne 0) {
    PutBack $base
    Report $item "failed" ("The tests failed after Claude's change, so it was taken back out. Claude's summary:`n" + (Prop $result "summary" "") + "`n`nTest output (last lines):`n" + (Tail $test.out 40))
    return
  }

  # A second Claude, which didn't write it, reviews the diff.
  $diff = GitOut @("diff", "--stat", "$base..HEAD")
  $patch = GitOut @("diff", "$base..HEAD")
  $review = (Get-Content (Join-Path $AgentDir "REVIEW_PROMPT.md") -Raw -Encoding UTF8).Replace("{{DIR}}", $rel)
  $reviewFile = Join-Path $dir "review-prompt.md"
  WriteText $reviewFile (($review + "`n`n## The item`n`n" + ($item | ConvertTo-Json -Depth 6) + "`n`n## Claude's summary`n`n" + (Prop $result "summary" "") + "`n`n## The diff`n`n" + $diff + "`n`n" + (Clip $patch 150000)))
  Log "Second review of #$($item.number)..."
  $rv = Claude $reviewFile $ReviewMin @("Read", "Glob", "Grep") (@("Edit", "Write", "Bash", "NotebookEdit") + $NeverAllowed) 60
  WriteText (Join-Path $dir "review.log") ($rv.out)
  $verdict = "hold"; $vreason = "The review gave no clear verdict."
  $m = [regex]::Matches($rv.out, '\{[^{}]*"verdict"[^{}]*\}')
  if ($m.Count -gt 0) {
    try { $v = $m[$m.Count - 1].Value | ConvertFrom-Json; $verdict = [string](Prop $v "verdict" "hold"); $vreason = [string](Prop $v "reasons" "") } catch { }
  }
  if ($verdict -eq "fail") {
    PutBack $base
    Report $item "failed" ("The second review turned the change down, so it was taken back out:`n" + $vreason + "`n`nClaude's summary:`n" + (Prop $result "summary" ""))
    return
  }

  # Hold back anything sensitive; deploy the rest if allowed.
  $files = (GitOut @("diff", "--name-only", "$base..HEAD")) -split "`n" | Where-Object { $_ -ne "" }
  $holds = @(SensitiveReasons $files)
  if (DropsData $base) { $holds += "a migration that drops or renames data" }
  if ($verdict -ne "pass") { $holds += "the review asked for a person's look: $vreason" }
  if (-not $autoDeploy) { $holds += "auto-deploy is off" }

  $summary = (Prop $result "summary" "") + "`n`nTests passed on the PC. Review: $verdict" + $(if ($vreason) { " ($vreason)" } else { "" }) + "`n`n" + $diff
  if ($holds.Count -gt 0) {
    Report $item "ready" $summary $head ($holds -join "; ")
  } else {
    Report $item "in_progress" $summary $head $null "Tested and reviewed; deploying."
    $item | Add-Member -NotePropertyName commit -NotePropertyValue $head -Force
    DoDeployFromWork $item
  }
}

# Auto-deploy straight after the work (the item is still "in progress").
function DoDeployFromWork($item) {
  Log "Deploying #$($item.number) (auto-deploy)..."
  $r = Run $DeployCmd $DeployMin
  WriteText (Join-Path $WorkRoot "deploy-$($item.number).log") $r.out
  if ($r.code -eq 0) {
    Report $item "deployed" $null $item.commit $null "Deployed by auto-deploy."
  } else {
    Report $item "ready" $null $item.commit "The automatic deploy failed (exit $($r.code)); press Deploy to try again. Last lines:`n$(Tail $r.out 25)" "Auto-deploy failed."
  }
}

# ------------------------------------------------------------------ main

try {
  if (Dirty) {
    $peek = Api "Get" "/api/feedback/agent/next?peek=1&note=$([uri]::EscapeDataString('Waiting: the working copy has uncommitted changes'))"
    if ($peek.action -ne "none") { Log "Not starting ($($peek.action)): the working copy has uncommitted changes." }
    exit 0
  }

  if ($DryRun) {
    # Claims nothing: just shows the settings work and what the next real run would do.
    $peek = Api "Get" "/api/feedback/agent/next?peek=1&note=$([uri]::EscapeDataString('Dry run'))"
    $what = if ($peek.action -eq "queued") { "take the next of $($peek.waiting) submitted item(s)" } elseif ($peek.PSObject.Properties.Name -contains "item") { "$($peek.action): #$($peek.item.number) $($peek.item.title)" } else { $peek.action }
    Log "Dry run: the site answered; claude is '$ClaudeExe'; auto-deploy $($peek.auto_deploy). Next run would: $what"
    exit 0
  }

  $next = Api "Get" "/api/feedback/agent/next?note=$([uri]::EscapeDataString('Checking for work'))"
  switch ($next.action) {
    "none" { exit 0 }
    "paused" { exit 0 }
    "wait" { exit 0 }
    "queued" { exit 0 }
    "deploy" { DoDeploy $next.item "an admin pressed Deploy" }
    "resume" { Report $next.item "failed" "The runner stopped part way through (the PC restarted, or the run was cut off). Submit it again to retry." }
    "work" { DoWork $next.item ([bool]$next.auto_deploy) }
    default { Log "Unknown action '$($next.action)'." }
  }
} catch {
  Log "Error: $($_.Exception.Message)"
  exit 1
} finally {
  Remove-Item -Force $Lock -ErrorAction SilentlyContinue
}

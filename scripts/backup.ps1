<#
.SYNOPSIS
  Backs up everything of Bacon8 that GitHub does not hold, to another drive.

.DESCRIPTION
  GitHub (origin) holds the code. This copies the rest, which lives only on this PC:

    - fresh dumps of the production databases (production runs on this PC's Kubernetes;
      deploy-prod.sh restores a fresh install from the newest dump in backups\)
    - backups\        every database dump and certificate backup so far
    - uploads\        files people uploaded
    - priv\static\models\   the game's built models
    - k3s secrets, .env files, priv\cert   (never in Git, by design)
    - library\        the art pipeline: its sources (its scripts are also on GitHub, Secret_Bacon) (textures and makehuman only
                      with -IncludeDownloads: they are several GB and can be downloaded again)
    - plugins\rays_space_sim\unreal\   the Unreal project: its own repository plus its Content (minus Unreal's caches)
    - handoff\, docs\, brand\ and every other file in the folder

  It leaves out what can be rebuilt: _build, deps, node_modules, priv\static\assets, tmp,
  editor caches (.vs) and Unreal's Binaries, Intermediate, Saved and DerivedDataCache. Leaving those out is also what
  makes it work: Explorer gives up on node_modules' very long paths and hundreds of thousands
  of small files ("an unexpected error"). Robocopy handles long paths and retries.

  It only adds and updates files in the backup, never deletes, so a damaged source can't wipe
  a good backup. A second pass then checks that nothing was left behind.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File C:\Bacon8\scripts\backup.ps1 -Destination D:\Backups

.EXAMPLE
  # every night at 3:10 (run once, in an administrator PowerShell)
  schtasks /Create /SC DAILY /ST 03:10 /TN "Bacon8 backup" /TR "powershell -ExecutionPolicy Bypass -File C:\Bacon8\scripts\backup.ps1 -Destination D:\Backups"
#>
param(
  [Parameter(Mandatory = $true)][string]$Destination,
  [string]$Source = "C:\Bacon8",
  [switch]$SkipDatabase,
  [switch]$IncludeDownloads
)

$ErrorActionPreference = "Stop"
$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$target = Join-Path $Destination "Bacon8"
$logDir = Join-Path $Destination "Bacon8_backup_logs"
New-Item -ItemType Directory -Force -Path $target, $logDir | Out-Null
$log = Join-Path $logDir "backup_$stamp.log"
$problems = @()

function Say($text, $color = "Gray") { Write-Host $text -ForegroundColor $color; Add-Content -Path $log -Value $text }

Say "Bacon8 backup ${stamp}: $Source -> $target" "Cyan"

# ---------------------------------------------------------------- 1. the databases
if (-not $SkipDatabase) {
  $pod = ""
  try { $pod = (kubectl get pods -n bacon8 -l app=postgres -o jsonpath="{.items[0].metadata.name}" 2>$null) } catch {}
  if (-not $pod) {
    $problems += "Production database not reachable (kubectl, namespace bacon8): no fresh dump. The dumps already in backups\ are still copied."
  } else {
    $pw = if ($env:PGPASSWORD) { $env:PGPASSWORD } else { "postgres" }
    foreach ($db in @(@("bacon8_prod", "db_backup"), @("bacon8_games_prod", "games_backup"))) {
      $out = Join-Path $Source "backups\$($db[1])_$stamp.sql"
      # cmd's redirection writes the dump byte for byte (PowerShell's would re-encode it)
      cmd /c "kubectl exec -n bacon8 $pod -- env PGPASSWORD=$pw pg_dump -U postgres -h db -d $($db[0]) > `"$out.part`""
      if ($LASTEXITCODE -eq 0 -and (Test-Path "$out.part") -and (Get-Item "$out.part").Length -gt 1000) {
        Move-Item "$out.part" $out -Force
        Say ("Dumped {0}: {1:N0} KB" -f $db[0], ((Get-Item $out).Length / 1KB)) "Green"
      } else {
        Remove-Item "$out.part" -ErrorAction SilentlyContinue
        $problems += "Dump of $($db[0]) failed."
      }
    }
  }
}

# ---------------------------------------------------------------- 2. the files
$skipDirs = @(
  "$Source\_build", "$Source\deps", "$Source\assets\node_modules", "$Source\priv\static\assets", "$Source\tmp",
  "$Source\plugins\rays_space_sim\unreal\Binaries", "$Source\plugins\rays_space_sim\unreal\Intermediate", "$Source\plugins\rays_space_sim\unreal\Saved",
  "$Source\plugins\rays_space_sim\unreal\DerivedDataCache", ".elixir_ls", "node_modules",
  # editor caches, locked while the editor is open (Visual Studio's search index)
  ".vs", "__pycache__"
)
if (-not $IncludeDownloads) { $skipDirs += @("$Source\library\textures", "$Source\library\makehuman") }

$common = @("/E", "/R:2", "/W:2", "/MT:16", "/XJ", "/FFT", "/NP", "/NDL", "/XD") + $skipDirs
Say "Copying (only new and changed files)..."
& robocopy $Source $target @common "/LOG+:$log" | Out-Null
$code = $LASTEXITCODE
# robocopy: 0-7 = success (1 = files copied), 8 and up = some files could not be copied
if ($code -ge 8) { $problems += "Robocopy could not copy some files (exit $code): see the log, lines with ERROR." }

# ---------------------------------------------------------------- 3. check
Say "Checking that nothing was left behind..."
$check = & robocopy $Source $target @common "/L" "/NJH" "/NFL"
$left = ($check | Select-String -Pattern "^\s+Files\s*:\s*(\d+)\s+(\d+)").Matches | Select-Object -First 1
if ($left -and [int]$left.Groups[2].Value -gt 0) {
  $problems += "$($left.Groups[2].Value) files still differ from the backup after the copy."
}

# what GitHub doesn't have yet, in each repository here
foreach ($repo in @($Source, "$Source\plugins\rays_space_sim", "$Source\plugins\rays_space_sim\unreal", "$Source\library\pipeline\scripts")) {
  if (-not (Test-Path "$repo\.git")) { continue }
  Push-Location $repo
  try {
    $ahead = (git rev-list --count "@{u}..HEAD" 2>$null)
    $dirty = (git status --porcelain 2>$null | Measure-Object).Count
    if ([int]$ahead -gt 0) { $problems += "${repo}: $ahead commit(s) not pushed to GitHub yet: run 'git push' there." }
    if ($dirty -gt 0) { Say "${repo}: $dirty changed or new file(s) not committed (they are in this backup, not on GitHub)." "Yellow" }
  } catch {} finally { Pop-Location }
}
git -C $Source rev-parse HEAD 2>$null | Out-File -Encoding ascii (Join-Path $target "BACKUP_GIT_HEAD.txt")

$size = (Get-ChildItem $target -Recurse -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
Say ("Backup now holds {0:N1} GB in {1}" -f ($size / 1GB), $target)

if ($problems.Count -gt 0) {
  Say "DONE WITH PROBLEMS:" "Red"
  $problems | ForEach-Object { Say "  - $_" "Red" }
  exit 1
}
Say "DONE: backup complete and checked. Log: $log" "Green"
exit 0

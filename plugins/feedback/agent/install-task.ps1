<#
  Registers "Bacon8 Claude runner", a Windows scheduled task that runs runner.ps1 every
  $Minutes minutes while you're signed in (it needs your Docker Desktop, git and Claude Code
  sign-in). Run once, in PowerShell, from the repository:

      powershell -ExecutionPolicy Bypass -File plugins\feedback\agent\install-task.ps1

  Remove it with:  Unregister-ScheduledTask -TaskName "Bacon8 Claude runner"
#>
param([int]$Minutes = 10)

$runner = Join-Path $PSScriptRoot "runner.ps1"
$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$runner`""
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes $Minutes) -RepetitionDuration (New-TimeSpan -Days 3650)
$settings = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Hours 4) -AllowStartIfOnBatteries
Register-ScheduledTask -TaskName "Bacon8 Claude runner" -Action $action -Trigger $trigger -Settings $settings -Description "Takes Suggestions & Bugs items submitted to Claude (plugins/feedback/agent/README.md)." -Force | Out-Null
Write-Host "Registered: every $Minutes minutes. Log: tmp\feedback-agent\runner.log"

@echo off
call "%~dp0paths.cmd"
rem Run as administrator (right-click, Run as administrator), with Docker Desktop closed (2026-11-13):
rem shrinks Docker's disk file and sets a fixed 20 GB page file (it takes effect after a restart).
net session >nul 2>&1 || (echo Please right-click this file and choose "Run as administrator". & pause & exit /b 1)
wsl --shutdown
set VHD=%LOCALAPPDATA%\Docker\wsl\disk\docker_data.vhdx
for %%A in ("%VHD%") do echo Docker disk before: %%~zA bytes
(echo select vdisk file="%VHD%"& echo attach vdisk readonly& echo compact vdisk& echo detach vdisk) > "%TEMP%\b8_compact.txt"
diskpart /s "%TEMP%\b8_compact.txt"
for %%A in ("%VHD%") do echo Docker disk after: %%~zA bytes
powershell -NoProfile -Command "$cs = Get-CimInstance Win32_ComputerSystem; Set-CimInstance -InputObject $cs -Property @{AutomaticManagedPagefile=$false}; $pf = Get-CimInstance Win32_PageFileSetting; if (-not $pf) { New-CimInstance -ClassName Win32_PageFileSetting -Property @{Name='C:\pagefile.sys'} | Out-Null; $pf = Get-CimInstance Win32_PageFileSetting }; $pf | Set-CimInstance -Property @{InitialSize=20480; MaximumSize=20480}; Get-CimInstance Win32_PageFileSetting | Format-List Name,InitialSize,MaximumSize"
echo.
echo Done. Restart Windows for the 20 GB page file to take effect.
pause

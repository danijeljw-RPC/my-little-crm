<#
.SYNOPSIS
  Run the Flutter app on a chosen device.

.EXAMPLE
  .\scripts\run.ps1                       # list everything you can run on
  .\scripts\run.ps1 windows               # run there
  .\scripts\run.ps1 chrome
  .\scripts\run.ps1 "swoovr-pixel"        # launches the Android emulator first
  .\scripts\run.ps1 edge --release        # extra args go straight to `flutter run`
#>
param(
  [Parameter(Position = 0)] [string] $Target,
  [Parameter(Position = 1, ValueFromRemainingArguments = $true)] [string[]] $FlutterArgs = @()
)

$ErrorActionPreference = 'Stop'
# flutter prints UTF-8 (the " • " column separators); decode it as such on Windows PowerShell 5.1.
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$Sep = ' ' + [char]0x2022 + ' '
Set-Location (Join-Path $PSScriptRoot '..')

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
  Write-Error 'flutter is not on PATH'
  exit 1
}

$IsMacHost = ($PSVersionTable.PSVersion.Major -ge 6) -and $IsMacOS -and (Get-Command xcrun -ErrorAction SilentlyContinue)

function Get-RunningDevices {
  $json = (flutter devices --machine 2>$null) -join "`n"
  $start = $json.IndexOf('[')
  if ($start -lt 0) { return @() }
  # parentheses force PS 5.1 to enumerate the array instead of passing it as one object
  @(($json.Substring($start) | ConvertFrom-Json) | ForEach-Object {
    [pscustomobject]@{ Name = $_.name; Id = $_.id }
  })
}

function Get-EmulatorIds {
  @(flutter emulators 2>$null | ForEach-Object {
    $parts = $_ -split [regex]::Escape($Sep)
    if ($parts.Count -ge 3 -and $parts[0].Trim() -ne 'Id') { $parts[0].Trim() }
  })
}

function Get-ShutdownSimulators {
  if (-not $IsMacHost) { return @() }
  @(xcrun simctl list devices available 2>$null | ForEach-Object {
    if ($_ -match '^\s+(.+) \(([0-9A-F-]{36})\) \(Shutdown\)') {
      [pscustomobject]@{ Name = $Matches[1]; Id = $Matches[2] }
    }
  })
}

function Find-Running([string] $t) {
  $devices = Get-RunningDevices
  # exact id, then exact name, then substring of name or id
  $hit = $devices | Where-Object { $_.Id -ieq $t } | Select-Object -First 1
  if (-not $hit) { $hit = $devices | Where-Object { $_.Name -ieq $t } | Select-Object -First 1 }
  if (-not $hit) {
    $hit = $devices | Where-Object {
      $_.Name -like "*$t*" -or $_.Id -like "*$t*"
    } | Select-Object -First 1
  }
  if ($hit) { $hit.Id }
}

function Show-Targets {
  Write-Host '== Running / connected devices =='
  foreach ($d in Get-RunningDevices) { Write-Host ('  {0,-34} id: {1}' -f $d.Name, $d.Id) }
  Write-Host "`n== Emulators (launched for you) =="
  $emus = Get-EmulatorIds
  if ($emus.Count) { $emus | ForEach-Object { Write-Host "  $_" } } else { Write-Host '  (none)' }
  if ($IsMacHost) {
    Write-Host "`n== iOS simulators, shut down (booted for you) =="
    $sims = Get-ShutdownSimulators
    if ($sims.Count) { $sims | ForEach-Object { Write-Host "  $($_.Name)" } } else { Write-Host '  (none)' }
  }
  Write-Host "`nUsage: .\scripts\run.ps1 `"<name or id>`" [flutter run args]"
  Write-Host '   eg: .\scripts\run.ps1 windows   .\scripts\run.ps1 chrome   .\scripts\run.ps1 "swoovr-pixel"'
}

function Invoke-FlutterRun([string] $id) {
  Write-Host "-> Running on $id"
  & flutter run -d $id @FlutterArgs
  exit $LASTEXITCODE
}

if (-not $Target) {
  Show-Targets
  exit 0
}

# 1. Already running or connected.
$device = Find-Running $Target
if ($device) { Invoke-FlutterRun $device }

# 2. A shut-down iOS simulator (only when this is run on a Mac).
$sim = Get-ShutdownSimulators | Where-Object { $_.Name -ieq $Target -or $_.Id -ieq $Target } | Select-Object -First 1
if ($sim) {
  Write-Host "-> Booting iOS simulator $($sim.Name)"
  xcrun simctl boot $sim.Id
  open -a Simulator 2>$null; if ($LASTEXITCODE -ne 0) { open -a DeviceHub 2>$null }
  Invoke-FlutterRun $sim.Id
}

# 3. A launchable emulator (Android AVD, or the generic iOS simulator).
$emu = Get-EmulatorIds | Where-Object { $_ -ieq $Target } | Select-Object -First 1
if ($emu) {
  $before = @(Get-RunningDevices | ForEach-Object { $_.Id })
  Write-Host "-> Launching emulator $emu (waiting up to 3 min)..."
  flutter emulators --launch $emu | Out-Null
  $deadline = (Get-Date).AddMinutes(3)
  while ((Get-Date) -lt $deadline) {
    $new = Get-RunningDevices | Where-Object { $before -notcontains $_.Id } | Select-Object -First 1
    if ($new) { Invoke-FlutterRun $new.Id }
    Start-Sleep -Seconds 3
  }
  Write-Error "emulator $emu did not come up in time"
  exit 1
}

Write-Host "error: no device, simulator or emulator matches `"$Target`"`n" -ForegroundColor Red
Show-Targets
exit 1

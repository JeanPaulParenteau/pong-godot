<#
  Launch the Pong CLIENT locally for play-testing.
  (This is NOT the test suite — for that run tests/run-all.ps1.)

  A windowed launch boots straight into the menu:
    Play Online  |  Vs Computer: Easy / Medium / Hard  |  Pong TV (watch live)

  Controls: move the mouse over the window — your paddle follows the pointer.
  Pick a difficulty under "Vs Computer" to play a rally vs the CPU. Solo (and the
  local server) already carry the uncapped ball + escalating shake/confetti; the
  live online server only gets them after a redeploy.

  Examples:
    .\run-local.ps1                 # open the menu, then click a difficulty
    .\run-local.ps1 -Solo           # skip the menu → straight into a Medium vs-CPU match
    .\run-local.ps1 -Solo -Shot 30  # also overwrite user://cap.png every 30 frames (debug)

  Anything after the named switches is forwarded to the game, e.g.:
    .\run-local.ps1 -- --address 127.0.0.1 --port 7777
#>
param(
  [switch]$Solo,
  [int]$Shot = 0,
  [string]$Godot = "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.6.3-stable_win64_console.exe",
  [Parameter(ValueFromRemainingArguments = $true)] [string[]]$Extra
)

$proj = $PSScriptRoot

if (-not (Test-Path $Godot)) {
  Write-Host "Godot 4.6.3 console binary not found at:" -ForegroundColor Red
  Write-Host "  $Godot" -ForegroundColor Red
  Write-Host "Install it (winget install GodotEngine.GodotEngine) or pass the path:" -ForegroundColor Yellow
  Write-Host "  .\run-local.ps1 -Godot 'C:\path\to\Godot_v4.6.3-stable_win64_console.exe'" -ForegroundColor Yellow
  exit 1
}

# Godot only forwards args after a literal `--` to the project (OS.get_cmdline_user_args).
$gameArgs = @()
if ($Solo)      { $gameArgs += '--solo' }
if ($Shot -gt 0) { $gameArgs += @('--shot-interval', "$Shot") }
if ($Extra)     { $gameArgs += $Extra }

$cli = @('--path', $proj)
if ($gameArgs.Count -gt 0) { $cli += '--'; $cli += $gameArgs }

Write-Host "Launching Pong:  $($cli -join ' ')" -ForegroundColor Cyan
& $Godot @cli
exit $LASTEXITCODE

<#
  The full test suite: headless logic tests + the UI-layout smoke. Exits non-zero
  if either fails. Run this (not just run_tests.gd) before shipping — the UI smoke
  guards the "Controls at 0x0 / off-screen" class of bug that unit tests can't see.
#>
param(
  [string]$Godot = "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.6.3-stable_win64_console.exe"
)
$proj = Split-Path $PSScriptRoot -Parent

& $Godot --headless --path $proj --script tests/run_tests.gd
$unit = $LASTEXITCODE
& $Godot --headless --path $proj --script tests/ui_smoke.gd
$ui = $LASTEXITCODE

if ($unit -eq 0 -and $ui -eq 0) {
  Write-Host "ALL SUITES PASSED" -ForegroundColor Green
} else {
  Write-Host "TESTS FAILED (unit=$unit ui=$ui)" -ForegroundColor Red
  exit 1
}

<#
  The full test suite, exits non-zero if anything fails. Run before shipping.
    1. tests/run_tests.gd   — legacy logic harness (being migrated to GdUnit4)
    2. tests/gdunit/        — GdUnit4 suites (logic + the UI-layout guard); NEW
                              tests go here, test-first (see docs/TDD.md)
#>
param(
  [string]$Godot = "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.6.3-stable_win64_console.exe"
)
$proj = Split-Path $PSScriptRoot -Parent

& $Godot --headless --path $proj --script tests/run_tests.gd
$legacy = $LASTEXITCODE
& $Godot --headless --path $proj -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/gdunit
$gdunit = $LASTEXITCODE

if ($legacy -eq 0 -and $gdunit -eq 0) {
  Write-Host "ALL SUITES PASSED" -ForegroundColor Green
} else {
  Write-Host "TESTS FAILED (legacy=$legacy gdunit=$gdunit)" -ForegroundColor Red
  exit 1
}

<#
  The full test suite, exits non-zero if anything fails. Run before shipping.
  Everything is GdUnit4 (tests/gdunit/); new tests go there, test-first
  (see docs/TDD.md). The legacy run_tests.gd harness is fully migrated and gone.
#>
param(
  [string]$Godot = "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.6.3-stable_win64_console.exe"
)
$proj = Split-Path $PSScriptRoot -Parent

& $Godot --headless --path $proj -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/gdunit
if ($LASTEXITCODE -eq 0) {
  Write-Host "ALL SUITES PASSED" -ForegroundColor Green
} else {
  Write-Host "TESTS FAILED" -ForegroundColor Red
  exit 1
}

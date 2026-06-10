<#
  TDD watch mode: re-run the full suite whenever a .gd file under src/ or tests/
  changes. This is the red→green→refactor inner loop — keep it open in a terminal
  while you work. Ctrl+C to stop.
#>
param(
  [string]$Godot = "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.6.3-stable_win64_console.exe"
)
$proj = Split-Path $PSScriptRoot -Parent

function Latest-Change {
  (Get-ChildItem -Path "$proj\src", "$proj\tests" -Recurse -Filter *.gd -File -ErrorAction SilentlyContinue |
    Measure-Object -Property LastWriteTimeUtc -Maximum).Maximum
}

Write-Host "TDD watch: re-running tests on any src/ or tests/ *.gd change (Ctrl+C to stop)..." -ForegroundColor Cyan
$last = $null
while ($true) {
  $cur = Latest-Change
  if ($cur -ne $last) {
    $last = $cur
    Clear-Host
    Write-Host ("--- run @ {0:HH:mm:ss} ---" -f (Get-Date)) -ForegroundColor DarkGray
    & "$PSScriptRoot\run-all.ps1" -Godot $Godot
  }
  Start-Sleep -Milliseconds 700
}

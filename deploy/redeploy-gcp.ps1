<#
  One-command (re)deploy of the Pong (Godot) dedicated server to the GCP VM.

  Exports the Linux server from current code, uploads the single embedded-PCK
  binary, (re)installs the systemd service on port 7778 via gcp-setup.sh, then
  runs a 2-autoclient online smoke against the live server.

  Touches only port 7778 and the pong-godot.service unit. The udp/7778 firewall
  rule is already in place (see DEPLOY.md); the legacy Unity server that once
  shared this VM was retired 2026-06-10.

  Any netcode/sim change must ship the APK AND this server in lockstep, or online
  desyncs (stale server vs current client).

  Usage:  powershell -ExecutionPolicy Bypass -File deploy\redeploy-gcp.ps1
#>
param(
  [string]$Project     = "pong-497801",
  [string]$Zone        = "us-west1-b",
  [string]$Vm          = "pong-server",
  [string]$ProjectPath = "C:\dev\pong_godot",
  [int]$Port           = 7778
)
$ErrorActionPreference = "Stop"
$godot  = "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.6.3-stable_win64_console.exe"
$gcloud = "$env:LOCALAPPDATA\Google\Cloud SDK\google-cloud-sdk\bin\gcloud.cmd"
$bin    = "$ProjectPath\build\linux\PongServer.x86_64"
$gargs  = @("--zone=$Zone", "--project=$Project")

Write-Host "[1/5] Exporting Linux dedicated server (current code)..." -ForegroundColor Cyan
Remove-Item $bin -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force (Split-Path $bin) | Out-Null
& $godot --headless --path $ProjectPath --export-debug "Linux Server" $bin > "$ProjectPath\godot-linux-build.log" 2>&1
if (-not (Test-Path $bin) -or (Get-Item $bin).Length -lt 1MB) {
  throw "Linux export failed - see godot-linux-build.log"
}
Write-Host ("      exported {0:N1} MB" -f ((Get-Item $bin).Length / 1MB))

Write-Host "[2/5] Stopping server + cleaning on VM..." -ForegroundColor Cyan
"y`n" | & $gcloud compute ssh $Vm @gargs --command "sudo systemctl stop pong-godot.service 2>/dev/null; rm -rf ~/pong-godot ~/srv; mkdir -p ~/srv" --quiet | Out-Null

Write-Host "[3/5] Uploading build + setup script..." -ForegroundColor Cyan
& $gcloud compute scp "$ProjectPath\deploy\gcp-setup.sh" "${Vm}:gcp-setup.sh" @gargs --quiet | Out-Null
& $gcloud compute scp $bin "${Vm}:srv/PongServer.x86_64" @gargs --quiet | Out-Null

Write-Host "[4/5] Installing + starting service (port $Port)..." -ForegroundColor Cyan
$verify = "y`n" | & $gcloud compute ssh $Vm @gargs --command "sed -i 's/\r`$//' ~/gcp-setup.sh; PONG_GODOT_PORT=$Port bash ~/gcp-setup.sh" --quiet 2>&1
$verify | Select-String "service:|GODOT_REDEPLOY_OK|GODOT_REDEPLOY_FAILED" | ForEach-Object { $_.Line }
if (-not ($verify -match "GODOT_REDEPLOY_OK")) { Write-Host "`nRedeploy FAILED - check logs" -ForegroundColor Red; exit 1 }

Write-Host "[5/5] Online smoke (2 autoclients vs the live server)..." -ForegroundColor Cyan
& $gcloud compute scp "$ProjectPath\deploy\online-smoke.sh" "${Vm}:online-smoke.sh" @gargs --quiet | Out-Null
$smoke = "y`n" | & $gcloud compute ssh $Vm @gargs --command "sed -i 's/\r`$//' ~/online-smoke.sh; PONG_GODOT_PORT=$Port bash ~/online-smoke.sh" --quiet 2>&1
$smoke | Select-String "SMOKE_EXITS|DEPLOY_SMOKE_OK|DEPLOY_SMOKE_FAILED|SMOKE_" | ForEach-Object { $_.Line }
if ($smoke -match "DEPLOY_SMOKE_OK") {
  Write-Host "`nRedeploy + smoke PASSED - Godot server live on 34.53.62.38:$Port" -ForegroundColor Green
} else {
  Write-Host "`nSMOKE FAILED - the deployed server is not serving real matches" -ForegroundColor Red; exit 1
}

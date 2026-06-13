# Deploying the Godot dedicated server

> **Status (2026-06-10): deployed and live** at `34.53.62.38:7778`
> (`pong-godot.service`, firewall rule `allow-pong-godot-udp`). The legacy Unity
> server has been **retired**: `pong.service` is stopped + disabled and its
> udp/7777 firewall rule deleted. Its files remain at `~/pong` on the VM —
> rollback is `sudo systemctl enable --now pong.service` plus recreating the
> udp/7777 rule.

The Godot client speaks **ENet/UDP** and cannot talk to the legacy Unity/NGO
server — so online play needs a *Godot* server running somewhere. This directory
deploys one to the existing GCP VM on its own port; the table below records the
coexist layout used during the transition (and what rollback would restore).

## Coexist model (transition layout)

| | Unity server (legacy) | Godot server (this) |
| --- | --- | --- |
| Port (UDP) | 7777 | **7778** |
| systemd unit | `pong.service` | `pong-godot.service` |
| Install dir | `~/pong` | `~/pong-godot` |
| Binary | `PongServer.x86_64` (+ `UnityPlayer.so`) | `PongServer.x86_64` (single, embedded PCK) |

Both ran on the same VM (`pong-server`, `us-west1-b`, static IP `34.53.62.38`)
during the transition. The Unity unit has since been decommissioned (2026-06-10,
see the status note at the top); only `pong-godot.service` runs now. The table
above is kept as the record of what rollback would restore.

## One-time setup

1. **Firewall** — allow the Godot port:
   ```sh
   gcloud compute firewall-rules create pong-godot-udp \
     --project pong-497801 --direction INGRESS --action ALLOW \
     --rules udp:7778 --target-tags pong-server
   ```
   (Already created as `allow-pong-godot-udp`; shown here for reference / rebuild.
   `gcloud compute firewall-rules list` shows the current rules. The old udp/7777
   Unity rule was deleted at retirement.)

2. **Ranked persistence (optional)** — to keep Elo across restarts, create
   `~/pong-godot.env` on the VM:
   ```
   PONG_SUPABASE_URL=https://<project>.supabase.co
   PONG_SUPABASE_KEY=<service_role key>
   ```
   Without it the server uses the in-memory store (ratings reset on restart).
   The same `players` table schema as the Unity build works unchanged.

## Deploy / redeploy

From a Windows dev box with `gcloud` authenticated and Godot installed:

```powershell
powershell -ExecutionPolicy Bypass -File deploy\redeploy-gcp.ps1
```

This exports the Linux server from current code, uploads the single binary,
(re)installs `pong-godot.service` on 7778, and runs a 2-autoclient online smoke
that must observe a real match (`DEPLOY_SMOKE_OK`) or the script exits non-zero.

> **Lockstep rule:** any netcode/sim change must ship the client (APK) **and**
> redeploy this server together. A stale server vs a current client desyncs —
> the same class of bug that broke the Unity build's v1.3.0.

Run it on any Linux host directly with `deploy/run-server.sh [port]`.

## Point the client at it

The client already targets this server: in `src/shared/game_config.gd`,
`PRODUCTION_SERVER_ADDRESS` / `PRODUCTION_SERVER_PORT` are `34.53.62.38` / `7778`,
which is the **Play Online** default. `DEFAULT_PORT` (7777) is only the local
`--server`/LAN default, unrelated to the production target. Players can still
override via the **Custom server** field. LAN and vs-CPU need no server.

## Files

| File | Runs on | Purpose |
| --- | --- | --- |
| `redeploy-gcp.ps1` | dev box | export → upload → install → smoke (one command) |
| `gcp-setup.sh` | VM | install deps, write the systemd unit, restart, verify bind |
| `online-smoke.sh` | VM | 2 autoclients vs `127.0.0.1:7778`, assert a real match |
| `pong-godot.service` | VM | reference systemd unit (drain on SIGTERM, optional env file) |
| `run-server.sh` | any Linux | run a local export without systemd |

#!/usr/bin/env bash
# Local pre-deploy verification: run the exported Linux server binary under WSL and
# smoke it with two autoclients — proves the artifact deploy/redeploy-gcp.ps1 will
# upload actually serves real matches, before any VM is touched.
# Usage (from Windows):  wsl bash /mnt/c/dev/pong_godot/deploy/local-wsl-smoke.sh
set -u
PORT="${PONG_GODOT_PORT:-7778}"
SRC="${1:-/mnt/c/dev/pong_godot/build/linux/PongServer.x86_64}"

pkill -f /tmp/pong-godot-smoke 2>/dev/null
cp "$SRC" /tmp/pong-godot-smoke && chmod +x /tmp/pong-godot-smoke
rm -f /tmp/pgs-s.log /tmp/pgs-c1.log /tmp/pgs-c2.log

GODOT_SILENCE_ROOT_WARNING=1 /tmp/pong-godot-smoke --headless -- --server --port "$PORT" >/tmp/pgs-s.log 2>&1 &
SP=$!
sleep 3

/tmp/pong-godot-smoke --headless -- --autoclient --smoke --address 127.0.0.1 --port "$PORT" --quitafter 12 >/tmp/pgs-c1.log 2>&1 &
P1=$!
sleep 1
/tmp/pong-godot-smoke --headless -- --autoclient --smoke --address 127.0.0.1 --port "$PORT" --quitafter 12 >/tmp/pgs-c2.log 2>&1 &
P2=$!
wait $P1; R1=$?
wait $P2; R2=$?
kill $SP 2>/dev/null

echo "SMOKE_EXITS R1=$R1 R2=$R2"
grep -h SMOKE_ /tmp/pgs-c1.log /tmp/pgs-c2.log 2>/dev/null
echo "--- server activity ---"
grep -E "listening|Created match|-> match" /tmp/pgs-s.log | head -5
if [ "$R1" = "0" ] && [ "$R2" = "0" ]; then echo DEPLOY_SMOKE_OK; else echo DEPLOY_SMOKE_FAILED; exit 1; fi

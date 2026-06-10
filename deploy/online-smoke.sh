#!/usr/bin/env bash
# Post-deploy online smoke: two headless autoclients must observe a real match on
# the just-deployed Godot server (got a side, reached Playing, ball replicated +
# moved). The end-to-end gate that proves the live server actually serves matches.
# Run on the VM via: bash ~/online-smoke.sh
# Kept as a file (not an inline --command) because gcloud.cmd on Windows mangles
# multi-line --command strings.
PORT="${PONG_GODOT_PORT:-7778}"
BIN=$(find "$HOME/pong-godot" -name PongServer.x86_64 2>/dev/null | head -1)
if [ -z "$BIN" ]; then echo "DEPLOY_SMOKE_FAILED (binary not found)"; exit 0; fi
chmod +x "$BIN"; rm -f /tmp/c1.log /tmp/c2.log

"$BIN" --headless -- --autoclient --smoke --address 127.0.0.1 --port "$PORT" --quitafter 12 > /tmp/c1.log 2>&1 & P1=$!
sleep 1
"$BIN" --headless -- --autoclient --smoke --address 127.0.0.1 --port "$PORT" --quitafter 12 > /tmp/c2.log 2>&1 & P2=$!
wait $P1; R1=$?
wait $P2; R2=$?
echo "SMOKE_EXITS R1=$R1 R2=$R2"; grep -h SMOKE_ /tmp/c1.log /tmp/c2.log 2>/dev/null || true
if [ "$R1" = "0" ] && [ "$R2" = "0" ]; then echo DEPLOY_SMOKE_OK; else echo DEPLOY_SMOKE_FAILED; fi

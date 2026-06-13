#!/usr/bin/env bash
# Runs ON the VM. Installs/updates the Pong (Godot) dedicated server as a systemd
# service on port 7778. If a freshly-uploaded binary is staged at
# ~/srv/PongServer.x86_64, it is moved into ~/pong-godot first. Idempotent — safe
# to re-run.
set -euo pipefail

PORT="${PONG_GODOT_PORT:-7778}"
DEST="$HOME/pong-godot"

# Stage a freshly-uploaded build (single embedded-PCK binary).
if [ -f "$HOME/srv/PongServer.x86_64" ]; then
  mkdir -p "$DEST"
  mv -f "$HOME/srv/PongServer.x86_64" "$DEST/PongServer.x86_64"
  rmdir "$HOME/srv" 2>/dev/null || true
fi

BIN="$DEST/PongServer.x86_64"
if [ ! -f "$BIN" ]; then echo "GODOT_REDEPLOY_FAILED (binary not found at $BIN)"; exit 1; fi
chmod +x "$BIN"

# Godot's exported binary dynamically links a few system libs even with --headless.
# Install them once (idempotent; quiet if already present).
if ! ldconfig -p | grep -q libGL.so.1; then
  sudo apt-get update -qq || true
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
    libgl1 libfontconfig1 libxcursor1 libxinerama1 libxrandr2 libxi6 libxkbcommon0 || true
fi

sudo tee /etc/systemd/system/pong-godot.service >/dev/null <<EOF
[Unit]
Description=Pong (Godot) dedicated server
After=network.target

[Service]
ExecStart=$BIN --headless -- --server --port $PORT
WorkingDirectory=$DEST
User=$(whoami)
Restart=always
RestartSec=2
EnvironmentFile=-$HOME/pong-godot.env
KillSignal=SIGTERM
TimeoutStopSec=300

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable pong-godot.service >/dev/null 2>&1
sudo systemctl restart pong-godot.service
sleep 4  # ENet bind is fast, but give the process a moment to come up

echo "service: $(systemctl is-active pong-godot.service)"
ss -ulnp 2>/dev/null | grep -q ":$PORT " && echo GODOT_REDEPLOY_OK || echo GODOT_REDEPLOY_FAILED

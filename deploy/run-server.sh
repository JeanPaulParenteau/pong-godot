#!/usr/bin/env bash
# Run the Pong (Godot) dedicated server on a Linux host from a local export
# (no Docker). Build it first with the "Linux Server" export preset, or via
# deploy/redeploy-gcp.ps1 which exports + uploads in one step.
# Usage:  ./deploy/run-server.sh [port]   (default 7778)
set -euo pipefail

PORT="${1:-7778}"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="$DIR/build/linux/PongServer.x86_64"

if [[ ! -f "$BIN" ]]; then
  echo "error: $BIN not found — export the 'Linux Server' preset first:" >&2
  echo "  godot --headless --path . --export-debug \"Linux Server\" build/linux/PongServer.x86_64" >&2
  exit 1
fi

chmod +x "$BIN"
echo "Starting Pong (Godot) dedicated server on 0.0.0.0:$PORT (UDP/ENet)..."
exec "$BIN" --headless -- --server --port "$PORT"

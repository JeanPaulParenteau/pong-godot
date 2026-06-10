#!/usr/bin/env bash
# TDD watch mode: re-run the full suite whenever a .gd file under src/ or tests/
# changes. The red→green→refactor inner loop — keep it open while you work.
#   GODOT=/path/to/godot tests/watch.sh      (Ctrl+C to stop)
GODOT="${GODOT:-godot}"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "TDD watch: re-running tests on any src/ or tests/ *.gd change (Ctrl+C to stop)..."
last=""
while true; do
  cur=$(find "$DIR/src" "$DIR/tests" -name '*.gd' -printf '%T@ ' 2>/dev/null)
  if [ "$cur" != "$last" ]; then
    last="$cur"
    clear
    echo "--- run @ $(date +%H:%M:%S) ---"
    GODOT="$GODOT" bash "$DIR/tests/run-all.sh"
  fi
  sleep 0.7
done

#!/usr/bin/env bash
# The full test suite: headless logic tests + the UI-layout smoke. Exits non-zero
# if either fails. Run this (not just run_tests.gd) before shipping — the UI smoke
# is what guards the "Controls at 0×0 / off-screen" class of bug that unit tests
# can't see (see tests/ui_smoke.gd).
#   GODOT=/path/to/godot tests/run-all.sh
set -u
GODOT="${GODOT:-godot}"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

"$GODOT" --headless --path "$DIR" --script tests/run_tests.gd; a=$?
"$GODOT" --headless --path "$DIR" --script tests/ui_smoke.gd; b=$?

if [ "$a" -eq 0 ] && [ "$b" -eq 0 ]; then
  echo "ALL SUITES PASSED"
else
  echo "TESTS FAILED (unit=$a ui=$b)"
  exit 1
fi

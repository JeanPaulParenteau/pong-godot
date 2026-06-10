#!/usr/bin/env bash
# The full test suite, exits non-zero if anything fails. Run this before shipping.
#   GODOT=/path/to/godot tests/run-all.sh
#
#   1. tests/run_tests.gd   — legacy logic harness (being migrated to GdUnit4)
#   2. tests/gdunit/        — GdUnit4 suites (logic + the UI-layout guard); this is
#                             where NEW tests go, test-first (see docs/TDD.md)
set -u
GODOT="${GODOT:-godot}"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

"$GODOT" --headless --path "$DIR" --script tests/run_tests.gd
a=$?
"$GODOT" --headless --path "$DIR" -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd \
  --ignoreHeadlessMode -a res://tests/gdunit
b=$?

if [ "$a" -eq 0 ] && [ "$b" -eq 0 ]; then
  echo "ALL SUITES PASSED"
else
  echo "TESTS FAILED (legacy=$a gdunit=$b)"
  exit 1
fi

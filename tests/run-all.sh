#!/usr/bin/env bash
# The full test suite, exits non-zero if anything fails. Run this before shipping.
#   GODOT=/path/to/godot tests/run-all.sh
#
# Everything is GdUnit4 (tests/gdunit/); new tests go there, test-first
# (see docs/TDD.md). The legacy run_tests.gd harness is fully migrated and gone.
set -u
GODOT="${GODOT:-godot}"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

"$GODOT" --headless --path "$DIR" -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd \
  --ignoreHeadlessMode -a res://tests/gdunit
if [ $? -eq 0 ]; then
  echo "ALL SUITES PASSED"
else
  echo "TESTS FAILED"
  exit 1
fi

#!/usr/bin/env bash
# Point git at the committed hooks/ dir so pre-push runs the test suite.
# Run once after cloning.
set -eu
ROOT="$(git rev-parse --show-toplevel)"
git -C "$ROOT" config core.hooksPath hooks
chmod +x "$ROOT"/hooks/* 2>/dev/null || true
echo "Git hooks installed (core.hooksPath=hooks). Pre-push now runs tests + the coverage gate."
echo "Set GODOT=/path/to/godot in your environment if 'godot' isn't on PATH."

#!/usr/bin/env bash
# Per-file test gate: every src/**/*.gd must be referenced by some test (its
# res:// path appears under tests/). Files not yet covered are grandfathered in
# tests/untested-allowlist.txt — that list may only SHRINK, so a NEW src file
# without a test fails this gate. That's the mechanical nudge to write the test
# first (see docs/TDD.md). Run in CI; exits non-zero on a violation.
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ALLOW="$DIR/tests/untested-allowlist.txt"
touch "$ALLOW"

fail=0
stale=0

# 1. Every source file is tested or explicitly allowlisted.
while IFS= read -r f; do
  rel="${f#"$DIR"/}"                       # e.g. src/shared/game_session.gd
  res="res://$rel"
  if grep -rqF -- "$res" "$DIR/tests" 2>/dev/null; then
    continue                               # referenced by a test → covered
  fi
  if grep -qxF -- "$rel" "$ALLOW" 2>/dev/null; then
    continue                               # known debt, allowlisted
  fi
  echo "UNTESTED (and not allowlisted): $rel"
  fail=1
done < <(find "$DIR/src" -name '*.gd' | sort)

# 2. The allowlist may only shrink: flag entries that are now tested or deleted.
while IFS= read -r rel; do
  [ -z "$rel" ] && continue
  if [ ! -f "$DIR/$rel" ] || grep -rqF -- "res://$rel" "$DIR/tests" 2>/dev/null; then
    echo "STALE allowlist entry (now tested or deleted — remove it): $rel"
    stale=1
  fi
done < "$ALLOW"

if [ $fail -ne 0 ]; then
  echo "test-coverage gate: FAILED — add a test for the file(s) above (preferred) or allowlist as debt."
  exit 1
fi
if [ $stale -ne 0 ]; then
  echo "test-coverage gate: FAILED — prune the stale allowlist entries above (the list may only shrink)."
  exit 1
fi
echo "test-coverage gate: OK"

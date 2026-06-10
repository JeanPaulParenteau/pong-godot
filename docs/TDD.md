# Test-Driven Development in this project

This codebase is developed **test-first**. The rule is simple:

> **No production code is written without a failing test that requires it.**

Red → Green → Refactor:

1. **Red** — write the smallest test that expresses the next bit of behaviour, and
   watch it fail (a test that passes before you write any code is testing nothing).
2. **Green** — write the minimum code to make it pass.
3. **Refactor** — clean up with the test as a safety net.

## The loop

Keep the watcher open while you work — it re-runs the whole suite on every save,
so each Red/Green is seconds of feedback:

```sh
GODOT=/path/to/godot tests/watch.sh      # or  tests/watch.ps1  on Windows
```

Run the suite once (also what CI runs, exits non-zero on any failure):

```sh
GODOT=/path/to/godot tests/run-all.sh    # or  tests/run-all.ps1
```

## Where tests live

| Location | What | Framework |
| --- | --- | --- |
| `tests/gdunit/**_test.gd` | **all new tests go here**, test-first | [GdUnit4](https://github.com/godot-gdunit-labs/gdUnit4) |
| `tests/run_tests.gd` | legacy logic harness (171 checks) | hand-rolled `check()` — **being migrated to GdUnit4**, don't add to it |

New behaviour → a new or existing GdUnit4 suite under `tests/gdunit/`. A GdUnit4
suite is `extends GdUnitTestSuite`, one `func test_*()` per behaviour, fluent
assertions (`assert_int(x).is_equal(5)`, `assert_that(v).is_equal(w)`):

```gdscript
extends GdUnitTestSuite

const EloRating = preload("res://src/shared/elo_rating.gd")

func test_equal_rating_win_moves_half_k_each_way() -> void:
    var r := EloRating.after_win(0, 0)
    assert_int(r[0]).is_equal(16)
    assert_int(r[1]).is_equal(-16)
```

**UI / layout / input** is testable too (this is why GdUnit4 was chosen) — see
`tests/gdunit/menu_layout_test.gd`, which boots the real menu graph in a sized
`SubViewport` and asserts the Controls aren't 0×0 / off-screen. That suite exists
because three shipped bugs (grey screen, hidden menu, missing Leave button) were
exactly that, and pure-logic tests can't see rendering. **Any new screen or
on-screen control gets a layout test.**

## What keeps us honest (enforcement)

TDD is a discipline; these make skipping it cost something:

- **`tests/watch.sh|ps1`** — the fast loop that makes test-first the easy path.
- **CI** (`.github/workflows/tests.yml`) runs `run-all` on every push/PR; a red
  suite blocks the merge.
- **Pre-push hook** (`hooks/pre-push`, install with `tests/install-hooks.sh|ps1`)
  runs the suite locally before a push so red never leaves your machine.
- **Per-file test gate** (`tests/check-tested.sh`, run in CI) — every `src/**`
  script must be referenced by some test. Files not yet covered are listed in
  `tests/untested-allowlist.txt`; **that list may only shrink** — a new `src` file
  with no test fails the gate, which is the mechanical nudge to write the test
  first.

## Migration

`tests/run_tests.gd` predates the framework. It still runs (and guards the existing
code), but it's frozen: port a chunk into a GdUnit4 suite whenever you touch the
code it covers, and delete the ported checks from it. The goal is one framework.

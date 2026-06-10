# Contributing

This project is developed **test-first** — please read **[docs/TDD.md](docs/TDD.md)**
before sending a change. In short:

1. Write a failing test (`tests/gdunit/**_test.gd`, GdUnit4) for the behaviour.
2. Make it pass with the minimum code.
3. Refactor.

Keep the loop tight:

```sh
GODOT=/path/to/godot tests/watch.sh      # re-runs the suite on every save
```

Before pushing, the full suite must be green:

```sh
GODOT=/path/to/godot tests/run-all.sh    # logic + GdUnit4 (UI layout) suites
```

Install the pre-push hook once so this runs automatically:

```sh
tests/install-hooks.sh                    # or tests/install-hooks.ps1 on Windows
```

CI runs the same suite plus the per-file test gate on every push/PR; a red build
blocks the merge. New `src/` files need a test (see the gate in docs/TDD.md).

For the project's design, see [README.md](README.md) and [docs/PORT.md](docs/PORT.md).

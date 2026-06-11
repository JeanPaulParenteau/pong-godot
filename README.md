# Pong (Godot)

A Godot 4.6 port of [JeanPaulParenteau/pong](https://github.com/JeanPaulParenteau/pong)
(Unity 6 + Netcode for GameObjects). Same game, same rules, same
server-authoritative architecture — rebuilt on GDScript and Godot's high-level
multiplayer (ENet/UDP). See [docs/PORT.md](docs/PORT.md) for every design
decision made in the translation.

**Features**

- Single-player vs CPU (Easy / Medium / Hard — one bot algorithm, three feels)
- Online 1v1 on a dedicated server: concurrent matches, auto-pairing,
  auto-reconnect with exponential backoff
- Server-authoritative physics with spin, edge-clip self-scores, swept
  (tunnel-proof) paddle collisions
- Client-side: ~100 ms interpolation for remote state, capped prediction for
  your own paddle, and a perspective mirror so you are always the blue paddle
  on the left
- "Pong TV": watch a live match as a read-only spectator
- LAN server discovery (wire-compatible with the Unity build's discovery)
- Ranked Elo ratings persisted to Supabase (optional, server-side)
- Procedural audio — no assets anywhere in the project
- Game feel driven off the *authoritative* event counters (never client guesses):
  screen shake, impact particles, paddle hit flashes, ball heat tint +
  squash-stretch as rallies ramp to the speed cap, rally counter, MATCH POINT
  banner, popping serve countdown, goal flash
- Persisted client settings (sound, fullscreen) and animated menu transitions

## Requirements

[Godot 4.6.x](https://godotengine.org/download) (standard build, not .NET).
On Windows: `winget install GodotEngine.GodotEngine`.

## Run

All commands from the repo root. `godot` is the Godot 4.6 executable
(on Windows prefer the `_console.exe` for visible logs). Project args go
after `--`.

```sh
# Play (menu: Play Online / Vs Computer / Pong TV)
godot --path .

# Dedicated server (windowed close request drains gracefully)
godot --headless --path . -- --server --port 7777

# Full test suite — legacy logic checks + GdUnit4 suites (logic + UI layout).
# This codebase is developed test-first; see docs/TDD.md. Watch mode: tests/watch.sh
GODOT=godot tests/run-all.sh          # or  tests/run-all.ps1  on Windows

# Headless autoclient (end-to-end smoke: exits 0 only if a real match was seen)
godot --headless --path . -- --autoclient --smoke --address 127.0.0.1 --port 7777 --quitafter 15
```

A full local online test is one server + two autoclients:

```sh
godot --headless --path . -- --server --port 7799 &
godot --headless --path . -- --autoclient --smoke --address 127.0.0.1 --port 7799 --quitafter 15 &
godot --headless --path . -- --autoclient --smoke --address 127.0.0.1 --port 7799 --quitafter 15
# each autoclient prints SMOKE_OK / SMOKE_FAIL and exits 0 / 2
```

## Developing & testing the running game

The dev loop, fastest first:

1. **Headless unit tests** (`tests/run-all.sh|ps1` → GdUnit4, seconds) — sim/bot/Elo/netcode/FX/UI-layout/server logic; every `src/**` script is covered (see `docs/TDD.md`).
2. **Headless smoke** — the server + autoclient commands above; real ENet sockets, exit codes.
3. **Desktop run** — `godot --path .` (add `-- --solo` to jump straight into a vs-CPU match).
4. **Android emulator** — `adb install` + `am start` + `input tap/swipe`; drive and observe.

**Seeing the running game (the debug capture tool).** In debug builds only, a
screenshotter saves the engine's own viewport — the reliable way to capture on
Android, where `adb screencap` can't read Godot's GL SurfaceView:

- **F12** → saves `user://shots/shot_NNN.png` (desktop).
- **`--shot-interval N`** → overwrites `user://cap.png` every N frames, for
  adb-driven testing. The committed **"Android Emu"** export preset bakes this in
  (plus x86_64 for the emulator), so:
  ```sh
  godot --headless --path . --export-debug "Android Emu" build/PongGodot-emu.apk
  adb install -r build/PongGodot-emu.apk && adb shell am start -n com.parenteau.ponggodot/com.godot.game.GodotAppLauncher
  # tap around with `adb shell input tap X Y`, then pull what the engine rendered:
  adb exec-out run-as com.parenteau.ponggodot cat files/cap.png > cap.png
  ```

The capture node is gated behind `OS.is_debug_build()` and inert unless the flag
is set, so it never affects a release build. Use the **"Android"** preset (arm-only,
no flag) for shipping and **"Android Emu"** (x86_64 + capture) for the emulator.

## Deploying the dedicated server

[deploy/](deploy/) holds the full GCP deploy pipeline, mirroring the Unity
original's: `redeploy-gcp.ps1` exports the Linux server (single embedded-PCK
binary), uploads it, installs the `pong-godot.service` systemd unit on **UDP
7778** — coexisting with the legacy Unity server on 7777 — and gates the deploy
on a 2-autoclient online smoke against the live server. One-time firewall setup
and the lockstep client/server rule are in [deploy/DEPLOY.md](deploy/DEPLOY.md).
`deploy/local-wsl-smoke.sh` verifies the exported Linux artifact end-to-end
under WSL before any VM is touched.

## Android APK

A signed debug APK ships on the [Releases](https://github.com/JeanPaulParenteau/pong-godot/releases)
page (`com.parenteau.ponggodot`, arm64-v8a + armeabi-v7a, INTERNET permission for
online play). To build it yourself you need JDK 17, the Android SDK (build-tools +
platform-tools), and the matching Godot Android export templates; with those and a
debug keystore configured in Godot's editor settings:

```sh
# prebuilt-template path (no Gradle daemon needed — just packages + signs)
godot --headless --path . --export-debug "Android" build/PongGodot.apk
```

Notes from setting this up (see [docs/PORT.md](docs/PORT.md) for the full trail):
- On Windows the export templates live in the **data** dir
  (`%LOCALAPPDATA%\Godot\export_templates\<version>\`), not the config dir.
- Android export requires `rendering/textures/vram_compression/import_etc2_astc=true`
  in `project.godot` (already set here) or validation fails — and in headless mode
  Godot reports that failure with an *empty* message, so it's easy to misdiagnose.
- The preset uses `use_gradle_build=false`; the Gradle path needs a loopback socket
  for its daemon, which a sandboxed shell can block.

### Launch flags

| Flag | Meaning |
| --- | --- |
| `--server` / `--dedicated` | dedicated server (also the default when headless) |
| `--port N` | listen/connect port (or `PONG_PORT` env; default 7777) |
| `--maxmatches N` | per-process match cap; refused clients see "server full" (or `PONG_MAX_MATCHES`; 0 = unlimited) |
| `--autoclient` | headless test client |
| `--smoke` | autoclient exits non-zero unless side+playing+ball-motion were observed |
| `--address IP` | autoclient target |
| `--quitafter S` / `--dropafter S` | autoclient lifetime / intentional mid-run drop |
| `--playerid ID --playername NAME` | autoclient connects as an identified Player (ranked) |
| `--solo` | client jumps straight into a vs-CPU match (dev/demo) |
| `--shot-interval N` | debug builds: save the viewport to `user://cap.png` every N frames (see Developing & testing) |

### Controls

Drag (touch) or move the mouse to drive your paddle vertically. `Esc` or the
on-screen **Leave** button exits a match.

### Ranked persistence (optional)

The server keeps Elo + win/loss per Player in memory by default. Set
`PONG_SUPABASE_URL` and `PONG_SUPABASE_KEY` (service-role key — server only,
never in a client) to persist to a Supabase `players` table
(`player_id, display_name, rating, wins, losses, games_played` — the same
schema the Unity server uses). Identified games only; anonymous games are
never rated.

## Project layout

```
src/shared/   pure simulation + protocol (no nodes): GameSession, PongBot, Elo,
              MatchRoster, SpectatorRouter, MatchSnapshot, handshake/discovery codecs
src/client/   view + input + connection UX: renderer, menu, solo match, prediction,
              interpolation, reconnect flow, LAN browser, identity, audio
src/server/   MatchServer (ENet adapter over the shared core), player stores, ranked
src/net/      NetBridge — the one RPC surface shared by client and server
tests/        headless test runner (ports the Unity EditMode suite's behaviours)
```

The layering rule is inherited from the Unity original: everything in
`src/shared/` is pure and headless-testable; nodes and networking live at the
edges. The deeper rationale for each subsystem is documented in the original
repo's `docs/adr/` and summarized per-divergence in [docs/PORT.md](docs/PORT.md).

## Caveat: the cloud server

`GameConfig.PRODUCTION_SERVER_ADDRESS` still points at the original deployment,
which today runs the **Unity** server. The two game transports (Unity Transport
vs ENet) are not cross-compatible — deploy this project's `--server` build
there (or anywhere) before pointing players at it. Only the LAN *discovery*
protocol is shared between the two implementations.

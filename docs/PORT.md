# Porting notes: Unity → Godot

This project is a feature-complete port of the Unity 6 / Netcode-for-GameObjects
Pong at `JeanPaulParenteau/pong`. The gameplay constants, physics, bot tuning,
Elo math, and wire-text protocols are byte-for-byte faithful; the engine-facing
layers were redesigned for Godot. This file records every deliberate divergence
and why.

## What was preserved exactly

- **All tuning** (`GameConfig`): field geometry, ball speeds/caps, bounce/spin/
  edge-deflect angles, paddle speed/easing, win score, serve/game-over delays,
  Elo K-factor. A rally feels the same in both builds.
- **The simulation** (`GameSession`): the swept leading-edge paddle collision
  (tunnel-proof, one-shot), the front-face vs edge-clip split (clipping your own
  paddle edge concedes the point), spin from paddle velocity with the 30° spin
  cap and 72° total cap, serve toward whoever was scored on, rematch on dwell.
- **The bot** (`PongBot`/`BotController`/`BotProfile`): identical three-tier
  tuning, reaction cadence, aim-error sampling, intercept prediction with
  triangle-wave wall folding, and the edge-safe aim bias.
- **Pure policy classes**: `MatchRoster` (seating + cap), `SpectatorRouter`
  (lowest-live-id, keep-through-game-over), `ConnectionFlow`/`ReconnectPolicy`
  (1-2-4-8s backoff, 4 attempts), `InputThrottle`, `SnapshotBuffer` semantics
  (tick-dedupe, teleport snap), `PaddlePredictor`, Elo, ranked aggregates.
- **Wire text formats**: the LAN discovery protocol (`PONGv1|DISCOVER`…) is
  wire-identical — the Godot client's LAN browser lists Unity servers and vice
  versa. The player handshake (`P1<US>id<US>name`) keeps the same shape (now a
  string over an RPC instead of approval-payload bytes).
- **The layering**: pure, headless-testable core; thin node adapters at the
  edges; the renderer/audio read one `MatchSource` seam so online, solo, and
  spectating share all view code.
- **The ops harness**: `--server/--port/--maxmatches/--autoclient/--smoke/...`
  flags and env precedence are unchanged, so the original deploy/smoke scripts
  translate directly.

## Divergences and their rationale

### 1. GDScript, not C#

Godot's .NET flavor would have allowed near-verbatim reuse of the C# core, but
GDScript was chosen deliberately: no .NET SDK dependency for contributors or
CI, first-class headless `--script` test runs, and zero marshalling friction
with engine types. The port cost is contained because the core classes are
small and pure. Consequences:

- **No nullable value types** → the `NO_SIDE` (-1) sentinel replaces
  `PlayerSide?` everywhere (winner, local side, spectators). `MatchSnapshot`
  keeps the same `-1 = no winner` encoding the Unity wire used.
- **No `ref` params** → `GameSession._resolve_paddle` returns `[pos, vel]`.
- **Scripts reference each other via `preload` consts**, not `class_name`
  globals: the global class cache can be stale in fresh headless checkouts,
  and explicit imports keep dependency edges grep-able.

### 2. Netcode: ENet high-level multiplayer replaces NGO

The biggest redesign. NGO concepts and their replacements:

| Unity (NGO) | Godot port |
| --- | --- |
| Connection approval payload | First-message `server_hello(payload)` RPC; the server sweeps peers that never say hello (5 s) |
| `NetworkVariable` delta replication | Server pushes each match's full snapshot (17-element array) at 30 Hz, unreliable-ordered |
| `NetworkObject` spawn + `NetworkShow` visibility | No spawned objects at all: the server sends a match's snapshots only to its two seats + routed spectators |
| `DisconnectReason` | `client_refused(reason)` RPC sent just before the server closes the peer |
| Server-side `NetworkGameState` per match | A plain `{session, participants, tick}` record inside `MatchServer` |
| `AssignSideRpc` | `client_assign_side(side)` RPC |
| `SubmitPaddleInputRpc` | `server_submit_input(target_y)` RPC |

Why snapshot-push instead of replicated objects: Pong's whole match state is
~17 scalars at 30 Hz (≈4 KB/s/client) — per-field delta replication buys
nothing, and explicit routing makes the spectator/visibility model trivial
(`_publish` sends to exactly who should see; there is no NGO 2.11-style
`CheckObjectVisibility`/`NetworkShow` ordering trap, which the Unity code
needed careful intent-first bookkeeping to survive). Late joiners need no
initial sync because every snapshot is a full state.

The hello-timeout sweep replaces what NGO approval gave for free (a client
can't sit connected but unrouted), and "server full" moves from approval-time
refusal to refuse-after-hello — same UX, one extra round-trip.

### 3. The Pong TV "Leave" bug class is structurally gone

The Unity v1.4.4 fix dealt with `Shutdown()` being asynchronous: the
disconnect callback fired later and could misread a spectator exit as a player
drop, auto-reconnecting into a seat. In Godot, closing the local peer emits no
local signal, so every leave path (`_leave_online`, `_leave_spectating`,
`_start_solo`) tears down synchronously: reset the flow, close the peer, reset
the online match. The reconnect loop is cancelled by a generation counter
rather than by stopping a coroutine. The defensive ordering (flow reset
*before* close) is kept anyway.

### 4. UI: code-built Control nodes

The Unity project went IMGUI → UI Toolkit, both built in C# without scene
assets (ADR 0006/0018 there: diff-able UI, no binary scenes). The port keeps
that philosophy with Godot Controls built in `connect_screen.gd`; the only
scene file is the one-node `main.tscn` entry point. Gameplay rendering is a
custom `_draw()` on a full-rect Control — the direct analog of the IMGUI
`GameRenderer`, including the trail, glow, score flash, and edge-clip border
flash.

One layout change: the solo result overlay (Rematch / difficulty / Main Menu)
moved from `LocalMatch.OnGUI` into the ConnectScreen, which already owns all
menu chrome. `LocalMatch` is logic-only in the port; nodes that draw and nodes
that simulate stay separate.

### 5. Per-frame polling replaces threads and coroutines

- `LanDiscovery`: Unity used a background thread + lock around a UDP socket.
  Godot's `PacketPeerUDP` is non-blocking, so the responder and the probe are
  polled in `_process` — no threads, no locks, same protocol.
- Reconnect backoff: Unity coroutine → an `await`-based loop cancelled by a
  generation counter.
- The server tick: NGO's `NetworkTickSystem.Tick` → a fixed-step accumulator
  in `MatchServer._process` (the same accumulator pattern `LocalMatch` uses,
  spiral-of-death guard included). `Engine.max_fps = 60` keeps the headless
  loop from spinning a VM core, as on Unity.

### 6. Persistence and identity

- `PlayerIdentity`: `PlayerPrefs` → a `ConfigFile` at `user://identity.cfg`;
  the id is 32 hex chars from a CSPRNG (same shape as `Guid.ToString("N")`).
- `SupabasePlayerStore`: `UnityWebRequest` coroutines → `HTTPRequest` nodes
  with signal callbacks. Same table, same warm/is-ready/write-behind contract,
  same "never rate against a cold cache" guard.
- The store seam is duck-typed (`warm/is_ready/load_record/save_record`)
  instead of a C# interface; `load`/`save` got the `_record` suffix because
  `load` shadows a GDScript built-in.

### 7. Drain semantics

`Application.wantsToQuit` → `NOTIFICATION_WM_CLOSE_REQUEST` with
`auto_accept_quit = false`: a desktop close request starts the drain (refuse
new connections, drop spectators and lone waiters, let live matches finish,
then quit). Caveat: a headless SIGTERM still hard-exits — same as the Unity
deployment in practice, where the drain ran only when the signal reached
`wantsToQuit`.

### 8. Tests

Unity's 106 EditMode tests → a single `SceneTree` script
(`tests/run_tests.gd`, 171 checks) covering the same behaviours: session state
machine and physics (wall/paddle/tunneling/edge-clip/self-score/win/rematch),
bounce + spin + caps math, bot decision/cadence/determinism, Elo, ranked
aggregates, roster, spectator routing, handshake + discovery codecs, launch
config precedence, connection flow + backoff, throttle, snapshot buffer,
predictor, and the snapshot wire codec. PlayMode-equivalent coverage comes
from the `--autoclient --smoke` end-to-end harness instead (real server, real
ENet sockets).

### 9. Game-feel additions beyond the Unity build

The port adds a "juice" layer the Unity version didn't have, but it follows the
same architectural rule that made the Unity AudioFx safe: every effect is driven
by the replicated, server-authoritative counters (paddle/wall/edge/score), never
by client-side inference — so effects fire identically online, offline, and on
Pong TV, and never desync from the simulation. The pipeline is
`MatchEvents` (pure counter-delta detector, shared with audio) →
`FxState` (pure: shake decay, particle sim with injectable RNG, paddle pulses,
rally counter, ball heat) → renderer (dumb draw). Both new classes are
unit-tested; the renderer stays logic-free. Client settings (mute, fullscreen)
persist to `user://settings.cfg` and apply through one `Settings.apply()`.

## Known gaps / follow-ups

- The production GCP address constant points at the **Unity** server; the
  transports are incompatible. Deploy this server build before shipping the
  Godot client to players (the deploy scripts in the original repo need a
  Godot export preset + Linux headless build — not part of this port).
- Spectator "leave the idle match" routing exists server-side, but a spectator
  watching the *only* match going idle simply stops receiving snapshots; the
  client falls back to the waiting screen after a 2 s starvation timeout
  (Unity could `NetworkHide` instantly).
### 10. Android APK

The Unity original shipped APKs, so this port does too — a signed debug APK on
the Releases page (`com.parenteau.ponggodot`, arm64-v8a + armeabi-v7a, custom
Pong launcher icon, INTERNET/NETWORK_STATE/WAKE_LOCK permissions). The preset
(`export_presets.cfg`) uses the **prebuilt-template path** (`use_gradle_build=false`):
Godot injects the PCK into the official `android_debug.apk` and signs it with
`apksigner` + the debug keystore — no Gradle daemon, which matters because the
daemon needs a loopback socket a sandboxed shell can refuse ("Unable to establish
loopback connection"). Three gotchas cost real time and are worth recording:

1. **Templates live in the data dir on Windows** (`%LOCALAPPDATA%\Godot\export_templates\`),
   not the config dir (`%APPDATA%`) where editor settings live.
2. **`rendering/textures/vram_compression/import_etc2_astc=true` is mandatory** for
   Android export even with zero textures — and headless Godot reports the missing
   setting as an *empty* configuration error, which masks the cause completely.
   This is now set in `project.godot`.
3. Debug-keystore user defaults to `androiddebugkey`, so Godot omits it from saved
   editor settings — its absence there is not a misconfiguration.

The icon is `res://icon.svg` (project + editor) plus `icons/launcher_*.png`
(legacy 192 + adaptive fg/bg 432) referenced by the preset.

### 11. Top-level Controls must fit the viewport explicitly (the "grey screen" bug)

The first APKs (v0.1.0/0.1.1) booted to a grey screen — no menu — on real phones.
Two bugs, both because the UI Controls are parented under the plain `Node` scene
root (so they are *not* auto-sized to the viewport):

1. `ConnectScreen`/`GameRenderer` had `size == (0,0)`; the centered menu card
   landed at negative coordinates, off-screen. Fix: each calls `_fit_to_viewport()`
   in `_ready` (and on `get_viewport().size_changed`) to set its size to the
   visible rect — Godot only auto-fills a Control that is a *direct* child of the
   viewport.
2. `ConnectScreen._is_connected()` treated Godot's default `OfflineMultiplayerPeer`
   (which reports `CONNECTION_CONNECTED` with `is_server() == true`) as a live
   online match, so it hid the menu behind the in-match leave state. Fix: exclude
   the offline peer with `and not multiplayer.is_server()`.

A third instance of the same root cause: the in-match **Leave** button
(`_corner_button`) set `PRESET_TOP_RIGHT` anchors while still 0×0 and relied on
`custom_minimum_size` (which only sizes Controls inside a Container) — so it
anchored at zero size and never appeared, leaving no way off the match screen on
touch (no `Esc`). Fix: give it a concrete rect via explicit anchor offsets. This
backs both the solo and online Leave buttons.

Both reproduce on desktop, so they're verified there (the in-engine viewport
capture, below, was how they were caught). The Android **emulator** added noise:
`adb screencap` can't read Godot's GL SurfaceView (host GPU → grey capture), and
software GL (swiftshader) has a 2D-compositing quirk (`101010-2` framebuffer) —
neither is a real-device issue. The debug capture node (`src/client/debug_capture.gd`,
`--shot-interval` / F12, gated behind `OS.is_debug_build()`) saves the engine's own
`get_viewport().get_image()`, which sidesteps all of that and is the supported way
to see the running game on-device.

## Known gaps / follow-ups (continued)

- The Android APK is a **debug** build (Godot debug keystore). A Play-store release
  needs a release keystore + AAB; the preset is one `export-release` away.
- Online play from the APK still needs a deployed **Godot** server (the GCP box runs
  Unity); see the server-deploy discussion. LAN and vs-CPU work offline today.

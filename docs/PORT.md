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
(`tests/run_tests.gd`, 142 checks) covering the same behaviours: session state
machine and physics (wall/paddle/tunneling/edge-clip/self-score/win/rematch),
bounce + spin + caps math, bot decision/cadence/determinism, Elo, ranked
aggregates, roster, spectator routing, handshake + discovery codecs, launch
config precedence, connection flow + backoff, throttle, snapshot buffer,
predictor, and the snapshot wire codec. PlayMode-equivalent coverage comes
from the `--autoclient --smoke` end-to-end harness instead (real server, real
ENet sockets).

## Known gaps / follow-ups

- The production GCP address constant points at the **Unity** server; the
  transports are incompatible. Deploy this server build before shipping the
  Godot client to players (the deploy scripts in the original repo need a
  Godot export preset + Linux headless build — not part of this port).
- Spectator "leave the idle match" routing exists server-side, but a spectator
  watching the *only* match going idle simply stops receiving snapshots; the
  client falls back to the waiting screen after a 2 s starvation timeout
  (Unity could `NetworkHide` instantly).
- No Android export preset yet (the Unity original shipped APKs). The code is
  touch-ready (`emulate_mouse_from_touch`, landscape orientation set).

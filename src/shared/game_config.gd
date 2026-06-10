## Central tuning + field-geometry constants shared by the server simulation
## and the client renderer. The play field is centred on the origin and uses
## world units; X is horizontal (paddles at the ends), Y is vertical, up-positive
## (the renderer flips for screen space).

# --- Networking ---
const DEFAULT_PORT := 7777
const DEFAULT_CLIENT_ADDRESS := "127.0.0.1"
# The live cloud dedicated server. Prefilled as the client's default target.
# The Godot server coexists with the legacy Unity server on the same VM: Unity
# owns udp/7777, Godot owns udp/7778 (see deploy/DEPLOY.md) — hence the
# non-default production port here.
const PRODUCTION_SERVER_ADDRESS := "34.53.62.38"
const PRODUCTION_SERVER_PORT := 7778
const TICK_RATE := 30

# Hello payload that marks a client as a read-only spectator ("Pong TV").
const SPECTATOR_TOKEN := "spectate"

# Refusal reason sent when the server is at the per-process match cap.
const SERVER_FULL_REASON := "Server full — please try again shortly."

# Refusal reason sent during a graceful drain (server restarting).
const SERVER_DRAINING_REASON := "Server is restarting — please reconnect shortly."

# --- Field geometry (world units, origin-centred) ---
const FIELD_HALF_WIDTH := 8.0   # left/right extent
const FIELD_HALF_HEIGHT := 4.5  # top/bottom extent (16:9-ish)

# --- Ball ---
const BALL_RADIUS := 0.2
const BALL_BASE_SPEED := 7.0      # launch speed
const BALL_SPEED_STEP := 1.2      # added per paddle hit (rallies ramp up fast)
const BALL_MAX_SPEED := 16.0      # hard cap
const MAX_BOUNCE_ANGLE_DEG := 55.0   # front-face deflection from horizontal
const EDGE_DEFLECT_ANGLE_DEG := 50.0 # glance angle when the ball clips a paddle's top/bottom corner
const SERVE_SPREAD_DEG := 25.0       # random vertical spread at serve

# --- Spin: a moving paddle "carries" the ball, adding bounce angle in its direction ---
const PADDLE_SPIN_DEG_PER_UNIT := 2.2   # extra bounce angle per unit/s of paddle motion.
                                        # At PADDLE_SPEED=16 this can reach ~35deg, so the
                                        # MAX_SPIN_ANGLE_DEG cap below actually engages.
const MAX_SPIN_ANGLE_DEG := 30.0        # cap on spin's angular contribution
const MAX_TOTAL_BOUNCE_ANGLE_DEG := 72.0 # overall cap so the ball always keeps advancing horizontally

# --- Paddles ---
const PADDLE_HALF_HEIGHT := 0.9
const PADDLE_WIDTH := 0.3
const PADDLE_X := 7.3      # distance of paddle face from centre
const PADDLE_SPEED := 16.0 # max paddle move speed (units/s); the paddle eases
                           # toward the input instead of teleporting

# --- Goals: the ball must pass the paddle to score ---
const GOAL_X := 7.9

# --- Match rules ---
const WIN_SCORE := 5
const SERVE_DELAY := 1.0       # serve countdown (seconds)
const GAME_OVER_DELAY := 3.0   # GameOver dwell before reset

# --- Ranked: rating-only Elo. Tuning, not design — cheap to change. ---
const ELO_START_RATING := 0    # every Player starts here (can go negative)
const ELO_K_FACTOR := 32       # max rating swing per game

# --- Derived clamps ---
const PADDLE_MAX_Y := FIELD_HALF_HEIGHT - PADDLE_HALF_HEIGHT
const PADDLE_MIN_Y := -(FIELD_HALF_HEIGHT - PADDLE_HALF_HEIGHT)

# Ball centre is reflected at this Y so the visible edge touches the wall.
const BALL_MAX_Y := FIELD_HALF_HEIGHT - BALL_RADIUS
const BALL_MIN_Y := -(FIELD_HALF_HEIGHT - BALL_RADIUS)


## Clamp a desired paddle Y into its legal range. The one place the
## paddle-bounds rule lives — shared by the simulation and the client input paths.
static func clamp_paddle_y(y: float) -> float:
	return clampf(y, PADDLE_MIN_Y, PADDLE_MAX_Y)

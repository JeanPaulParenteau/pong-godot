## The authoritative match: state machine + ball/paddle simulation + scoring.
## Pure GDScript (no nodes, no networking) so it can be unit-tested headlessly
## and so a dictionary of N sessions is cheap. The server owns one per match
## and publishes its state as snapshots.

const GameConfig := preload("res://src/shared/game_config.gd")
const GameTypes := preload("res://src/shared/game_types.gd")

# ---- Replicated/authoritative state (read-only to the outside) ----
var state: int = GameTypes.GameState.WAITING_FOR_PLAYERS
var ball_position := Vector2.ZERO
var ball_velocity := Vector2.ZERO
var left_paddle_y := 0.0
var right_paddle_y := 0.0
var left_score := 0
var right_score := 0
var serve_countdown := 0.0
var last_game_over_reason: int = GameTypes.GameOverReason.NONE
var winning_side: int = GameTypes.NO_SIDE  # NO_SIDE until a side wins

# Monotonic event counters (replicated) so clients can trigger sound/FX
# off authoritative collisions without any client-side simulation.
var paddle_hit_count := 0
var wall_hit_count := 0
# Edge/corner clips (a subset of paddle contacts) — drives a distinct self-score cue.
var edge_clip_count := 0

# ---- Internal bookkeeping ----
var _left_taken := false
var _right_taken := false
var _serve_toward: int = GameTypes.PlayerSide.LEFT  # side that was last scored on
var _left_input := 0.0    # desired paddle target (already last-known)
var _right_input := 0.0
var _left_paddle_vel := 0.0   # paddle Y velocity (units/s), for spin on contact
var _right_paddle_vel := 0.0
var _game_over_timer := 0.0
var _rng: RandomNumberGenerator


func _init(rng: RandomNumberGenerator = null) -> void:
	if rng == null:
		_rng = RandomNumberGenerator.new()
		_rng.randomize()
	else:
		_rng = rng
	_reset_to_waiting()


func player_count() -> int:
	return (1 if _left_taken else 0) + (1 if _right_taken else 0)


# -------------------------------------------------------------------
# Connection seam: paddle assignment is first-come, free-slot based.
# -------------------------------------------------------------------

## Assign the joining player a free paddle. Returns GameTypes.NO_SIDE if the
## match is full (the cap-at-2 seam). Seating the second player begins a match.
func add_player() -> int:
	var side: int
	if not _left_taken:
		side = GameTypes.PlayerSide.LEFT
		_left_taken = true
	elif not _right_taken:
		side = GameTypes.PlayerSide.RIGHT
		_right_taken = true
	else:
		return GameTypes.NO_SIDE  # full

	if _left_taken and _right_taken:
		_start_new_match()

	return side


## A player dropped: free their slot and end any in-progress match.
func remove_player(side: int) -> void:
	if side == GameTypes.PlayerSide.LEFT:
		_left_taken = false
	else:
		_right_taken = false

	if state == GameTypes.GameState.SERVING or state == GameTypes.GameState.PLAYING:
		_enter_game_over(GameTypes.GameOverReason.OPPONENT_LEFT, GameTypes.NO_SIDE)
	elif state == GameTypes.GameState.GAME_OVER and last_game_over_reason == GameTypes.GameOverReason.WIN:
		# A drop during the post-win dwell: still end up waiting.
		last_game_over_reason = GameTypes.GameOverReason.OPPONENT_LEFT
		winning_side = GameTypes.NO_SIDE


## Client → server input: the desired paddle Y (clamped on apply).
func set_input(side: int, target_y: float) -> void:
	if side == GameTypes.PlayerSide.LEFT:
		_left_input = target_y
	else:
		_right_input = target_y


# -------------------------------------------------------------------
# Simulation tick (called at the server tick rate, e.g. 30 Hz).
# -------------------------------------------------------------------
func tick(dt: float) -> void:
	match state:
		GameTypes.GameState.WAITING_FOR_PLAYERS:
			pass  # Ball idle/hidden at centre; nothing simulates.

		GameTypes.GameState.SERVING:
			_apply_paddle_inputs(dt)
			serve_countdown = maxf(0.0, serve_countdown - dt)
			if serve_countdown <= 0.0:
				_launch_ball()
				state = GameTypes.GameState.PLAYING

		GameTypes.GameState.PLAYING:
			_apply_paddle_inputs(dt)
			_step_ball(dt)

		GameTypes.GameState.GAME_OVER:
			_game_over_timer = maxf(0.0, _game_over_timer - dt)
			if _game_over_timer <= 0.0:
				# Rematch if both players are still here, else wait.
				if _left_taken and _right_taken:
					_start_new_match()
				else:
					_reset_to_waiting()


# -------------------------------------------------------------------
# State transitions
# -------------------------------------------------------------------
func _reset_to_waiting() -> void:
	state = GameTypes.GameState.WAITING_FOR_PLAYERS
	left_score = 0
	right_score = 0
	ball_position = Vector2.ZERO
	ball_velocity = Vector2.ZERO
	serve_countdown = 0.0
	left_paddle_y = 0.0
	right_paddle_y = 0.0
	_left_input = 0.0
	_right_input = 0.0
	winning_side = GameTypes.NO_SIDE
	last_game_over_reason = GameTypes.GameOverReason.NONE


func _start_new_match() -> void:
	left_score = 0
	right_score = 0
	winning_side = GameTypes.NO_SIDE
	last_game_over_reason = GameTypes.GameOverReason.NONE
	# Random initial serve direction at match start.
	_serve_toward = GameTypes.PlayerSide.LEFT if _rng.randi_range(0, 1) == 0 else GameTypes.PlayerSide.RIGHT
	_begin_serve()


func _begin_serve() -> void:
	ball_position = Vector2.ZERO
	ball_velocity = Vector2.ZERO
	serve_countdown = GameConfig.SERVE_DELAY
	state = GameTypes.GameState.SERVING


func _enter_game_over(reason: int, winner: int) -> void:
	state = GameTypes.GameState.GAME_OVER
	last_game_over_reason = reason
	winning_side = winner
	_game_over_timer = GameConfig.GAME_OVER_DELAY
	ball_velocity = Vector2.ZERO


# -------------------------------------------------------------------
# Ball + paddle physics
# -------------------------------------------------------------------
func _launch_ball() -> void:
	ball_position = Vector2.ZERO
	var dir_x := -1.0 if _serve_toward == GameTypes.PlayerSide.LEFT else 1.0
	var spread := _rng.randf_range(-1.0, 1.0) * GameConfig.SERVE_SPREAD_DEG
	var angle := deg_to_rad(spread)
	var dir := Vector2(dir_x * cos(angle), sin(angle))
	ball_velocity = dir.normalized() * GameConfig.BALL_BASE_SPEED


func _apply_paddle_inputs(dt: float) -> void:
	# Ease toward the (clamped) input at a capped speed rather than teleporting.
	# This adds positioning skill and makes the paddle velocity smooth + bounded, so spin is
	# proportional and consistent online (no teleport-driven spikes).
	var max_step := GameConfig.PADDLE_SPEED * dt
	var new_left := move_toward(left_paddle_y, GameConfig.clamp_paddle_y(_left_input), max_step)
	var new_right := move_toward(right_paddle_y, GameConfig.clamp_paddle_y(_right_input), max_step)
	_left_paddle_vel = (new_left - left_paddle_y) / dt if dt > 0.0 else 0.0  # |vel| <= PADDLE_SPEED
	_right_paddle_vel = (new_right - right_paddle_y) / dt if dt > 0.0 else 0.0
	left_paddle_y = new_left
	right_paddle_y = new_right


func _step_ball(dt: float) -> void:
	var pos := ball_position + ball_velocity * dt
	var vel := ball_velocity

	# Top / bottom walls.
	if pos.y > GameConfig.BALL_MAX_Y:
		pos.y = GameConfig.BALL_MAX_Y
		vel.y = -absf(vel.y)
		wall_hit_count += 1
	elif pos.y < GameConfig.BALL_MIN_Y:
		pos.y = GameConfig.BALL_MIN_Y
		vel.y = absf(vel.y)
		wall_hit_count += 1

	# Paddle collisions, swept against the paddle face: register the tick where the
	# ball's LEADING EDGE crosses the face plane (was in front → now at/behind). The
	# ball is then re-seated flush against the face, so it never renders penetrating
	# the paddle; a fast ball can't tunnel through (any crossing is caught regardless
	# of step size); and an edge clip — which keeps its X heading and isn't re-seated —
	# can't re-trigger, because the crossing is a one-shot prev→new transition. The
	# front-face vs edge-clip split lives in _resolve_paddle.
	if (vel.x < 0.0
			and ball_position.x - GameConfig.BALL_RADIUS > -GameConfig.PADDLE_X
			and pos.x - GameConfig.BALL_RADIUS <= -GameConfig.PADDLE_X):
		var hit := _resolve_paddle(pos, vel, ball_position, left_paddle_y, _left_paddle_vel,
				-GameConfig.PADDLE_X, true)
		pos = hit[0]
		vel = hit[1]
	elif (vel.x > 0.0
			and ball_position.x + GameConfig.BALL_RADIUS < GameConfig.PADDLE_X
			and pos.x + GameConfig.BALL_RADIUS >= GameConfig.PADDLE_X):
		var hit := _resolve_paddle(pos, vel, ball_position, right_paddle_y, _right_paddle_vel,
				GameConfig.PADDLE_X, false)
		pos = hit[0]
		vel = hit[1]

	ball_position = pos
	ball_velocity = vel

	# Goals (checked after movement/paddle resolution).
	if pos.x < -GameConfig.GOAL_X:
		_score_point(GameTypes.PlayerSide.RIGHT, GameTypes.PlayerSide.LEFT)
	elif pos.x > GameConfig.GOAL_X:
		_score_point(GameTypes.PlayerSide.LEFT, GameTypes.PlayerSide.RIGHT)


## Resolve a paddle collision once the ball's centre has crossed the paddle face.
## A hit within the flat face bounces back toward the opponent; a hit that only
## catches the rounded top/bottom corner — the "side" of the paddle — glances off
## and keeps heading toward the goal behind the paddle, so a player who clips the
## ball on their paddle's edge concedes the point. A clean miss is left untouched so
## the goal check scores it. Returns [pos, vel] (GDScript has no ref params).
func _resolve_paddle(pos: Vector2, vel: Vector2, prev: Vector2, paddle_y: float,
		paddle_vel: float, paddle_x: float, bounce_right: bool) -> Array:
	# Signed offset from the ball centre to its leading edge (toward the paddle).
	var leading_offset := -GameConfig.BALL_RADIUS if bounce_right else GameConfig.BALL_RADIUS
	var lead_before := prev.x + leading_offset
	var lead_after := pos.x + leading_offset

	# Interpolate the ball's Y at the instant the leading edge meets the face, so the
	# front/edge classification and bounce angle use the true contact point even when
	# the ball travels a long way in one tick.
	var denom := lead_after - lead_before
	var t := 1.0 if is_zero_approx(denom) else clampf((paddle_x - lead_before) / denom, 0.0, 1.0)
	var contact_y := prev.y + (pos.y - prev.y) * t
	var ady := absf(contact_y - paddle_y)

	if ady <= GameConfig.PADDLE_HALF_HEIGHT:
		# Front-face hit: re-seat the ball flush against the face, then reflect back.
		pos.x = paddle_x - leading_offset
		vel = _bounce_off_paddle(vel, contact_y, paddle_y, paddle_vel, bounce_right)
		paddle_hit_count += 1
	elif ady <= GameConfig.PADDLE_HALF_HEIGHT + GameConfig.BALL_RADIUS:
		# Edge/corner clip: glance off the tip but keep travelling toward the goal.
		vel = _edge_deflect(vel, contact_y - paddle_y)
		paddle_hit_count += 1
		edge_clip_count += 1
	# else: clean miss — leave the ball untouched; the goal check scores it.

	return [pos, vel]


## Reflect X, deflect Y by hit offset (edge hits = sharper angle), add spin from the
## paddle's motion (a paddle moving up/down carries the ball that way), and speed up by
## a fixed step capped at the max. The angle is bounded so the ball always advances
## horizontally and the speed stays exactly at the cap — spin changes direction, not speed.
static func _bounce_off_paddle(vel: Vector2, ball_y: float, paddle_y: float,
		paddle_vel: float, moving_right: bool) -> Vector2:
	var offset := clampf((ball_y - paddle_y) / GameConfig.PADDLE_HALF_HEIGHT, -1.0, 1.0)
	var offset_deg := offset * GameConfig.MAX_BOUNCE_ANGLE_DEG
	var spin_deg := clampf(paddle_vel * GameConfig.PADDLE_SPIN_DEG_PER_UNIT,
			-GameConfig.MAX_SPIN_ANGLE_DEG, GameConfig.MAX_SPIN_ANGLE_DEG)
	var angle := deg_to_rad(clampf(offset_deg + spin_deg,
			-GameConfig.MAX_TOTAL_BOUNCE_ANGLE_DEG, GameConfig.MAX_TOTAL_BOUNCE_ANGLE_DEG))
	var new_speed := minf(vel.length() + GameConfig.BALL_SPEED_STEP, GameConfig.BALL_MAX_SPEED)
	var dir_x := 1.0 if moving_right else -1.0
	var dir := Vector2(dir_x * cos(angle), sin(angle))
	return dir.normalized() * new_speed


## A glancing hit off the paddle's top/bottom corner: kick the ball away from the
## paddle centre vertically while preserving its horizontal heading, so it slips
## past the paddle toward the goal behind it. Still a contact, so it speeds up.
static func _edge_deflect(vel: Vector2, dy: float) -> Vector2:
	var v_sign := 1.0 if dy >= 0.0 else -1.0   # push up off the top tip, down off the bottom tip
	var x_sign := 1.0 if vel.x >= 0.0 else -1.0  # keep heading toward the goal behind the paddle
	var angle := deg_to_rad(GameConfig.EDGE_DEFLECT_ANGLE_DEG)
	var new_speed := minf(vel.length() + GameConfig.BALL_SPEED_STEP, GameConfig.BALL_MAX_SPEED)
	var dir := Vector2(x_sign * cos(angle), v_sign * sin(angle))
	return dir.normalized() * new_speed


func _score_point(scorer: int, scored_on: int) -> void:
	if scorer == GameTypes.PlayerSide.LEFT:
		left_score += 1
	else:
		right_score += 1

	_serve_toward = scored_on  # serve toward whoever was just scored on
	var scorer_score := left_score if scorer == GameTypes.PlayerSide.LEFT else right_score

	if scorer_score >= GameConfig.WIN_SCORE:
		_enter_game_over(GameTypes.GameOverReason.WIN, scorer)
	else:
		_begin_serve()


# -------------------------------------------------------------------
# Test support (deterministic scenario setup).
# -------------------------------------------------------------------
func teleport_ball(position: Vector2, velocity: Vector2) -> void:
	ball_position = position
	ball_velocity = velocity


## Place a paddle directly (test setup), bypassing the capped easing.
func teleport_paddle(side: int, y: float) -> void:
	if side == GameTypes.PlayerSide.LEFT:
		left_paddle_y = GameConfig.clamp_paddle_y(y)
	else:
		right_paddle_y = GameConfig.clamp_paddle_y(y)

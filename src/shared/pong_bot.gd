## The CPU opponent's decision logic for the RIGHT paddle. Pure and deterministic
## (no time, no RNG, no nodes) so it unit-tests headlessly; the stateful bits
## (reaction cadence, aim-error sampling) live in BotController.

const GameConfig := preload("res://src/shared/game_config.gd")


## Where the right paddle wants to be this instant. Centres (0) when the ball is moving
## away (so the bot doesn't pre-camp the ball), tracks the ball's current y by default,
## and aims at the reflected intercept point when predict_intercept is set.
static func desired_aim_y(ball_pos: Vector2, ball_vel: Vector2, predict_intercept: bool) -> float:
	# Ball heading toward the right paddle means vel.x > 0. Otherwise idle to centre.
	if ball_vel.x <= 0.0:
		return 0.0
	return intercept_y(ball_pos, ball_vel) if predict_intercept else ball_pos.y


## The y at which a ball travelling (vel) from (pos) reaches the right paddle's contact
## plane, accounting for top/bottom wall reflections. Contact happens when the ball's
## near edge meets the paddle face, i.e. when its centre reaches PADDLE_X - BALL_RADIUS
## (matching GameSession's collision test). Assumes vel.x > 0 (caller guards).
static func intercept_y(pos: Vector2, vel: Vector2) -> float:
	if vel.x <= 0.0:
		return pos.y
	var t := (GameConfig.PADDLE_X - GameConfig.BALL_RADIUS - pos.x) / vel.x
	if t <= 0.0:
		return pos.y
	return fold_into_field(pos.y + vel.y * t)


## Reflect a raw y back into [BALL_MIN_Y, BALL_MAX_Y] as a triangle wave — i.e. as
## many bounces off the top/bottom walls as the distance implies.
static func fold_into_field(raw_y: float) -> float:
	var lo := GameConfig.BALL_MIN_Y
	var hi := GameConfig.BALL_MAX_Y
	var span := hi - lo
	if span <= 0.0:
		return lo
	var p := fposmod(raw_y - lo, 2.0 * span)  # 0..2*span
	var folded := p if p <= span else 2.0 * span - p  # fold the second half back down
	return lo + folded


## Move current_y toward aim_y by at most max_step, clamped to the paddle's legal
## range. This is the rate limit that keeps the bot beatable.
static func rate_limited_step(current_y: float, aim_y: float, max_step: float) -> float:
	var next := move_toward(current_y, aim_y, max_step)
	return clampf(next, GameConfig.PADDLE_MIN_Y, GameConfig.PADDLE_MAX_Y)


## How far the bot lets its committed aim sit from where the ball will actually be — the
## edge-aware safe zone. GameSession's edge-clip physics only counts a contact as a save
## while it lands on the front face (|dy| <= PADDLE_HALF_HEIGHT); the band just beyond it
## (PADDLE_HALF_HEIGHT .. +BALL_RADIUS) glances past for a self-score. The committed aim
## can be up to aim_error off, so we cap that offset a full BALL_RADIUS inside the
## front-face boundary: the cushion absorbs the residual prediction/lag/rate-limit drift
## that piles on top of the aim error, so the contact can't tip into the edge band. A bot
## already aiming tighter than this limit needs no reining in, hence the lesser of the two.
static func edge_safe_offset(aim_error: float) -> float:
	var front_face_cushioned := GameConfig.PADDLE_HALF_HEIGHT - GameConfig.BALL_RADIUS
	return minf(absf(aim_error), front_face_cushioned)


## Bias a committed aim point toward the ball's true target so the resulting contact stays
## on the paddle's front face instead of the self-scoring edge band. base_aim is where the
## bot wants the paddle (ball y, or the predicted intercept); raw_aim is that target after
## the sampled aim error. We clamp the error component to edge_safe_offset so an over-sloppy
## tier can't commit an aim that clips its own paddle edge. Within the safe band this is a no-op.
static func edge_safe_aim(base_aim: float, raw_aim: float, aim_error: float) -> float:
	var safe := edge_safe_offset(aim_error)
	return base_aim + clampf(raw_aim - base_aim, -safe, safe)

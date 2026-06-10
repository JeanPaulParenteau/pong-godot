## The stateful half of the CPU opponent: reaction cadence, aim-error sampling, and the
## rate-limited paddle position carried across ticks. Wraps the pure PongBot decision
## math so the bot's *behaviour over time* (how Easy lags, how Hard tracks) is
## unit-testable without a node or frame loop. Deterministic given a seeded RNG.

const GameConfig := preload("res://src/shared/game_config.gd")
const PongBot := preload("res://src/shared/pong_bot.gd")

var _profile  # BotProfile
var _rng: RandomNumberGenerator

var _paddle_y := 0.0      # current rate-limited paddle position
var _committed_aim := 0.0 # aim point held until the next reaction
var _aim_timer := 0.0     # seconds accumulated since the last aim commit


## profile: per-difficulty tuning (speed, reaction delay, aim error, prediction).
## rng: source for aim-error sampling. Pass a seeded RandomNumberGenerator for
## reproducible tests; omit for per-match variety.
func _init(profile, rng: RandomNumberGenerator = null) -> void:
	_profile = profile
	if rng == null:
		_rng = RandomNumberGenerator.new()
		_rng.randomize()
	else:
		_rng = rng
	_aim_timer = profile.react_delay  # commit an aim on the very first step


## The paddle position as of the last step() (starts centred at 0).
func paddle_y() -> float:
	return _paddle_y


## Advance the bot by one fixed tick against the current ball state and return its new
## desired paddle Y. Re-commits an aim point (with sampled aim error) every
## react_delay seconds, then rate-limits travel toward it by max_speed * dt — the
## self-limit that keeps the bot beatable.
func step(ball_pos: Vector2, ball_vel: Vector2, dt: float) -> float:
	_aim_timer += dt
	if _aim_timer >= _profile.react_delay:
		_aim_timer = 0.0
		var err: float = _rng.randf_range(-1.0, 1.0) * _profile.aim_error
		var base_aim: float = PongBot.desired_aim_y(ball_pos, ball_vel, _profile.predict_intercept)
		# Edge-aware: bias the committed aim back toward the true target so even the
		# worst aim-error sample keeps the ball on the front face rather than clipping the
		# paddle's edge band into a self-score (GameSession edge-clip physics).
		var aim := PongBot.edge_safe_aim(base_aim, base_aim + err, _profile.aim_error)
		_committed_aim = clampf(aim, GameConfig.PADDLE_MIN_Y, GameConfig.PADDLE_MAX_Y)
	_paddle_y = PongBot.rate_limited_step(_paddle_y, _committed_aim, _profile.max_speed * dt)
	return _paddle_y

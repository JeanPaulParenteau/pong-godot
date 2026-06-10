## Pure visual-FX state for a match: screen shake, impact particles, paddle hit
## pulses, the rally counter, and ball "heat". Fed by MatchEvents (authoritative
## counter deltas) and ticked with frame time; the renderer only reads and draws.
## No nodes, injectable RNG → unit-testable, like the rest of the client logic.

const GameConfig := preload("res://src/shared/game_config.gd")
const GameTypes := preload("res://src/shared/game_types.gd")
const MatchEvents := preload("res://src/client/match_events.gd")

# Shake impulse per event (screen pixels) and exponential decay rate.
const SHAKE_PADDLE := 4.0
const SHAKE_WALL := 2.5
const SHAKE_EDGE := 9.0
const SHAKE_SCORE := 12.0
const SHAKE_DECAY := 7.0

const PULSE_DECAY := 4.0           # paddle hit-flash fade (per second)
const RALLY_SHOW_MIN := 4          # show the rally counter from this many hits
const MAX_PARTICLES := 256

var shake := 0.0               # current shake magnitude (pixels)
var paddle_pulse_left := 0.0   # 1 → just hit, fades to 0
var paddle_pulse_right := 0.0
var rally := 0                 # paddle contacts in the current point
var particles: Array = []      # {pos, vel (world u/s), life, max_life, size (world u), color}

var _rng: RandomNumberGenerator


func _init(rng: RandomNumberGenerator = null) -> void:
	if rng == null:
		_rng = RandomNumberGenerator.new()
		_rng.randomize()
	else:
		_rng = rng


func clear() -> void:
	shake = 0.0
	paddle_pulse_left = 0.0
	paddle_pulse_right = 0.0
	rally = 0
	particles.clear()


## React to one authoritative event. snap supplies the ball position/velocity so
## bursts land where the contact happened.
func apply_event(event: String, snap) -> void:
	var ball: Vector2 = snap.ball_position
	match event:
		MatchEvents.EV_PADDLE_HIT:
			shake = maxf(shake, SHAKE_PADDLE)
			rally += 1
			var away := Vector2(-3.0, 0.0) if ball.x > 0.0 else Vector2(3.0, 0.0)
			if ball.x > 0.0:
				paddle_pulse_right = 1.0
			else:
				paddle_pulse_left = 1.0
			spawn_burst(ball, Color(1.0, 0.96, 0.8), 10, away)
		MatchEvents.EV_WALL_HIT:
			shake = maxf(shake, SHAKE_WALL)
			var away := Vector2(0.0, -2.0) if ball.y > 0.0 else Vector2(0.0, 2.0)
			spawn_burst(ball, Color(0.5, 0.68, 0.9), 6, away)
		MatchEvents.EV_EDGE_CLIP:
			shake = maxf(shake, SHAKE_EDGE)
			rally += 1
			spawn_burst(ball, Color(1.0, 0.45, 0.2), 16, Vector2.ZERO)
		MatchEvents.EV_SCORE:
			shake = maxf(shake, SHAKE_SCORE)
			rally = 0
			# The ball is at/behind a goal line; burst inward from that side.
			var inward := Vector2(-4.0, 0.0) if ball.x > 0.0 else Vector2(4.0, 0.0)
			spawn_burst(ball, Color(1.0, 1.0, 1.0), 24, inward)


## Advance decays and particle motion. The rally counter only means something
## inside a live point, so it clears whenever the match isn't PLAYING.
func update(dt: float, state: int) -> void:
	shake *= exp(-SHAKE_DECAY * dt)
	if shake < 0.05:
		shake = 0.0
	paddle_pulse_left = maxf(0.0, paddle_pulse_left - PULSE_DECAY * dt)
	paddle_pulse_right = maxf(0.0, paddle_pulse_right - PULSE_DECAY * dt)
	if state != GameTypes.GameState.PLAYING:
		rally = 0

	var i := particles.size() - 1
	while i >= 0:
		var p: Dictionary = particles[i]
		p["life"] -= dt
		if p["life"] <= 0.0:
			particles.remove_at(i)
		else:
			p["pos"] += p["vel"] * dt
			p["vel"] *= exp(-3.0 * dt)  # drag
		i -= 1


## A radial burst of short-lived squares at a world position, biased along
## `bias` (e.g. away from the surface that was hit).
func spawn_burst(world_pos: Vector2, color: Color, count: int, bias: Vector2) -> void:
	for i in count:
		if particles.size() >= MAX_PARTICLES:
			return
		var angle := _rng.randf_range(0.0, TAU)
		var speed := _rng.randf_range(1.0, 4.5)
		var life := _rng.randf_range(0.25, 0.6)
		particles.append({
			"pos": world_pos,
			"vel": Vector2(cos(angle), sin(angle)) * speed + bias,
			"life": life,
			"max_life": life,
			"size": _rng.randf_range(0.04, 0.11),
			"color": color,
		})


## A per-frame shake offset (screen pixels). Random each call so the shake
## reads as a jitter, not a slide.
func shake_offset() -> Vector2:
	if shake <= 0.0:
		return Vector2.ZERO
	return Vector2(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0)) * shake


## How "hot" the ball is: 0 at launch speed, 1 at the speed cap. Drives the
## tint and squash-stretch so a maxed-out rally is legible at a glance.
static func heat(speed: float) -> float:
	return clampf((speed - GameConfig.BALL_BASE_SPEED)
			/ (GameConfig.BALL_MAX_SPEED - GameConfig.BALL_BASE_SPEED), 0.0, 1.0)


## One point from a win for either side (drives the MATCH POINT banner).
static func is_match_point(left_score: int, right_score: int) -> bool:
	return (maxi(left_score, right_score) == GameConfig.WIN_SCORE - 1
			and maxi(left_score, right_score) >= 0)

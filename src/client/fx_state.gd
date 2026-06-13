## Pure visual-FX state for a match: screen shake, impact particles, paddle hit
## pulses, the rally counter, and ball "heat". Fed by MatchEvents (authoritative
## counter deltas) and ticked with frame time; the renderer only reads and draws.
## No nodes, injectable RNG → unit-testable, like the rest of the client logic.
##
## Rallies are the headline, so the juice ESCALATES: both the shake impulse and the
## particle bursts grow with the rally length and the ball's heat. Hit #20 of a fast
## rally rattles the screen and sprays far more confetti than hit #2, and every fifth
## contact earns a celebratory multi-colour pop (Balatro-style) on top.

const GameConfig := preload("res://src/shared/game_config.gd")
const GameTypes := preload("res://src/shared/game_types.gd")
const MatchEvents := preload("res://src/client/match_events.gd")

# Shake impulse per event (screen pixels) and exponential decay rate.
const SHAKE_PADDLE := 6.0
const SHAKE_WALL := 3.0
const SHAKE_EDGE := 13.0
const SHAKE_SCORE := 18.0
const SHAKE_DECAY := 8.5

# Rally escalation: each contact in the rally and the ball's heat pile onto the
# paddle-hit shake, so the screen kicks harder the longer (and faster) the rally runs.
const SHAKE_RALLY_STEP := 0.8      # added per rally hit
const SHAKE_RALLY_CAP := 14.0      # cap on the rally contribution alone
const SHAKE_HEAT_BONUS := 7.0      # added at full heat
const SHAKE_MAX := 40.0            # overall safety clamp (punchy, not a seizure)

const PULSE_DECAY := 4.0           # paddle hit-flash fade (per second)
const RALLY_PULSE_DECAY := 3.0     # rally-counter "pop" fade (per second)
const RALLY_SHOW_MIN := 3          # show the rally counter from this many hits
const RALLY_MILESTONE := 5         # every Nth contact fires an extra confetti pop
const MAX_PARTICLES := 512

# Spark tint runs from warm-white (cool ball) to hot-orange (fast ball).
const SPARK_COOL := Color(1.00, 0.96, 0.80)
const SPARK_HOT := Color(1.00, 0.45, 0.20)

# Celebration confetti palette (scores + milestone rallies) — multi-colour like Balatro.
const CONFETTI := [
	Color(0.36, 0.80, 1.00),  # cool blue (P1)
	Color(1.00, 0.50, 0.32),  # warm orange (P2)
	Color(1.00, 0.85, 0.35),  # gold
	Color(0.55, 0.95, 0.60),  # green
	Color(1.00, 1.00, 1.00),  # white
]

var shake := 0.0               # current shake magnitude (pixels)
var paddle_pulse_left := 0.0   # 1 → just hit, fades to 0
var paddle_pulse_right := 0.0
var rally := 0                 # paddle contacts in the current point
var rally_pulse := 0.0         # 1 → just incremented, fades (renderer pops the counter)
var particles: Array = []      # {pos, vel (world u/s), life, max_life, size (world u),
                               #  color, rot (rad), spin (rad/s), grav (world u/s², Y-up)}

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
	rally_pulse = 0.0
	particles.clear()


## React to one authoritative event. snap supplies the ball position/velocity so
## bursts land where the contact happened and scale with how fast the ball is going.
func apply_event(event: String, snap) -> void:
	var ball: Vector2 = snap.ball_position
	var ball_heat := heat(snap.ball_velocity.length())
	match event:
		MatchEvents.EV_PADDLE_HIT:
			rally += 1
			rally_pulse = 1.0
			if ball.x > 0.0:
				paddle_pulse_right = 1.0
			else:
				paddle_pulse_left = 1.0
			# Shake builds with the rally length and the ball's heat.
			var impulse := SHAKE_PADDLE \
					+ minf(rally * SHAKE_RALLY_STEP, SHAKE_RALLY_CAP) \
					+ ball_heat * SHAKE_HEAT_BONUS
			_add_shake(impulse)
			# Sparks fly back off the struck face; more (and bigger) the hotter the rally.
			var away := Vector2(-3.0, 0.0) if ball.x > 0.0 else Vector2(3.0, 0.0)
			var count := mini(10 + rally + int(ball_heat * 14.0), 44)
			spawn_burst(ball, SPARK_COOL.lerp(SPARK_HOT, ball_heat), count, away,
					1.0 + ball_heat, 1.0 + 0.7 * ball_heat, -2.5)
			# Milestone rallies earn a celebratory confetti pop and an extra kick.
			if rally % RALLY_MILESTONE == 0:
				_add_shake(impulse + 7.0)
				spawn_confetti(ball, 16 + rally, Vector2(0.0, 1.5))
		MatchEvents.EV_WALL_HIT:
			_add_shake(SHAKE_WALL + ball_heat * 2.0)
			var away := Vector2(0.0, -2.5) if ball.y > 0.0 else Vector2(0.0, 2.5)
			spawn_burst(ball, Color(0.55, 0.72, 0.95), 8, away, 1.0 + 0.5 * ball_heat, 1.0, -1.0)
		MatchEvents.EV_EDGE_CLIP:
			rally += 1
			rally_pulse = 1.0
			_add_shake(SHAKE_EDGE + ball_heat * SHAKE_HEAT_BONUS)
			spawn_burst(ball, SPARK_HOT, 22, Vector2.ZERO, 1.4, 1.2, -1.0)
		MatchEvents.EV_SCORE:
			rally = 0
			rally_pulse = 0.0
			_add_shake(SHAKE_SCORE)
			# Big confetti explosion inward from the goal line the ball just crossed.
			var inward := Vector2(-4.0, 0.0) if ball.x > 0.0 else Vector2(4.0, 0.0)
			spawn_confetti(ball, 48, inward)


## Advance decays and particle motion. The rally counter only means something
## inside a live point, so it clears whenever the match isn't PLAYING.
func update(dt: float, state: int) -> void:
	shake *= exp(-SHAKE_DECAY * dt)
	if shake < 0.05:
		shake = 0.0
	paddle_pulse_left = maxf(0.0, paddle_pulse_left - PULSE_DECAY * dt)
	paddle_pulse_right = maxf(0.0, paddle_pulse_right - PULSE_DECAY * dt)
	rally_pulse = maxf(0.0, rally_pulse - RALLY_PULSE_DECAY * dt)
	if state != GameTypes.GameState.PLAYING:
		rally = 0

	var i := particles.size() - 1
	while i >= 0:
		var p: Dictionary = particles[i]
		p["life"] -= dt
		if p["life"] <= 0.0:
			particles.remove_at(i)
		else:
			p["vel"] += Vector2(0.0, p["grav"]) * dt   # gravity (world Y is up → grav<0 falls)
			p["pos"] += p["vel"] * dt
			p["vel"] *= exp(-2.2 * dt)                 # drag → confetti settles into a drift
			p["rot"] += p["spin"] * dt
		i -= 1


func _add_shake(amount: float) -> void:
	shake = minf(SHAKE_MAX, maxf(shake, amount))


## A radial burst of short-lived, tumbling squares at a world position, biased along
## `bias` (e.g. away from the struck surface). speed_scale/size_scale grow the burst
## with the rally's heat; `gravity` (negative = falls) and per-particle spin give the
## debris its arc and tumble.
func spawn_burst(world_pos: Vector2, color: Color, count: int, bias: Vector2,
		speed_scale := 1.0, size_scale := 1.0, gravity := 0.0) -> void:
	for i in count:
		if particles.size() >= MAX_PARTICLES:
			return
		var angle := _rng.randf_range(0.0, TAU)
		var speed := _rng.randf_range(1.0, 4.5) * speed_scale
		var life := _rng.randf_range(0.3, 0.7)
		particles.append({
			"pos": world_pos,
			"vel": Vector2(cos(angle), sin(angle)) * speed + bias,
			"life": life,
			"max_life": life,
			"size": _rng.randf_range(0.05, 0.13) * size_scale,
			"color": color,
			"rot": _rng.randf_range(0.0, TAU),
			"spin": _rng.randf_range(-14.0, 14.0),
			"grav": gravity,
		})


## A celebratory multi-colour confetti explosion — bigger, longer-lived squares that
## arc out and rain back down. Fired on scores and milestone rallies.
func spawn_confetti(world_pos: Vector2, count: int, bias: Vector2) -> void:
	for i in count:
		if particles.size() >= MAX_PARTICLES:
			return
		var angle := _rng.randf_range(0.0, TAU)
		var speed := _rng.randf_range(2.0, 8.0)
		var life := _rng.randf_range(0.5, 1.2)
		particles.append({
			"pos": world_pos,
			"vel": Vector2(cos(angle), sin(angle)) * speed + bias,
			"life": life,
			"max_life": life,
			"size": _rng.randf_range(0.07, 0.18),
			"color": CONFETTI[_rng.randi() % CONFETTI.size()],
			"rot": _rng.randf_range(0.0, TAU),
			"spin": _rng.randf_range(-18.0, 18.0),
			"grav": -7.0,
		})


## A per-frame shake offset (screen pixels). Random each call so the shake
## reads as a jitter, not a slide.
func shake_offset() -> Vector2:
	if shake <= 0.0:
		return Vector2.ZERO
	return Vector2(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0)) * shake


## How "hot" the ball is: 0 at launch speed, 1 at the heat-reference speed — and the
## ball keeps getting faster past that, heat just saturates. Drives the tint,
## squash-stretch, shake and particle intensity so a roaring rally reads at a glance.
static func heat(speed: float) -> float:
	return clampf((speed - GameConfig.BALL_BASE_SPEED)
			/ (GameConfig.BALL_HEAT_REF_SPEED - GameConfig.BALL_BASE_SPEED), 0.0, 1.0)


## One point from a win for either side (drives the MATCH POINT banner).
static func is_match_point(left_score: int, right_score: int) -> bool:
	return (maxi(left_score, right_score) == GameConfig.WIN_SCORE - 1
			and maxi(left_score, right_score) >= 0)

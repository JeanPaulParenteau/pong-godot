## Interpolation buffer for remote state (ball + opponent paddle). Stores
## timestamped snapshots (deduped by server tick) and samples an interpolated
## snapshot at a render time slightly in the past, so motion is smooth between
## the 30 Hz server updates even with jitter. Pure (no node lifecycle) —
## unit-tested headlessly.

const MatchSnapshot := preload("res://src/shared/match_snapshot.gd")

# If two consecutive ball positions are farther apart than this, it's a teleport
# (serve reset / score), not motion — snap instead of sliding across the field.
const TELEPORT_DISTANCE := 3.0
const CAPACITY := 32

var _times: Array[float] = []
var _snaps := []  # MatchSnapshot, parallel to _times
var _last_tick := -(1 << 62)


func count() -> int:
	return _snaps.size()


## Record a snapshot at the given client time. Ignores repeats of the same server tick.
func add(time: float, snap) -> void:
	if snap.tick == _last_tick:
		return
	_last_tick = snap.tick
	_times.append(time)
	_snaps.append(snap)
	if _snaps.size() > CAPACITY:
		_times.pop_front()
		_snaps.pop_front()


func clear() -> void:
	_times.clear()
	_snaps.clear()
	_last_tick = -(1 << 62)


## Sample an interpolated snapshot at target_time. Returns null only when empty.
## Clamps to the ends; interpolates ball + paddle positions between the two
## bracketing snapshots (snapping the ball on teleports).
func try_sample(target_time: float):  # -> MatchSnapshot or null
	if _snaps.is_empty():
		return null
	if _snaps.size() == 1 or target_time <= _times[0]:
		return _snaps[0]

	var last := _snaps.size() - 1
	if target_time >= _times[last]:
		return _snaps[last]

	for i in last:
		if target_time >= _times[i] and target_time <= _times[i + 1]:
			var span := _times[i + 1] - _times[i]
			var t := (target_time - _times[i]) / span if span > 1e-6 else 0.0
			return interpolate(_snaps[i], _snaps[i + 1], t)
	return _snaps[last]


## Interpolate continuous fields (ball/paddle positions); take discrete fields
## from the newer snapshot.
static func interpolate(a, b, t: float):  # -> MatchSnapshot
	var ball: Vector2
	if a.ball_position.distance_to(b.ball_position) > TELEPORT_DISTANCE:
		ball = b.ball_position  # teleport (serve/score reset) — don't slide across the field
	else:
		ball = a.ball_position.lerp(b.ball_position, t)

	var snap = MatchSnapshot.new()
	snap.state = b.state
	snap.ball_position = ball
	snap.ball_velocity = b.ball_velocity
	snap.left_paddle_y = lerpf(a.left_paddle_y, b.left_paddle_y, t)
	snap.right_paddle_y = lerpf(a.right_paddle_y, b.right_paddle_y, t)
	snap.left_score = b.left_score
	snap.right_score = b.right_score
	snap.serve_countdown = b.serve_countdown
	snap.game_over_reason = b.game_over_reason
	snap.winning_side = b.winning_side
	snap.paddle_hits = b.paddle_hits
	snap.wall_hits = b.wall_hits
	snap.edge_clips = b.edge_clips
	snap.match_id = b.match_id
	snap.tick = b.tick
	return snap

# GdUnit4 suite — SnapshotBuffer: the client interpolation buffer that smooths
# network jitter. Ported from the legacy runner.
extends GdUnitTestSuite

const GameTypes = preload("res://src/shared/game_types.gd")
const MatchSnapshot = preload("res://src/shared/match_snapshot.gd")
const SnapshotBuffer = preload("res://src/client/snapshot_buffer.gd")


func _snap_at(tick: int, ball: Vector2, left_y := 0.0) -> MatchSnapshot:
	var s := MatchSnapshot.new()
	s.tick = tick
	s.ball_position = ball
	s.left_paddle_y = left_y
	s.state = GameTypes.GameState.PLAYING
	return s


func test_empty_buffer_has_no_sample() -> void:
	assert_object(SnapshotBuffer.new().try_sample(0.0)).is_null()


func test_duplicate_ticks_are_deduped() -> void:
	var buf := SnapshotBuffer.new()
	buf.add(1.0, _snap_at(1, Vector2(0, 0)))
	buf.add(2.0, _snap_at(2, Vector2(1, 0)))
	buf.add(2.0, _snap_at(2, Vector2(9, 9)))  # same tick again
	assert_int(buf.count()).is_equal(2)


func test_samples_interpolate_between_snapshots_and_clamp_at_the_ends() -> void:
	var buf := SnapshotBuffer.new()
	buf.add(1.0, _snap_at(1, Vector2(0, 0), 0.0))
	buf.add(2.0, _snap_at(2, Vector2(1, 0), 1.0))
	var mid = buf.try_sample(1.5)
	assert_float(mid.ball_position.x).is_equal_approx(0.5, 1e-4)
	assert_float(mid.left_paddle_y).is_equal_approx(0.5, 1e-4)
	assert_vector(buf.try_sample(0.5).ball_position).is_equal(Vector2(0, 0))  # oldest
	assert_vector(buf.try_sample(3.0).ball_position).is_equal(Vector2(1, 0))  # newest


func test_a_teleport_snaps_instead_of_sliding() -> void:
	# A serve reset moves the ball across the field in one tick — interpolating
	# that would show the ball sweeping through the play field.
	var buf := SnapshotBuffer.new()
	buf.add(1.0, _snap_at(1, Vector2(7, 0)))
	buf.add(2.0, _snap_at(2, Vector2(0, 0)))
	assert_vector(buf.try_sample(1.5).ball_position).is_equal(Vector2(0, 0))

# GdUnit4 suite — MatchEvents: monotonic counters -> discrete events, with the
# priming semantics that stop history replaying on (re)connect. Ported from the
# legacy runner.
extends GdUnitTestSuite

const GameTypes = preload("res://src/shared/game_types.gd")
const MatchSnapshot = preload("res://src/shared/match_snapshot.gd")
const MatchEvents = preload("res://src/client/match_events.gd")


func _snap(paddle := 0, wall := 0, edge := 0, left := 0, right := 0) -> MatchSnapshot:
	var s := MatchSnapshot.new()
	s.paddle_hits = paddle
	s.wall_hits = wall
	s.edge_clips = edge
	s.left_score = left
	s.right_score = right
	s.state = GameTypes.GameState.PLAYING
	return s


func test_first_snapshot_only_primes_and_stillness_is_silent() -> void:
	var det := MatchEvents.new()
	assert_array(det.process(_snap(5, 3, 1, 2, 2))).is_empty()
	assert_array(det.process(_snap(5, 3, 1, 2, 2))).is_empty()


func test_a_paddle_counter_bump_emits_a_paddle_event() -> void:
	var det := MatchEvents.new()
	det.process(_snap(5, 3, 1, 2, 2))
	assert_array(det.process(_snap(6, 3, 1, 2, 2))).is_equal([MatchEvents.EV_PADDLE_HIT])


func test_an_edge_clip_suppresses_the_same_frame_paddle_event() -> void:
	var det := MatchEvents.new()
	det.process(_snap(6, 3, 1, 2, 2))
	assert_array(det.process(_snap(7, 3, 2, 2, 2))).is_equal([MatchEvents.EV_EDGE_CLIP])


func test_wall_and_score_in_one_frame_both_emit() -> void:
	var det := MatchEvents.new()
	det.process(_snap(7, 3, 2, 2, 2))
	var events := det.process(_snap(7, 4, 2, 3, 2))
	assert_array(events).contains([MatchEvents.EV_WALL_HIT, MatchEvents.EV_SCORE])
	assert_int(events.size()).is_equal(2)


func test_a_counter_regression_re_primes_silently_then_resumes() -> void:
	# A new match on the same source (solo rematch) drops the counters.
	var det := MatchEvents.new()
	det.process(_snap(7, 4, 2, 3, 2))
	assert_array(det.process(_snap(0, 0, 0, 0, 0))).is_empty()
	assert_array(det.process(_snap(1, 0, 0, 0, 0))).is_equal([MatchEvents.EV_PADDLE_HIT])


func test_reset_re_primes() -> void:
	var det := MatchEvents.new()
	det.process(_snap(1, 0, 0, 0, 0))
	det.reset()
	assert_array(det.process(_snap(9, 9, 9, 4, 1))).is_empty()

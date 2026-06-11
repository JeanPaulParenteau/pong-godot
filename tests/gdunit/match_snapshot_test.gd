# GdUnit4 suite — MatchSnapshot's flat-array wire encoding (to_wire/from_wire are
# exact inverses). Ported from the legacy runner.
extends GdUnitTestSuite

const GameSession = preload("res://src/shared/game_session.gd")
const MatchSnapshot = preload("res://src/shared/match_snapshot.gd")

const DT := 1.0 / 30.0


func test_a_live_session_snapshot_survives_the_wire() -> void:
	var s := GameSession.new()
	s.add_player()
	s.add_player()
	for i in 50:
		s.tick(DT)
	var snap = MatchSnapshot.from_session(s, 7, 42)
	var back = MatchSnapshot.from_wire(snap.to_wire())
	assert_object(back).is_not_null()
	assert_int(back.state).is_equal(snap.state)
	assert_int(back.tick).is_equal(42)
	assert_int(back.match_id).is_equal(7)
	assert_vector(back.ball_position).is_equal(snap.ball_position)
	assert_vector(back.ball_velocity).is_equal(snap.ball_velocity)
	assert_int(back.left_score).is_equal(snap.left_score)
	assert_int(back.right_score).is_equal(snap.right_score)


func test_a_short_wire_payload_is_rejected() -> void:
	assert_object(MatchSnapshot.from_wire([1, 2, 3])).is_null()

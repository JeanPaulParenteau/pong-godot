# GdUnit4 suite — AutoClient's smoke OBSERVATION logic (side seen, Playing
# reached, ball moved), driven through a stub OnlineMatch. The verdict/quit path
# (_finish) calls get_tree().quit() and the connect path opens a real ENet socket,
# so neither runs here — the flags they read are the decision logic under test.
extends GdUnitTestSuite

const AutoClient = preload("res://src/client/autoclient.gd")
const GameTypes = preload("res://src/shared/game_types.gd")
const MatchSnapshot = preload("res://src/shared/match_snapshot.gd")


## Stands in for OnlineMatch: tests script side/state/ball per observation.
class StubOnline extends Node:
	var side: int = GameTypes.NO_SIDE
	var snap = MatchSnapshot.new()
	var with_match := false

	func local_side() -> int:
		return side

	func has_match() -> bool:
		return with_match

	func snapshot():
		return snap


var _auto: AutoClient
var _online: StubOnline


func before_test() -> void:
	_auto = auto_free(AutoClient.new())
	_online = auto_free(StubOnline.new())
	add_child(_auto)
	add_child(_online)
	_auto.set_process(false)  # engine frames would hit _process with no _config
	_auto._online = _online


func test_nothing_observed_before_any_state_arrives() -> void:
	_auto._observe_and_log()
	assert_bool(_auto._saw_side).is_false()
	assert_bool(_auto._saw_playing).is_false()
	assert_bool(_auto._ball_moved).is_false()


func test_an_assigned_side_is_recorded() -> void:
	_online.side = GameTypes.PlayerSide.RIGHT
	_auto._observe_and_log()
	assert_bool(_auto._saw_side).is_true()


func test_reaching_playing_is_recorded() -> void:
	_online.with_match = true
	_online.snap.state = GameTypes.GameState.PLAYING
	_auto._observe_and_log()
	assert_bool(_auto._saw_playing).is_true()


func test_a_static_ball_does_not_count_as_movement() -> void:
	_online.with_match = true
	_online.snap.state = GameTypes.GameState.PLAYING
	_online.snap.ball_position = Vector2(1, 1)
	_auto._observe_and_log()
	_auto._observe_and_log()  # same position twice
	assert_bool(_auto._ball_moved).is_false()


func test_ball_movement_across_observations_is_recorded() -> void:
	_online.with_match = true
	_online.snap.state = GameTypes.GameState.PLAYING
	_online.snap.ball_position = Vector2(1, 1)
	_auto._observe_and_log()
	_online.snap.ball_position = Vector2(2, 1)
	_auto._observe_and_log()
	assert_bool(_auto._ball_moved).is_true()


func test_non_playing_states_do_not_count_as_playing() -> void:
	_online.with_match = true
	_online.snap.state = GameTypes.GameState.SERVING
	_auto._observe_and_log()
	assert_bool(_auto._saw_playing).is_false()

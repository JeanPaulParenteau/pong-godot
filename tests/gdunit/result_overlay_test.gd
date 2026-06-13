# GdUnit4 suite — ResultOverlay.model(): the pure classifier that decides the
# game-over result card's content from MatchSource state + snapshot. One source of
# truth for both solo and online, replacing the divergent solo-card / online-banner
# paths. The Control half is covered for layout by menu_layout_test.gd.
extends GdUnitTestSuite

const ResultOverlay = preload("res://src/client/result_overlay.gd")
const GameTypes = preload("res://src/shared/game_types.gd")
const MatchSnapshot = preload("res://src/shared/match_snapshot.gd")


## Stand-in for a match source (the snapshot()/local_side()/is_local() contract).
class StubSource:
	var snap
	var side: int
	var local: bool

	func _init(p_snap, p_side: int, p_local: bool) -> void:
		snap = p_snap
		side = p_side
		local = p_local

	func snapshot():
		return snap

	func local_side() -> int:
		return side

	func is_local() -> bool:
		return local


func _snap(winning: int, left: int, right: int, reason := GameTypes.GameOverReason.WIN,
		state := GameTypes.GameState.GAME_OVER) -> MatchSnapshot:
	var s := MatchSnapshot.new()
	s.state = state
	s.winning_side = winning
	s.game_over_reason = reason
	s.left_score = left
	s.right_score = right
	return s


func test_solo_win_offers_rematch_difficulty_and_menu() -> void:
	var snap := _snap(GameTypes.PlayerSide.LEFT, 5, 2)
	var m := ResultOverlay.model(StubSource.new(snap, GameTypes.PlayerSide.LEFT, true), snap)
	assert_str(m["title"]).is_equal("YOU WIN!")
	assert_str(m["primary"]["label"]).is_equal("Rematch")
	assert_str(m["secondary"]["label"]).is_equal("Main Menu")
	assert_bool(m["show_difficulty"]).is_true()
	assert_str(m["hint"]).is_empty()


func test_solo_loss_titles_cpu_wins() -> void:
	var snap := _snap(GameTypes.PlayerSide.RIGHT, 2, 5)
	var m := ResultOverlay.model(StubSource.new(snap, GameTypes.PlayerSide.LEFT, true), snap)
	assert_str(m["title"]).is_equal("CPU WINS")


func test_online_win_offers_find_new_game_leave_and_rematching_hint() -> void:
	var snap := _snap(GameTypes.PlayerSide.LEFT, 5, 2)
	var m := ResultOverlay.model(StubSource.new(snap, GameTypes.PlayerSide.LEFT, false), snap)
	assert_str(m["title"]).is_equal("YOU WIN!")
	assert_str(m["primary"]["label"]).is_equal("Find new game")
	assert_str(m["secondary"]["label"]).is_equal("Leave")
	assert_bool(m["show_difficulty"]).is_false()
	assert_str(m["hint"]).is_equal("Rematching...")


func test_online_loss_uses_local_side_perspective() -> void:
	var snap := _snap(GameTypes.PlayerSide.LEFT, 5, 2)  # left wins
	var m := ResultOverlay.model(StubSource.new(snap, GameTypes.PlayerSide.RIGHT, false), snap)
	assert_str(m["title"]).is_equal("YOU LOSE")


func test_opponent_left_title() -> void:
	var snap := _snap(GameTypes.NO_SIDE, 3, 1, GameTypes.GameOverReason.OPPONENT_LEFT)
	var m := ResultOverlay.model(StubSource.new(snap, GameTypes.PlayerSide.LEFT, false), snap)
	assert_str(m["title"]).is_equal("Opponent left")


func test_not_visible_until_game_over() -> void:
	var snap := _snap(GameTypes.NO_SIDE, 0, 0, GameTypes.GameOverReason.NONE, GameTypes.GameState.PLAYING)
	var m := ResultOverlay.model(StubSource.new(snap, GameTypes.PlayerSide.LEFT, true), snap)
	assert_bool(m["visible"]).is_false()


func test_subtitle_is_local_perspective_score() -> void:
	var snap := _snap(GameTypes.PlayerSide.LEFT, 5, 2)
	var solo := ResultOverlay.model(StubSource.new(snap, GameTypes.PlayerSide.LEFT, true), snap)
	assert_str(solo["subtitle"]).is_equal("5 – 2")  # near (left) first
	var online_right := ResultOverlay.model(StubSource.new(snap, GameTypes.PlayerSide.RIGHT, false), snap)
	assert_str(online_right["subtitle"]).is_equal("2 – 5")  # right player sees their score first

# GdUnit4 suite — LocalMatch (offline solo). The node is driven deterministically:
# _process(delta) is called directly with fixed deltas (no engine frame timing), and
# game-over scenarios are forced through GameSession's teleport_ball test seam, so
# nothing here depends on bot behaviour or wall-clock time.
extends GdUnitTestSuite

const LocalMatch = preload("res://src/client/local_match.gd")
const BotProfile = preload("res://src/shared/bot_profile.gd")
const GameConfig = preload("res://src/shared/game_config.gd")
const GameTypes = preload("res://src/shared/game_types.gd")
const MatchSource = preload("res://src/shared/match_source.gd")
const PaddleInput = preload("res://src/client/paddle_input.gd")

var _lm: LocalMatch


func before_test() -> void:
	MatchSource.current = null
	PaddleInput.clear_local_target()
	_lm = auto_free(LocalMatch.new())
	add_child(_lm)  # in-tree so get_viewport() is valid inside _process


func after_test() -> void:
	MatchSource.current = null


## Tick the session past the serve countdown into PLAYING.
func _advance_past_serve() -> void:
	for i in int(GameConfig.SERVE_DELAY * GameConfig.TICK_RATE) + 1:
		_lm._step_once()


func test_snapshot_before_begin_is_the_empty_waiting_state() -> void:
	assert_int(_lm.snapshot().state).is_equal(GameTypes.GameState.WAITING_FOR_PLAYERS)


func test_local_player_is_the_left_paddle_with_zero_latency() -> void:
	assert_int(_lm.local_side()).is_equal(GameTypes.PlayerSide.LEFT)
	assert_bool(_lm.is_local()).is_true()


func test_begin_publishes_itself_as_the_active_match_source() -> void:
	_lm.begin(BotProfile.medium())
	assert_bool(_lm.active).is_true()
	assert_object(MatchSource.current).is_same(_lm)


func test_begin_seats_both_players_so_the_match_is_serving() -> void:
	_lm.begin(BotProfile.medium())
	assert_int(_lm.snapshot().state).is_equal(GameTypes.GameState.SERVING)


func test_process_ticks_the_session_on_the_fixed_step() -> void:
	_lm.begin(BotProfile.medium())
	for i in 35:  # > SERVE_DELAY worth of 30 Hz frames
		_lm._process(_lm._dt)
	var snap = _lm.snapshot()
	assert_int(snap.tick).is_greater(0)
	assert_int(snap.state).is_equal(GameTypes.GameState.PLAYING)


func test_cpu_reaching_win_score_finishes_with_cpu_wins_text() -> void:
	_lm.begin(BotProfile.medium())
	_advance_past_serve()
	_lm._session.right_score = GameConfig.WIN_SCORE - 1
	# Ball about to cross the left goal line, past the paddle plane → CPU's point.
	_lm._session.teleport_ball(Vector2(-7.8, 0), Vector2(-6, 0))
	_lm._step_once()
	assert_bool(_lm.finished).is_true()
	assert_str(_lm.result_text).contains("CPU WINS")
	assert_str(_lm.result_text).contains("0–%d" % GameConfig.WIN_SCORE)


func test_human_reaching_win_score_finishes_with_you_win_text() -> void:
	_lm.begin(BotProfile.medium())
	_advance_past_serve()
	_lm._session.left_score = GameConfig.WIN_SCORE - 1
	_lm._session.teleport_ball(Vector2(7.8, 0), Vector2(6, 0))
	_lm._step_once()
	assert_bool(_lm.finished).is_true()
	assert_str(_lm.result_text).contains("YOU WIN!")


func test_finished_match_freezes_instead_of_auto_rematching() -> void:
	_lm.begin(BotProfile.medium())
	_advance_past_serve()
	_lm._session.left_score = GameConfig.WIN_SCORE - 1
	_lm._session.teleport_ball(Vector2(7.8, 0), Vector2(6, 0))
	_lm._step_once()
	var tick_at_game_over: int = _lm.snapshot().tick
	_lm._process(1.0)  # a whole second of frames must not tick the session further
	assert_int(_lm.snapshot().tick).is_equal(tick_at_game_over)


func test_stop_clears_the_source_and_the_leftover_input() -> void:
	_lm.begin(BotProfile.medium())
	PaddleInput.local_target_y = 1.0
	_lm.stop()
	assert_bool(_lm.active).is_false()
	assert_object(MatchSource.current).is_null()
	assert_bool(PaddleInput.has_local_target()).is_false()


func test_leaving_the_tree_mid_match_stops_cleanly() -> void:
	_lm.begin(BotProfile.medium())
	remove_child(_lm)  # _exit_tree on an active match behaves like stop()
	assert_bool(_lm.active).is_false()
	assert_object(MatchSource.current).is_null()
	add_child(_lm)  # re-parent so the orphan monitor sees a clean tree

# GdUnit4 suite — FxState: shake/pulse/rally/particle bookkeeping driven by the
# authoritative event stream. Seeded RNG. Ported from the legacy runner.
extends GdUnitTestSuite

const GameConfig = preload("res://src/shared/game_config.gd")
const GameTypes = preload("res://src/shared/game_types.gd")
const MatchSnapshot = preload("res://src/shared/match_snapshot.gd")
const MatchEvents = preload("res://src/client/match_events.gd")
const FxState = preload("res://src/client/fx_state.gd")


func _fx() -> FxState:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	return FxState.new(rng)


func _snap(paddle := 0, wall := 0, edge := 0, left := 0, right := 0,
		ball := Vector2.ZERO) -> MatchSnapshot:
	var s := MatchSnapshot.new()
	s.paddle_hits = paddle
	s.wall_hits = wall
	s.edge_clips = edge
	s.left_score = left
	s.right_score = right
	s.ball_position = ball
	s.state = GameTypes.GameState.PLAYING
	return s


func test_a_paddle_hit_shakes_pulses_the_struck_side_and_spawns_particles() -> void:
	var fx := _fx()
	fx.apply_event(MatchEvents.EV_PADDLE_HIT, _snap(1, 0, 0, 0, 0, Vector2(7.0, 0.0)))
	assert_float(fx.shake).is_greater(0.0)
	assert_int(fx.rally).is_equal(1)
	assert_float(fx.paddle_pulse_right).is_equal(1.0)
	assert_float(fx.paddle_pulse_left).is_equal(0.0)
	assert_bool(fx.particles.is_empty()).is_false()


func test_shake_and_pulse_decay_while_the_rally_persists() -> void:
	var fx := _fx()
	fx.apply_event(MatchEvents.EV_PADDLE_HIT, _snap(1, 0, 0, 0, 0, Vector2(7.0, 0.0)))
	var shake_before: float = fx.shake
	fx.update(0.1, GameTypes.GameState.PLAYING)
	assert_float(fx.shake).is_less(shake_before)
	assert_float(fx.paddle_pulse_right).is_less(1.0)
	assert_int(fx.rally).is_equal(1)


func test_scores_and_non_playing_states_reset_the_rally() -> void:
	var fx := _fx()
	fx.apply_event(MatchEvents.EV_PADDLE_HIT, _snap(1, 0, 0, 0, 0, Vector2(7.0, 0.0)))
	fx.apply_event(MatchEvents.EV_SCORE, _snap(1, 0, 0, 1, 0, Vector2(8.0, 0.0)))
	assert_int(fx.rally).is_equal(0)
	fx.apply_event(MatchEvents.EV_PADDLE_HIT, _snap(2, 0, 0, 1, 0, Vector2(-7.0, 0.0)))
	assert_float(fx.paddle_pulse_left).is_equal(1.0)  # hit at -x pulses the left paddle
	fx.update(0.1, GameTypes.GameState.SERVING)
	assert_int(fx.rally).is_equal(0)


func test_particles_expire_and_shake_settles() -> void:
	var fx := _fx()
	fx.apply_event(MatchEvents.EV_PADDLE_HIT, _snap(1, 0, 0, 0, 0, Vector2(7.0, 0.0)))
	for i in 80:
		fx.update(0.05, GameTypes.GameState.PLAYING)
	assert_bool(fx.particles.is_empty()).is_true()
	assert_float(fx.shake).is_equal(0.0)


func test_clear_wipes_all_fx() -> void:
	var fx := _fx()
	fx.apply_event(MatchEvents.EV_EDGE_CLIP, _snap(3, 0, 1, 1, 0))
	fx.clear()
	assert_bool(fx.particles.is_empty()).is_true()
	assert_float(fx.shake).is_equal(0.0)
	assert_int(fx.rally).is_equal(0)


func test_heat_maps_launch_speed_to_zero_and_the_cap_to_one() -> void:
	assert_float(FxState.heat(GameConfig.BALL_BASE_SPEED)).is_equal_approx(0.0, 1e-4)
	assert_float(FxState.heat(GameConfig.BALL_MAX_SPEED)).is_equal_approx(1.0, 1e-4)
	assert_float(FxState.heat(0.0)).is_equal_approx(0.0, 1e-4)  # clamps below


func test_match_point_lights_at_win_minus_one_for_either_side() -> void:
	assert_bool(FxState.is_match_point(GameConfig.WIN_SCORE - 1, 0)).is_true()
	assert_bool(FxState.is_match_point(2, GameConfig.WIN_SCORE - 1)).is_true()
	assert_bool(FxState.is_match_point(GameConfig.WIN_SCORE - 2, GameConfig.WIN_SCORE - 2)).is_false()

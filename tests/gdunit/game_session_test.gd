# GdUnit4 suite — GameSession: the state machine, ball/paddle physics, and the
# pure bounce math. Ported from the legacy runner (tests/run_tests.gd); scenarios
# use a seeded RNG + teleport seams for determinism.
extends GdUnitTestSuite

const GameConfig = preload("res://src/shared/game_config.gd")
const GameTypes = preload("res://src/shared/game_types.gd")
const GameSession = preload("res://src/shared/game_session.gd")

const DT := 1.0 / 30.0


## A session seeded for determinism, ticked into PLAYING.
func _playing_session() -> GameSession:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	var s := GameSession.new(rng)
	s.add_player()
	s.add_player()
	for i in 40:
		s.tick(DT)
		if s.state == GameTypes.GameState.PLAYING:
			break
	return s


# ---- State machine ----

func test_session_starts_waiting_for_players() -> void:
	assert_int(GameSession.new().state).is_equal(GameTypes.GameState.WAITING_FOR_PLAYERS)


func test_seating_fills_left_then_right_and_begins_serving() -> void:
	var s := GameSession.new()
	assert_int(s.add_player()).is_equal(GameTypes.PlayerSide.LEFT)
	assert_int(s.state).is_equal(GameTypes.GameState.WAITING_FOR_PLAYERS)  # one player still waits
	assert_int(s.add_player()).is_equal(GameTypes.PlayerSide.RIGHT)
	assert_int(s.state).is_equal(GameTypes.GameState.SERVING)
	assert_float(s.serve_countdown).is_equal_approx(GameConfig.SERVE_DELAY, 1e-4)
	assert_int(s.add_player()).is_equal(GameTypes.NO_SIDE)  # match is full


func test_serve_countdown_elapses_into_playing_at_base_speed() -> void:
	var s := _playing_session()
	assert_int(s.state).is_equal(GameTypes.GameState.PLAYING)
	assert_float(s.ball_velocity.length()).is_equal_approx(GameConfig.BALL_BASE_SPEED, 1e-3)


func test_opponent_leaving_ends_the_game_with_no_winner() -> void:
	var s := _playing_session()
	s.remove_player(GameTypes.PlayerSide.RIGHT)
	assert_int(s.state).is_equal(GameTypes.GameState.GAME_OVER)
	assert_int(s.last_game_over_reason).is_equal(GameTypes.GameOverReason.OPPONENT_LEFT)
	assert_int(s.winning_side).is_equal(GameTypes.NO_SIDE)


func test_game_over_dwell_with_an_empty_seat_returns_to_waiting() -> void:
	var s := _playing_session()
	s.remove_player(GameTypes.PlayerSide.RIGHT)
	for i in int(GameConfig.GAME_OVER_DELAY / DT) + 2:
		s.tick(DT)
	assert_int(s.state).is_equal(GameTypes.GameState.WAITING_FOR_PLAYERS)


func test_paddle_eases_toward_input_at_capped_speed() -> void:
	var s := _playing_session()
	s.teleport_paddle(GameTypes.PlayerSide.LEFT, 0.0)
	s.set_input(GameTypes.PlayerSide.LEFT, 10.0)  # clamped to PADDLE_MAX_Y on apply
	var before := s.left_paddle_y
	s.tick(DT)
	assert_float(s.left_paddle_y - before).is_equal_approx(GameConfig.PADDLE_SPEED * DT, 1e-4)


# ---- Ball physics ----

func test_wall_bounce_reflects_y_counts_and_clamps() -> void:
	var s := _playing_session()
	s.teleport_ball(Vector2(0.0, GameConfig.BALL_MAX_Y - 0.05), Vector2(0.0, 5.0))
	var walls := s.wall_hit_count
	s.tick(DT)
	assert_float(s.ball_velocity.y).is_less(0.0)
	assert_int(s.wall_hit_count).is_equal(walls + 1)
	assert_float(s.ball_position.y).is_less_equal(GameConfig.BALL_MAX_Y + 1e-5)


func test_front_face_bounce_reflects_x_speeds_up_and_reseats() -> void:
	var s := _playing_session()
	s.teleport_paddle(GameTypes.PlayerSide.RIGHT, 0.0)
	s.set_input(GameTypes.PlayerSide.RIGHT, 0.0)
	s.teleport_ball(Vector2(GameConfig.PADDLE_X - GameConfig.BALL_RADIUS - 0.1, 0.0), Vector2(8.0, 0.0))
	var hits := s.paddle_hit_count
	s.tick(DT)
	assert_float(s.ball_velocity.x).is_less(0.0)
	assert_int(s.paddle_hit_count).is_equal(hits + 1)
	assert_float(s.ball_velocity.length()).is_equal_approx(8.0 + GameConfig.BALL_SPEED_STEP, 1e-3)
	assert_float(s.ball_position.x).is_equal_approx(GameConfig.PADDLE_X - GameConfig.BALL_RADIUS, 1e-4)


func test_a_fast_ball_cannot_tunnel_through_the_paddle() -> void:
	# Leading-edge sweep: any face crossing is caught regardless of step size.
	var s := _playing_session()
	s.teleport_paddle(GameTypes.PlayerSide.RIGHT, 0.0)
	s.set_input(GameTypes.PlayerSide.RIGHT, 0.0)
	s.teleport_ball(Vector2(GameConfig.PADDLE_X - 2.0, 0.0), Vector2(120.0, 0.0))
	s.tick(DT)
	assert_float(s.ball_velocity.x).is_less(0.0)


func test_edge_clip_keeps_heading_and_concedes_the_point() -> void:
	var s := _playing_session()
	s.teleport_paddle(GameTypes.PlayerSide.RIGHT, 0.0)
	s.set_input(GameTypes.PlayerSide.RIGHT, 0.0)
	s.teleport_ball(Vector2(GameConfig.PADDLE_X - GameConfig.BALL_RADIUS - 0.1, 1.0), Vector2(8.0, 0.0))
	var clips := s.edge_clip_count
	var left_score := s.left_score
	s.tick(DT)
	assert_int(s.edge_clip_count).is_equal(clips + 1)
	assert_float(s.ball_velocity.x).is_greater(0.0)  # still heading for the goal behind the paddle
	for i in 30:
		if s.left_score != left_score:
			break
		s.tick(DT)
	assert_int(s.left_score).is_equal(left_score + 1)  # the self-score


func test_clean_miss_scores_and_serves_again() -> void:
	var s := _playing_session()
	s.teleport_paddle(GameTypes.PlayerSide.RIGHT, GameConfig.PADDLE_MIN_Y)
	s.set_input(GameTypes.PlayerSide.RIGHT, GameConfig.PADDLE_MIN_Y)
	s.teleport_ball(Vector2(GameConfig.PADDLE_X - 0.5, 3.0), Vector2(10.0, 0.0))
	for i in 30:
		if s.left_score == 1:
			break
		s.tick(DT)
	assert_int(s.left_score).is_equal(1)
	assert_int(s.state).is_equal(GameTypes.GameState.SERVING)


func test_win_score_ends_the_game_and_a_full_dwell_rematches_at_zero() -> void:
	var s := _playing_session()
	for point in GameConfig.WIN_SCORE:
		for i in 200:  # ride out the serve countdown
			if s.state == GameTypes.GameState.PLAYING:
				break
			s.tick(DT)
		s.teleport_paddle(GameTypes.PlayerSide.RIGHT, GameConfig.PADDLE_MIN_Y)
		s.set_input(GameTypes.PlayerSide.RIGHT, GameConfig.PADDLE_MIN_Y)
		s.teleport_ball(Vector2(GameConfig.PADDLE_X - 0.5, 3.0), Vector2(12.0, 0.0))
		for i in 60:
			if s.state != GameTypes.GameState.PLAYING:
				break
			s.tick(DT)
	assert_int(s.state).is_equal(GameTypes.GameState.GAME_OVER)
	assert_int(s.last_game_over_reason).is_equal(GameTypes.GameOverReason.WIN)
	assert_int(s.winning_side).is_equal(GameTypes.PlayerSide.LEFT)

	# Both players still seated: the dwell elapses into a fresh serve at 0-0.
	for i in int(GameConfig.GAME_OVER_DELAY / DT) + 2:
		s.tick(DT)
	assert_int(s.state).is_equal(GameTypes.GameState.SERVING)
	assert_int(s.left_score).is_equal(0)
	assert_int(s.right_score).is_equal(0)


# ---- Pure bounce math ----

func test_centre_hit_on_a_still_paddle_bounces_horizontally() -> void:
	var v: Vector2 = GameSession._bounce_off_paddle(Vector2(8.0, 0.0), 0.0, 0.0, 0.0, false)
	assert_float(v.y).is_equal_approx(0.0, 1e-4)
	assert_float(v.length()).is_equal_approx(8.0 + GameConfig.BALL_SPEED_STEP, 1e-3)
	assert_float(v.x).is_less(0.0)


func test_edge_of_face_hit_deflects_at_max_bounce_angle() -> void:
	var v: Vector2 = GameSession._bounce_off_paddle(Vector2(8.0, 0.0),
			GameConfig.PADDLE_HALF_HEIGHT, 0.0, 0.0, false)
	assert_float(rad_to_deg(atan2(v.y, -v.x))).is_equal_approx(GameConfig.MAX_BOUNCE_ANGLE_DEG, 0.01)


func test_full_speed_paddle_spin_hits_the_spin_cap() -> void:
	var v: Vector2 = GameSession._bounce_off_paddle(Vector2(8.0, 0.0), 0.0, 0.0,
			GameConfig.PADDLE_SPEED, false)
	assert_float(rad_to_deg(atan2(v.y, -v.x))).is_equal_approx(GameConfig.MAX_SPIN_ANGLE_DEG, 0.01)
	# Tuning sanity: the cap must actually be reachable.
	assert_float(GameConfig.PADDLE_SPEED * GameConfig.PADDLE_SPIN_DEG_PER_UNIT) \
			.is_greater(GameConfig.MAX_SPIN_ANGLE_DEG)


func test_offset_plus_spin_clamps_at_the_total_angle_cap() -> void:
	var v: Vector2 = GameSession._bounce_off_paddle(Vector2(8.0, 0.0),
			GameConfig.PADDLE_HALF_HEIGHT, 0.0, GameConfig.PADDLE_SPEED, false)
	assert_float(rad_to_deg(atan2(v.y, -v.x))).is_equal_approx(GameConfig.MAX_TOTAL_BOUNCE_ANGLE_DEG, 0.01)


func test_bounce_speed_is_uncapped_so_rallies_never_plateau() -> void:
	# Well past the old hard cap: the ball must still gain exactly one step — there is no
	# ceiling, so a sustained rally keeps accelerating.
	var v: Vector2 = GameSession._bounce_off_paddle(Vector2(40.0, 0.0), 0.0, 0.0, 0.0, false)
	assert_float(v.length()).is_equal_approx(40.0 + GameConfig.BALL_SPEED_STEP, 1e-3)


func test_edge_deflect_pushes_off_the_tip_keeping_the_heading() -> void:
	var top: Vector2 = GameSession._edge_deflect(Vector2(8.0, 0.0), 0.5)
	assert_bool(top.x > 0.0 and top.y > 0.0).is_true()
	var bottom: Vector2 = GameSession._edge_deflect(Vector2(8.0, 0.0), -0.5)
	assert_bool(bottom.x > 0.0 and bottom.y < 0.0).is_true()

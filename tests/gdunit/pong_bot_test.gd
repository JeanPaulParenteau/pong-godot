# GdUnit4 suite — PongBot's pure aiming helpers. Ported from the legacy runner.
extends GdUnitTestSuite

const GameConfig = preload("res://src/shared/game_config.gd")
const PongBot = preload("res://src/shared/pong_bot.gd")


func test_bot_centres_when_the_ball_moves_away() -> void:
	assert_float(PongBot.desired_aim_y(Vector2(0, 2), Vector2(-5, 0), false)).is_equal_approx(0.0, 1e-4)


func test_bot_chases_ball_y_without_prediction() -> void:
	assert_float(PongBot.desired_aim_y(Vector2(0, 2), Vector2(5, 0), false)).is_equal_approx(2.0, 1e-4)


func test_straight_line_intercept() -> void:
	var y: float = PongBot.intercept_y(Vector2(0.0, 0.0), Vector2(7.0, 1.0))
	var t := (GameConfig.PADDLE_X - GameConfig.BALL_RADIUS) / 7.0
	assert_float(y).is_equal_approx(t * 1.0, 1e-4)


func test_fold_into_field_reflects_like_a_triangle_wave() -> void:
	assert_float(PongBot.fold_into_field(0.0)).is_equal_approx(0.0, 1e-4)
	assert_float(PongBot.fold_into_field(GameConfig.BALL_MAX_Y + 1.0)) \
			.is_equal_approx(GameConfig.BALL_MAX_Y - 1.0, 1e-4)
	assert_float(PongBot.fold_into_field(GameConfig.BALL_MIN_Y - 1.0)) \
			.is_equal_approx(GameConfig.BALL_MIN_Y + 1.0, 1e-4)


func test_rate_limited_step_binds_and_clamps_to_paddle_range() -> void:
	assert_float(PongBot.rate_limited_step(0.0, 100.0, 0.5)).is_equal_approx(0.5, 1e-4)
	assert_float(PongBot.rate_limited_step(GameConfig.PADDLE_MAX_Y, 100.0, 5.0)) \
			.is_equal_approx(GameConfig.PADDLE_MAX_Y, 1e-4)


func test_edge_safe_aim_keeps_the_worst_sample_on_the_front_face() -> void:
	var safe: float = PongBot.edge_safe_offset(0.8)
	assert_float(safe).is_equal_approx(GameConfig.PADDLE_HALF_HEIGHT - GameConfig.BALL_RADIUS, 1e-4)
	assert_float(PongBot.edge_safe_offset(0.12)).is_equal_approx(0.12, 1e-4)  # tight tier unchanged
	assert_float(PongBot.edge_safe_aim(2.0, 3.5, 0.8)).is_equal_approx(2.0 + safe, 1e-4)
	assert_float(PongBot.edge_safe_aim(2.0, 2.1, 0.8)).is_equal_approx(2.1, 1e-4)  # inside the band: no-op

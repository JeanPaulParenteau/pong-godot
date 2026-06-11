# GdUnit4 suite — PaddlePredictor: client-side prediction of the local paddle.
# Ported from the legacy runner.
extends GdUnitTestSuite

const GameConfig = preload("res://src/shared/game_config.gd")
const PaddlePredictor = preload("res://src/client/paddle_predictor.gd")

const DT := 1.0 / 30.0


func test_first_frame_trusts_the_server() -> void:
	assert_float(PaddlePredictor.new().update(3.0, 1.5, DT)).is_equal_approx(1.5, 1e-4)


func test_then_predicts_capped_motion_toward_the_target() -> void:
	var p := PaddlePredictor.new()
	p.update(3.0, 1.5, DT)
	assert_float(p.update(3.0, 1.5, DT)).is_equal_approx(1.5 + GameConfig.PADDLE_SPEED * DT, 1e-4)


func test_reset_re_seeds_from_the_authoritative_position() -> void:
	var p := PaddlePredictor.new()
	p.update(3.0, 1.5, DT)
	p.reset()
	assert_float(p.update(3.0, 0.0, DT)).is_equal_approx(0.0, 1e-4)

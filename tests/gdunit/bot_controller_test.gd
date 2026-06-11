# GdUnit4 suite — BotController: the CPU's stateful driver (cadence, aim error,
# rate limit). Seeded RNG for determinism. Ported from the legacy runner.
extends GdUnitTestSuite

const BotController = preload("res://src/shared/bot_controller.gd")
const BotProfile = preload("res://src/shared/bot_profile.gd")

const DT := 1.0 / 30.0


func _seeded_bot(seed_value: int) -> BotController:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return BotController.new(BotProfile.medium(), rng)


func test_first_step_is_rate_limited() -> void:
	var bot := _seeded_bot(42)
	var y := bot.step(Vector2(0, 3.0), Vector2(5, 0), DT)
	assert_float(absf(y)).is_less_equal(BotProfile.medium().max_speed * DT + 1e-5)


func test_bot_settles_within_aim_error_of_the_target() -> void:
	var bot := _seeded_bot(42)
	var y := 0.0
	for i in 120:
		y = bot.step(Vector2(0, 3.0), Vector2(5, 0), DT)
	assert_float(absf(y - 3.0)).is_less_equal(BotProfile.medium().aim_error + 1e-3)


func test_seeded_bot_is_deterministic() -> void:
	var y1 := _seeded_bot(42).step(Vector2(0, 3.0), Vector2(5, 0), DT)
	var y2 := _seeded_bot(42).step(Vector2(0, 3.0), Vector2(5, 0), DT)
	assert_float(y1).is_equal_approx(y2, 1e-6)

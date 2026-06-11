# GdUnit4 suite — Palette is pure constants, so this asserts the design RULES the
# header comment promises (cool vs warm sides, dark text on light tints), not the
# exact channel values — those are free to be retuned without touching tests.
extends GdUnitTestSuite

const Palette = preload("res://src/client/palette.gd")


func test_gameplay_colors_are_fully_opaque() -> void:
	for color: Color in [Palette.HUMAN, Palette.CPU, Palette.BALL, Palette.LINE]:
		assert_float(color.a).is_equal(1.0)


func test_human_side_is_cool_and_cpu_side_is_warm() -> void:
	# The promise in the header: left/player one cool (blue-leaning), CPU warm (red-leaning).
	assert_bool(Palette.HUMAN.b > Palette.HUMAN.r).is_true()
	assert_bool(Palette.CPU.r > Palette.CPU.b).is_true()


func test_button_text_is_dark_on_light_tints() -> void:
	# Contrast rule: dark text sits on every tinted button.
	assert_float(Palette.BUTTON_TEXT.get_luminance()).is_less(0.2)
	for tint: Color in [Palette.ACCENT, Palette.EASY, Palette.MEDIUM, Palette.HARD, Palette.NEUTRAL]:
		assert_float(tint.get_luminance()).is_greater(0.3)


func test_difficulty_tints_are_distinct() -> void:
	assert_that(Palette.EASY).is_not_equal(Palette.MEDIUM)
	assert_that(Palette.MEDIUM).is_not_equal(Palette.HARD)
	assert_that(Palette.EASY).is_not_equal(Palette.HARD)

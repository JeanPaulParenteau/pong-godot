# GdUnit4 suite — ScoreStyle: the pure contrast/outline primitive that guarantees
# HUD text legibility. Contrast + offset LOGIC is tested here; the on-screen
# stamping in game_renderer._draw_score is visual and is covered for crash-freedom
# only by menu_layout_test.gd (headless viewport is 64×64 / unreliable).
extends GdUnitTestSuite

const ScoreStyle = preload("res://src/client/score_style.gd")
const Palette = preload("res://src/client/palette.gd")

const DARK_CLEAR := Color(0.05, 0.055, 0.07)  # the new default_clear_color


func test_offsets_are_symmetric_around_origin() -> void:
	var o := ScoreStyle.offsets(2.0)
	var sum := Vector2.ZERO
	for v in o:
		sum += v
	assert_vector(sum).is_equal_approx(Vector2.ZERO, Vector2(1e-4, 1e-4))
	assert_int(o.size()).is_greater_equal(4)


func test_offsets_scale_with_px() -> void:
	var max_abs := 0.0
	for v in ScoreStyle.offsets(2.0):
		max_abs = maxf(max_abs, maxf(absf(v.x), absf(v.y)))
	assert_float(max_abs).is_equal_approx(2.0, 1e-4)


func test_wcag_contrast_is_symmetric_and_anchors_at_21() -> void:
	assert_float(ScoreStyle.wcag_contrast(Color.WHITE, Color.BLACK)).is_equal_approx(21.0, 0.1)
	assert_float(ScoreStyle.wcag_contrast(Palette.CPU, DARK_CLEAR)) \
			.is_equal_approx(ScoreStyle.wcag_contrast(DARK_CLEAR, Palette.CPU), 1e-4)


func test_dark_clear_color_lifts_cpu_score_over_aa_floor() -> void:
	# The whole rationale for the item: orange score clears AA on the dark slate,
	# but failed on the old default grey.
	assert_bool(ScoreStyle.meets_floor(Palette.CPU, DARK_CLEAR)).is_true()
	assert_bool(ScoreStyle.meets_floor(Palette.CPU, Color(0.3, 0.3, 0.3))).is_false()


func test_outline_is_dark_and_gives_local_contrast_under_any_tint() -> void:
	for tint: Color in [Palette.HUMAN, Palette.CPU]:
		assert_bool(ScoreStyle.meets_floor(tint, ScoreStyle.OUTLINE)).is_true()

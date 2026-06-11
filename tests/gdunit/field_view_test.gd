# GdUnit4 suite — pure-logic coverage for the world↔screen mapping. FieldView is
# all static math (no nodes), so we drive it by setting FieldView.screen_size /
# flip_x directly. At the default 1280×720 the 16:9 field fills a 16:9 screen, so
# pixels_per_unit is exactly 73.6 (1280*0.92/16 == 720*0.92/9) — convenient round
# numbers for the assertions below.
extends GdUnitTestSuite

const FieldView = preload("res://src/client/field_view.gd")
const GameConfig = preload("res://src/shared/game_config.gd")

const PPU := 73.6  # pixels_per_unit at 1280×720 (see header)


func before_test() -> void:
	# FieldView holds static state across tests — reset to a known frame.
	FieldView.screen_size = Vector2(1280, 720)
	FieldView.flip_x = false


func test_pixels_per_unit_fits_field_to_screen() -> void:
	assert_float(FieldView.pixels_per_unit()).is_equal_approx(PPU, 0.0001)


func test_pixels_per_unit_uses_the_limiting_axis() -> void:
	# A very wide screen is limited by height; ppu follows the tighter fit.
	FieldView.screen_size = Vector2(4000, 720)
	var fit_h := 720.0 * 0.92 / (2.0 * GameConfig.FIELD_HALF_HEIGHT)
	assert_float(FieldView.pixels_per_unit()).is_equal_approx(fit_h, 0.0001)


func test_origin_maps_to_screen_centre() -> void:
	assert_vector(FieldView.world_to_screen(Vector2.ZERO)).is_equal_approx(Vector2(640, 360), Vector2(0.001, 0.001))


func test_positive_world_y_maps_up_the_screen() -> void:
	# World Y is up-positive, screen Y is down-positive → +1 world Y is ABOVE centre.
	assert_vector(FieldView.world_to_screen(Vector2(0, 1))).is_equal_approx(Vector2(640, 360 - PPU), Vector2(0.001, 0.001))


func test_positive_world_x_maps_right_when_not_flipped() -> void:
	assert_vector(FieldView.world_to_screen(Vector2(1, 0))).is_equal_approx(Vector2(640 + PPU, 360), Vector2(0.001, 0.001))


func test_flip_x_mirrors_world_x_only() -> void:
	FieldView.flip_x = true
	var p := FieldView.world_to_screen(Vector2(1, 1))
	# X mirrored to the left, Y unaffected by the flip.
	assert_vector(p).is_equal_approx(Vector2(640 - PPU, 360 - PPU), Vector2(0.001, 0.001))


func test_pointer_centre_maps_to_world_zero() -> void:
	assert_float(FieldView.pointer_y_to_world(360)).is_equal_approx(0.0, 0.0001)


func test_world_to_screen_and_pointer_y_round_trip() -> void:
	for world_y in [-3.0, -0.5, 0.0, 1.25, 4.0]:
		var screen := FieldView.world_to_screen(Vector2(0, world_y))
		assert_float(FieldView.pointer_y_to_world(screen.y)).is_equal_approx(world_y, 0.0001)


func test_paddle_target_clamps_above_the_top_bound() -> void:
	# Pointer at the very top of the screen maps to a world Y past the paddle's
	# range; the result is clamped to PADDLE_MAX_Y.
	assert_float(FieldView.pointer_to_paddle_target_y(0)).is_equal_approx(GameConfig.PADDLE_MAX_Y, 0.0001)


func test_paddle_target_clamps_below_the_bottom_bound() -> void:
	assert_float(FieldView.pointer_to_paddle_target_y(720)).is_equal_approx(GameConfig.PADDLE_MIN_Y, 0.0001)


func test_paddle_target_passes_through_inside_the_range() -> void:
	# A pointer that maps to a legal world Y is returned unclamped.
	var pointer_y := 360.0 - PPU  # world Y == 1.0, inside ±3.6
	assert_float(FieldView.pointer_to_paddle_target_y(pointer_y)).is_equal_approx(1.0, 0.0001)


func test_world_rect_centres_a_box_in_screen_space() -> void:
	var r := FieldView.world_rect(Vector2.ZERO, 2.0, 2.0)
	assert_vector(r.position).is_equal_approx(Vector2(640 - PPU, 360 - PPU), Vector2(0.001, 0.001))
	assert_vector(r.size).is_equal_approx(Vector2(2.0 * PPU, 2.0 * PPU), Vector2(0.001, 0.001))

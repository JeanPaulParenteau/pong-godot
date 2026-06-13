# GdUnit4 suite — SafeArea: pure inset math for keeping interactive controls and
# HUD text clear of Android display cutouts. All decisions are functions of
# (safe_rect, window_size); the one DisplayServer/OS call lives behind
# current_safe_rect() and is exercised via the injectable _safe_rect_override
# (the Settings.file_path / _request_factory injection pattern). Mirrors FieldView.
extends GdUnitTestSuite

const SafeArea = preload("res://src/client/safe_area.gd")


func after_test() -> void:
	SafeArea._safe_rect_override = null  # static state — reset like field_view_test


func test_no_inset_when_safe_rect_is_empty() -> void:
	var r := SafeArea.inset_rect(Rect2(), Vector2(1280, 720))
	assert_vector(r.position).is_equal(Vector2.ZERO)
	assert_vector(r.size).is_equal(Vector2(1280, 720))


func test_inset_rect_clamps_to_safe_region() -> void:
	var r := SafeArea.inset_rect(Rect2(40, 30, 1200, 690), Vector2(1280, 720))
	assert_vector(r.position).is_equal(Vector2(40, 30))
	assert_vector(r.size).is_equal(Vector2(1200, 690))


func test_corner_offsets_match_legacy_when_no_inset() -> void:
	var o := SafeArea.corner_top_right_offsets(Rect2(), Vector2(1280, 720), 156, 54, 16, 18)
	assert_float(o["left"]).is_equal_approx(-174.0, 1e-4)
	assert_float(o["right"]).is_equal_approx(-18.0, 1e-4)
	assert_float(o["top"]).is_equal_approx(16.0, 1e-4)
	assert_float(o["bottom"]).is_equal_approx(70.0, 1e-4)


func test_corner_offsets_shift_in_by_right_inset() -> void:
	# A 60px right cutout: the safe right edge sits at 1220.
	var o := SafeArea.corner_top_right_offsets(Rect2(0, 0, 1220, 720), Vector2(1280, 720), 156, 54, 16, 18)
	assert_float(o["right"]).is_equal_approx(-78.0, 1e-4)  # -18 - 60
	assert_float(o["left"]).is_equal_approx(-234.0, 1e-4)  # right - 156
	assert_float(o["right"] - o["left"]).is_equal_approx(156.0, 1e-4)  # width preserved


func test_corner_offsets_shift_down_by_top_inset() -> void:
	var o := SafeArea.corner_top_right_offsets(Rect2(0, 44, 1280, 676), Vector2(1280, 720), 156, 54, 16, 18)
	assert_float(o["top"]).is_equal_approx(60.0, 1e-4)     # 16 + 44
	assert_float(o["bottom"]).is_equal_approx(114.0, 1e-4)  # 60 + 54


func test_hud_baseline_unchanged_without_top_inset() -> void:
	assert_float(SafeArea.hud_top_baseline(Rect2(), Vector2(1280, 720), 64.0)).is_equal_approx(64.0, 0.001)


func test_hud_baseline_drops_below_top_inset() -> void:
	assert_float(SafeArea.hud_top_baseline(Rect2(0, 44, 1280, 676), Vector2(1280, 720), 64.0)) \
			.is_equal_approx(108.0, 0.001)  # 44 + 64


func test_current_safe_rect_uses_override() -> void:
	SafeArea._safe_rect_override = Rect2(0, 44, 1280, 676)
	var r := SafeArea.current_safe_rect()
	assert_vector(r.position).is_equal(Vector2(0, 44))
	assert_vector(r.size).is_equal(Vector2(1280, 676))

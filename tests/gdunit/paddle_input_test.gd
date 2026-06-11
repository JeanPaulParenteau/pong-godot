# GdUnit4 suite — PaddleInput's static target state and the no-input path.
# Pointer *simulation* is unreliable headless (GdUnit4 warns), so this asserts the
# pure parts: the NAN-until-input contract and the environment-dependent branch of
# try_get_pointer_y, not synthetic mouse events.
extends GdUnitTestSuite

const PaddleInput = preload("res://src/client/paddle_input.gd")


func before_test() -> void:
	PaddleInput.clear_local_target()


func test_no_target_until_input_arrives() -> void:
	assert_bool(PaddleInput.has_local_target()).is_false()


func test_setting_a_target_marks_it_present() -> void:
	PaddleInput.local_target_y = 1.5
	assert_bool(PaddleInput.has_local_target()).is_true()


func test_clear_removes_the_target() -> void:
	PaddleInput.local_target_y = 1.5
	PaddleInput.clear_local_target()
	assert_bool(PaddleInput.has_local_target()).is_false()


func test_pointer_read_matches_the_environment() -> void:
	# Headless CI: no FEATURE_MOUSE and no button held → no input (NAN).
	# With a real mouse the pointer drives the paddle whenever it's over the
	# window, so the read is the live mouse Y.
	var y := PaddleInput.try_get_pointer_y(get_viewport())
	if DisplayServer.has_feature(DisplayServer.FEATURE_MOUSE):
		assert_float(y).is_equal(get_viewport().get_mouse_position().y)
	else:
		assert_bool(is_nan(y)).is_true()

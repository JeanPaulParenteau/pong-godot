# GdUnit4 suite — InputThrottle: don't flood the server with unchanged paddle
# targets. Ported from the legacy runner.
extends GdUnitTestSuite

const InputThrottle = preload("res://src/client/input_throttle.gd")


func test_first_sample_always_sends() -> void:
	assert_bool(InputThrottle.new().should_send(0.5)).is_true()


func test_repeats_and_tiny_moves_are_suppressed() -> void:
	var t := InputThrottle.new()
	t.should_send(0.5)
	assert_bool(t.should_send(0.5)).is_false()
	assert_bool(t.should_send(0.51)).is_false()


func test_a_meaningful_move_sends() -> void:
	var t := InputThrottle.new()
	t.should_send(0.5)
	assert_bool(t.should_send(0.6)).is_true()


func test_reset_re_arms() -> void:
	var t := InputThrottle.new()
	t.should_send(0.6)
	t.reset()
	assert_bool(t.should_send(0.6)).is_true()

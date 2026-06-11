# GdUnit4 suite — DebugCapture's decision logic: interval clamping and the
# frame-counting gate. The actual viewport→PNG save needs a real renderer (absent
# headless), so tests stay below the capture threshold — counting is asserted
# without ever triggering _save.
extends GdUnitTestSuite

const DebugCapture = preload("res://src/client/debug_capture.gd")

var _cap: DebugCapture


func before_test() -> void:
	_cap = auto_free(DebugCapture.new())
	add_child(_cap)


func test_negative_interval_clamps_to_manual_only() -> void:
	_cap.setup(-5)
	assert_int(_cap._interval).is_equal(0)


func test_zero_interval_means_no_continuous_capture() -> void:
	_cap.setup(0)
	for i in 10:
		_cap._process(0.0)
	assert_int(_cap._frame).is_equal(0)  # early-out: not even counting


func test_frames_are_counted_toward_the_capture_threshold() -> void:
	_cap.setup(1000)  # far above what we step — _save never fires
	for i in 5:
		_cap._process(0.0)
	assert_int(_cap._frame).is_equal(5)

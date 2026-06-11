# GdUnit4 suite — ConnectionFlow + ReconnectPolicy: the client connect/reconnect
# state machine and its backoff. Ported from the legacy runner.
extends GdUnitTestSuite

const ConnectionFlow = preload("res://src/client/connection_flow.gd")
const ReconnectPolicy = preload("res://src/client/reconnect_policy.gd")


func test_initial_connect_failure_surfaces_the_reason_without_reconnecting() -> void:
	var f := ConnectionFlow.new()
	assert_int(f.state).is_equal(ConnectionFlow.State.IDLE)
	f.begin_connect("1.2.3.4", "7777")
	assert_int(f.state).is_equal(ConnectionFlow.State.CONNECTING)
	assert_bool(f.on_disconnected("nope")).is_false()  # no reconnect before ever connecting
	assert_int(f.state).is_equal(ConnectionFlow.State.IDLE)
	assert_str(f.status).is_equal("nope")


func test_unexpected_drop_after_connecting_reconnects() -> void:
	var f := ConnectionFlow.new()
	f.begin_connect("1.2.3.4", "7777")
	f.on_connected()
	assert_int(f.state).is_equal(ConnectionFlow.State.CONNECTED)
	assert_bool(f.on_disconnected()).is_true()
	assert_int(f.state).is_equal(ConnectionFlow.State.RECONNECTING)
	assert_bool(f.on_disconnected()).is_false()  # a failed attempt inside the loop doesn't re-trigger


func test_backoff_is_exponential_then_fails() -> void:
	var f := ConnectionFlow.new()
	f.begin_connect("1.2.3.4", "7777")
	f.on_connected()
	f.on_disconnected()
	var delays: Array[float] = []
	for i in ReconnectPolicy.MAX_ATTEMPTS:
		delays.append(f.next_reconnect_delay())
	assert_array(delays).is_equal([1.0, 2.0, 4.0, 8.0])
	assert_float(f.next_reconnect_delay()).is_less(0.0)  # exhausted
	assert_int(f.state).is_equal(ConnectionFlow.State.FAILED)


func test_reset_and_a_fresh_connect_re_arm_the_backoff() -> void:
	var f := ConnectionFlow.new()
	f.begin_connect("1.2.3.4", "7777")
	f.on_connected()
	f.on_disconnected()
	for i in ReconnectPolicy.MAX_ATTEMPTS + 1:
		f.next_reconnect_delay()
	f.reset()
	assert_int(f.state).is_equal(ConnectionFlow.State.IDLE)
	f.on_connected()
	f.on_disconnected()
	assert_float(f.next_reconnect_delay()).is_equal_approx(1.0, 1e-6)

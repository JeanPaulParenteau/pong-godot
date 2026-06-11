# GdUnit4 suite — DiscoveryProtocol: the LAN browser wire format (Unity
# wire-compatible). Ported from the legacy runner.
extends GdUnitTestSuite

const DiscoveryProtocol = preload("res://src/shared/discovery_protocol.gd")


func test_request_round_trips() -> void:
	assert_bool(DiscoveryProtocol.is_request(DiscoveryProtocol.request())).is_true()


func test_a_response_is_not_a_request() -> void:
	assert_bool(DiscoveryProtocol.is_request("PONGv1|SERVER|7777|x".to_ascii_buffer())).is_false()


func test_response_round_trips_with_sanitized_name() -> void:
	var parsed := DiscoveryProtocol.try_parse_response(DiscoveryProtocol.response(7777, "My|Server"))
	assert_int(parsed["port"]).is_equal(7777)
	assert_str(parsed["name"]).is_equal("My/Server")  # separator made safe


func test_junk_is_rejected() -> void:
	assert_bool(DiscoveryProtocol.try_parse_response("junk".to_ascii_buffer()).is_empty()).is_true()

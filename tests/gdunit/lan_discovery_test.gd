# GdUnit4 suite — LanDiscovery's responder and probe halves over real loopback
# sockets. Each half is exercised with direct unicast packets (responder: send it a
# request, read its reply; probe: send a response to its bound port) instead of a
# 255.255.255.255 broadcast, which CI runners don't reliably deliver locally. The
# wire format itself is covered by the DiscoveryProtocol tests.
extends GdUnitTestSuite

const LanDiscovery = preload("res://src/client/lan_discovery.gd")
const DiscoveryProtocol = preload("res://src/shared/discovery_protocol.gd")

var _node: LanDiscovery
var _peer: PacketPeerUDP  # the test's own socket, playing the other side


func before_test() -> void:
	_node = auto_free(LanDiscovery.new())
	add_child(_node)
	_peer = PacketPeerUDP.new()


func after_test() -> void:
	_node.stop()
	_peer.close()


## Poll the node's _process until predicate() holds or ~1 s passes.
func _poll_until(predicate: Callable) -> bool:
	for i in 100:
		_node._process(0.0)
		if predicate.call():
			return true
		OS.delay_msec(10)
	return false


func test_responder_replies_to_a_discovery_request() -> void:
	_node.start_responder(7777, "Test Server")

	assert_int(_peer.bind(0)).is_equal(OK)  # so the reply can reach us
	_peer.set_dest_address("127.0.0.1", DiscoveryProtocol.DISCOVERY_PORT)
	_peer.put_packet(DiscoveryProtocol.request())

	assert_bool(_poll_until(func() -> bool: return _peer.get_available_packet_count() > 0)) \
			.override_failure_message("responder never replied").is_true()
	var parsed := DiscoveryProtocol.try_parse_response(_peer.get_packet())
	assert_int(parsed["port"]).is_equal(7777)
	assert_str(parsed["name"]).is_equal("Test Server")


func test_responder_ignores_non_request_noise() -> void:
	_node.start_responder(7777, "Test Server")

	assert_int(_peer.bind(0)).is_equal(OK)
	_peer.set_dest_address("127.0.0.1", DiscoveryProtocol.DISCOVERY_PORT)
	_peer.put_packet("not a pong packet".to_ascii_buffer())

	assert_bool(_poll_until(func() -> bool: return _peer.get_available_packet_count() > 0)).is_false()


func test_probe_collects_and_dedupes_server_replies() -> void:
	_node.refresh(10.0)  # long deadline — the test drives _process itself
	assert_bool(_node.searching()).is_true()

	# Reply to the probe's ephemeral port, twice from the same "server" — the
	# addr:port key dedupes into one entry.
	_peer.set_dest_address("127.0.0.1", _node._socket.get_local_port())
	_peer.put_packet(DiscoveryProtocol.response(7778, "Cloud"))
	_peer.put_packet(DiscoveryProtocol.response(7778, "Cloud"))

	assert_bool(_poll_until(func() -> bool: return _node.servers().size() > 0)) \
			.override_failure_message("probe never saw the reply").is_true()
	assert_int(_node.servers().size()).is_equal(1)
	var server: Dictionary = _node.servers()[0]
	assert_str(server["address"]).is_equal("127.0.0.1")
	assert_int(server["port"]).is_equal(7778)
	assert_str(server["name"]).is_equal("Cloud")


func test_probe_stops_searching_after_the_listen_window() -> void:
	_node.refresh(0.05)
	OS.delay_msec(80)  # past the deadline
	_node._process(0.0)
	assert_bool(_node.searching()).is_false()


func test_stop_is_idempotent_and_ends_the_search() -> void:
	_node.refresh(10.0)
	_node.stop()
	_node.stop()
	assert_bool(_node.searching()).is_false()
	assert_array(_node.servers()).is_empty()

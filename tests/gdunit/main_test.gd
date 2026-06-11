# GdUnit4 suite — Main, the composition root. _ready resolves the LaunchConfig
# and delegates to _build(mode, config); tests call _build directly with a crafted
# config so booting never parses the test runner's own command line (which would
# resolve to SERVER and bind real ports). The Main node stays OUT of the tree —
# children are asserted by name; their _ready wiring is covered by their own
# suites. Nodes are freed manually since out-of-tree nodes trip the orphan monitor.
extends GdUnitTestSuite

const Main = preload("res://src/main.gd")
const MatchServer = preload("res://src/server/match_server.gd")
const LaunchConfig = preload("res://src/shared/launch_config.gd")


## Minimal stand-in at the NetBridge seam (configure only registers itself on it).
class StubNet extends Node:
	var server = null


func test_client_mode_builds_the_full_client_stack() -> void:
	var main: Node = Main.new()
	main._build(LaunchConfig.LaunchMode.CLIENT, LaunchConfig.new())
	assert_bool(main.has_node("Net")).is_true()
	assert_bool(main.has_node("OnlineMatch")).is_true()
	assert_bool(main.has_node("GameRenderer")).is_true()
	assert_bool(main.has_node("ConnectScreen")).is_true()
	main.free()


func test_client_mode_routes_client_rpcs_to_the_online_match() -> void:
	var main: Node = Main.new()
	main._build(LaunchConfig.LaunchMode.CLIENT, LaunchConfig.new())
	assert_object(main.get_node("Net").client).is_same(main.get_node("OnlineMatch"))
	main.free()


func test_close_request_starts_a_graceful_drain_instead_of_quitting() -> void:
	var main: Node = Main.new()
	var net := StubNet.new()
	var server := MatchServer.new()
	server.configure(net)
	main._server = server

	main._notification(NOTIFICATION_WM_CLOSE_REQUEST)

	assert_bool(server.is_draining()).is_true()
	server.free()
	net.free()
	main.free()

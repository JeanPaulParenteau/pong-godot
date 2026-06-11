# GdUnit4 suite — MatchServer through its transport seam. A FakeNet adapter
# implements NetBridge's server-side send surface (send_assign_side /
# send_snapshot / refuse / kick / connected_peers), so seating, publish targeting,
# spectator routing, ranked recording, and the graceful drain are all exercised
# with no ENet peer: tests call the signal handlers and tick steps directly.
extends GdUnitTestSuite

const MatchServer = preload("res://src/server/match_server.gd")
const GameConfig = preload("res://src/shared/game_config.gd")
const GameTypes = preload("res://src/shared/game_types.gd")
const PlayerHandshake = preload("res://src/shared/player_handshake.gd")
const PlayerRecord = preload("res://src/server/player_record.gd")


## The second adapter at the NetBridge seam: records every outgoing send.
class FakeNet extends Node:
	var server = null  # NetBridge contract: the server registers itself here
	var connected := PackedInt32Array()
	var assigned := {}   # peer_id -> side
	var snapshots := {}  # peer_id -> Array of wire arrays
	var refusals := {}   # peer_id -> reason
	var kicked: Array = []

	func connected_peers() -> PackedInt32Array:
		return connected

	func send_assign_side(peer_id: int, side: int) -> void:
		assigned[peer_id] = side

	func send_snapshot(peer_id: int, wire: Array) -> void:
		if not snapshots.has(peer_id):
			snapshots[peer_id] = []
		snapshots[peer_id].append(wire)

	func refuse(peer_id: int, reason: String) -> void:
		refusals[peer_id] = reason

	func kick(peer_id: int) -> void:
		kicked.append(peer_id)


## A store that is never warm — the cold-cache guard must skip the update.
class ColdStore:
	var saved: Array = []

	func warm(_id: String) -> void:
		pass

	func is_ready(_id: String) -> bool:
		return false

	func load_record(id: String):
		return PlayerRecord.new_player(id, "")

	func save_record(rec) -> void:
		saved.append(rec)


var _server: MatchServer
var _net: FakeNet


func before_test() -> void:
	_server = auto_free(MatchServer.new())
	add_child(_server)
	_server.set_process(false)  # tests drive ticks/sweeps explicitly
	_net = auto_free(FakeNet.new())
	_server.configure(_net)


func _connect_and_hello(peer_id: int, payload := "") -> void:
	_server._on_peer_connected(peer_id)
	_server.handle_hello(peer_id, payload)


func _seat_two() -> void:
	_connect_and_hello(1)
	_connect_and_hello(2)
	_net.connected = PackedInt32Array([1, 2])


func _session():  # the only match's GameSession
	return _server._matches.values()[0]["session"]


## Tick the only match through the serve countdown into PLAYING.
func _advance_past_serve() -> void:
	for i in int(GameConfig.SERVE_DELAY * GameConfig.TICK_RATE) + 1:
		_server._tick_all()


## Force the next tick to score past `side`'s goal line.
func _teleport_ball_past_goal(side: int) -> void:
	if side == GameTypes.PlayerSide.LEFT:
		_session().teleport_ball(Vector2(-7.8, 0), Vector2(-6, 0))
	else:
		_session().teleport_ball(Vector2(7.8, 0), Vector2(6, 0))


func test_first_two_hellos_seat_left_then_right_in_one_match() -> void:
	_seat_two()
	assert_int(_net.assigned[1]).is_equal(GameTypes.PlayerSide.LEFT)
	assert_int(_net.assigned[2]).is_equal(GameTypes.PlayerSide.RIGHT)
	assert_int(_server.match_count()).is_equal(1)


func test_hello_beyond_the_match_cap_is_refused_as_full() -> void:
	_server.configure(_net, 1)  # cap: one match
	_seat_two()
	_connect_and_hello(3)
	assert_str(_net.refusals[3]).is_equal(GameConfig.SERVER_FULL_REASON)


func test_snapshots_go_only_to_connected_participants() -> void:
	_seat_two()
	_net.connected = PackedInt32Array([1])  # 2's disconnect hasn't been processed yet
	_server._tick_all()
	assert_bool(_net.snapshots.has(1)).is_true()
	assert_bool(_net.snapshots.has(2)).is_false()


func test_input_moves_the_senders_own_paddle() -> void:
	_seat_two()
	_server.handle_input(1, 3.0)  # peer 1 = Left
	_server._tick_all()
	assert_float(_session().left_paddle_y).is_greater(0.0)
	assert_float(_session().right_paddle_y).is_equal(0.0)


func test_input_from_an_unseated_peer_is_ignored() -> void:
	_server.handle_input(99, 3.0)  # no crash, no match created
	assert_int(_server.match_count()).is_equal(0)


func test_spectator_is_routed_to_the_live_match_and_fed_snapshots() -> void:
	_seat_two()
	_connect_and_hello(5, GameConfig.SPECTATOR_TOKEN)
	_net.connected = PackedInt32Array([1, 2, 5])
	_server._reconcile_spectators()
	_server._tick_all()
	assert_bool(_net.snapshots.has(5)).is_true()


func test_peer_that_never_says_hello_is_kicked_after_the_timeout() -> void:
	_server._on_peer_connected(7)
	_server._sweep_pending(MatchServer.HELLO_TIMEOUT_SEC + 1.0)
	assert_array(_net.kicked).contains([7])


func test_both_players_leaving_closes_the_match() -> void:
	_seat_two()
	_server._on_peer_disconnected(1)
	_server._on_peer_disconnected(2)
	assert_int(_server.match_count()).is_equal(0)


func test_a_win_between_identified_players_is_rated_once() -> void:
	_server._on_peer_connected(1)
	_server.handle_hello(1, PlayerHandshake.new("id-winner", "Winner").encode())
	_server._on_peer_connected(2)
	_server.handle_hello(2, PlayerHandshake.new("id-loser", "Loser").encode())
	_net.connected = PackedInt32Array([1, 2])
	_advance_past_serve()

	_session().left_score = GameConfig.WIN_SCORE - 1
	_teleport_ball_past_goal(GameTypes.PlayerSide.RIGHT)  # Left scores the winning point
	_server._tick_all()

	var winner = _server._store.load_record("id-winner")
	var loser = _server._store.load_record("id-loser")
	assert_int(winner.wins).is_equal(1)
	assert_int(loser.losses).is_equal(1)
	assert_int(winner.rating).is_greater(loser.rating)

	_server._tick_all()  # game-over dwell — must not double-record
	assert_int(_server._store.load_record("id-winner").games_played).is_equal(1)


func test_anonymous_games_are_not_rated() -> void:
	_seat_two()  # both anonymous (empty payloads)
	_advance_past_serve()
	_session().left_score = GameConfig.WIN_SCORE - 1
	_teleport_ball_past_goal(GameTypes.PlayerSide.RIGHT)
	_server._tick_all()
	assert_int(_server._store.load_record("").games_played).is_equal(0)


func test_a_cold_store_skips_the_ranked_update_instead_of_clobbering() -> void:
	var cold := ColdStore.new()
	_server.configure(_net, 0, cold)
	_server._on_peer_connected(1)
	_server.handle_hello(1, PlayerHandshake.new("id-a", "A").encode())
	_server._on_peer_connected(2)
	_server.handle_hello(2, PlayerHandshake.new("id-b", "B").encode())
	_net.connected = PackedInt32Array([1, 2])
	_advance_past_serve()
	_session().left_score = GameConfig.WIN_SCORE - 1
	_teleport_ball_past_goal(GameTypes.PlayerSide.RIGHT)
	_server._tick_all()
	assert_array(cold.saved).is_empty()


func test_drain_refuses_new_hellos_with_the_restarting_reason() -> void:
	_server.begin_drain()
	_connect_and_hello(4)
	assert_str(_net.refusals[4]).is_equal(GameConfig.SERVER_DRAINING_REASON)


func test_drain_drops_spectators_and_waiting_players() -> void:
	_connect_and_hello(1)  # lone player, waiting for an opponent
	_connect_and_hello(5, GameConfig.SPECTATOR_TOKEN)
	_server.begin_drain()
	assert_str(_net.refusals[1]).is_equal(GameConfig.SERVER_DRAINING_REASON)
	assert_str(_net.refusals[5]).is_equal(GameConfig.SERVER_DRAINING_REASON)


func test_drain_finishes_once_nothing_remains() -> void:
	_connect_and_hello(1)
	var finished := [false]
	_server.drain_finished.connect(func() -> void: finished[0] = true)

	_server.begin_drain()
	_server._drain_step()
	assert_bool(finished[0]).is_false()  # peer 1 still seated (refused, not yet gone)

	_server._on_peer_disconnected(1)
	_server._on_peer_disconnected(5)  # the refused spectator from begin_drain? none here — harmless
	_server._drain_step()
	assert_bool(finished[0]).is_true()

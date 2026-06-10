## Headless test client: connect, log replicated state, optionally drop, and (with
## -smoke) require that a real match was observed — side assigned, Playing reached,
## ball moving — exiting non-zero otherwise. The end-to-end gate that catches
## wire/replication regressions without a GUI or a phone.
extends Node

const GameConfig := preload("res://src/shared/game_config.gd")
const GameTypes := preload("res://src/shared/game_types.gd")
const PlayerHandshake := preload("res://src/shared/player_handshake.gd")

var _config  # LaunchConfig
var _net: Node     # NetBridge
var _online: Node  # OnlineMatch

var _elapsed := 0.0
var _next_log := 0.5
var _dropped := false
# Smoke observations: did we get a side, reach Playing, and see the ball move?
var _saw_side := false
var _saw_playing := false
var _ball_moved := false
var _has_last_ball := false
var _last_playing_ball := Vector2.ZERO


func start(net: Node, online: Node, config) -> void:
	_net = net
	_online = online
	_config = config

	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(func() -> void: print("[AutoClient] Connection failed."))
	multiplayer.server_disconnected.connect(func() -> void: print("[AutoClient] Disconnected."))

	print("[AutoClient] Connecting to %s:%d (drop=%.1fs, quit=%.1fs)..." % [
		config.client_address, config.port, config.drop_after, config.quit_after])
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(config.client_address, config.port)
	print("[AutoClient] create_client returned %s." % error_string(err))
	if err == OK:
		multiplayer.multiplayer_peer = peer


func _on_connected() -> void:
	print("[AutoClient] Connected (peer=%d)." % multiplayer.get_unique_id())
	# Ranked smoke: with -playerid the autoclient connects as an identified Player so
	# a completed game writes rating/W-L to the store. Default stays anonymous.
	var payload := ""
	if not _config.player_id.is_empty():
		payload = PlayerHandshake.new(_config.player_id, _config.player_name).encode()
	_net.rpc_id(1, "server_hello", payload)


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= _next_log:
		_next_log += 0.5
		_observe_and_log()

	if _config.drop_after > 0.0 and not _dropped and _elapsed >= _config.drop_after:
		_dropped = true
		print("[AutoClient] Intentionally disconnecting to test disconnect handling.")
		var peer := multiplayer.multiplayer_peer
		if peer != null:
			peer.close()
		multiplayer.multiplayer_peer = null

	if _elapsed >= _config.quit_after:
		_finish()


func _observe_and_log() -> void:
	if _online.local_side() != GameTypes.NO_SIDE:
		_saw_side = true

	if _online.has_match():
		var snap = _online.snapshot()
		if snap.state == GameTypes.GameState.PLAYING:
			_saw_playing = true
			if _has_last_ball and _last_playing_ball.distance_to(snap.ball_position) > 0.01:
				_ball_moved = true
			_last_playing_ball = snap.ball_position
			_has_last_ball = true
		print("[AutoClient] t=%.1fs match=%d side=%d state=%d score=%d-%d ball=%s L=%.2f R=%.2f" % [
			_elapsed, snap.match_id, _online.local_side(), snap.state,
			snap.left_score, snap.right_score, snap.ball_position,
			snap.left_paddle_y, snap.right_paddle_y])
	else:
		var peer := multiplayer.multiplayer_peer
		var connected := (peer != null
				and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED)
		print("[AutoClient] t=%.1fs connected=%s (no state yet)" % [_elapsed, connected])


func _finish() -> void:
	set_process(false)
	if _config.require_play:
		# Online smoke: a real match must have been observed.
		var ok := _saw_side and _saw_playing and _ball_moved
		print("[AutoClient] %s (side=%s playing=%s ballMoved=%s)" % [
			"SMOKE_OK" if ok else "SMOKE_FAIL", _saw_side, _saw_playing, _ball_moved])
		get_tree().quit(0 if ok else 2)
	else:
		print("[AutoClient] Done. Quitting.")
		get_tree().quit(0)

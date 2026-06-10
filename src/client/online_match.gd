## Client-side state for online play (and Pong TV): receives the server's
## snapshot stream, tracks the locally-controlled side, and publishes itself as
## the active match source so the renderer/audio draw it like any other match.
## Also owns the client → server input path (pointer → throttled RPC).
##
## Snapshots stop flowing when the server has nothing to show this peer (e.g. a
## spectator with no live match); after a short starvation timeout the view is
## cleared so the UI can fall back to its waiting screen.
extends Node

const GameConfig := preload("res://src/shared/game_config.gd")
const GameTypes := preload("res://src/shared/game_types.gd")
const MatchSnapshot := preload("res://src/shared/match_snapshot.gd")
const MatchSource := preload("res://src/shared/match_source.gd")
const FieldView := preload("res://src/client/field_view.gd")
const PaddleInput := preload("res://src/client/paddle_input.gd")
const InputThrottle := preload("res://src/client/input_throttle.gd")

const SNAPSHOT_STARVE_SEC := 2.0

var _net: Node  # NetBridge
var _latest = null  # MatchSnapshot
var _side: int = GameTypes.NO_SIDE
var _since_snapshot := 0.0
var _throttle := InputThrottle.new()

## The last refusal reason the server sent (server full / draining), surfaced on
## the connect screen after the disconnect that follows it. Read-and-clear.
var last_refusal := ""


func start(net: Node) -> void:
	_net = net
	net.client = self


# ---- Match-source contract (read by GameRenderer / AudioFx) ----

func snapshot():  # -> MatchSnapshot
	return _latest if _latest != null else MatchSnapshot.new()


func local_side() -> int:
	return _side


func is_local() -> bool:
	return false


func has_match() -> bool:
	return _latest != null


# ---- RPC handlers (routed by NetBridge) ----

func handle_snapshot(data: Array) -> void:
	var snap = MatchSnapshot.from_wire(data)
	if snap == null:
		return
	_latest = snap
	_since_snapshot = 0.0
	# Don't hijack an in-progress offline solo match if a stray/in-flight online
	# connection lands (e.g. a "Play Online" tap the player abandoned for vs CPU).
	if MatchSource.current == null or not MatchSource.current.is_local():
		MatchSource.set_source(self)


func handle_assign_side(side: int) -> void:
	_side = side


func handle_refused(reason: String) -> void:
	last_refusal = reason


## Read and clear the last refusal reason (the connect screen consumes it once).
func take_refusal() -> String:
	var r := last_refusal
	last_refusal = ""
	return r


## Connection torn down (by us or the server): drop all per-connection state.
func reset() -> void:
	_latest = null
	_side = GameTypes.NO_SIDE
	_since_snapshot = 0.0
	_throttle.reset()
	PaddleInput.clear_local_target()
	MatchSource.clear(self)


# ---- Frame loop: input send + starvation sweep ----

func _process(delta: float) -> void:
	if _latest != null:
		_since_snapshot += delta
		if _since_snapshot > SNAPSHOT_STARVE_SEC:
			# The server stopped showing us anything (spectator with no live match,
			# or a dead connection about to be reported). Clear the view.
			_latest = null
			_side = _side if _connected() else GameTypes.NO_SIDE
			MatchSource.clear(self)

	if not _connected():
		return
	if _latest == null or _side == GameTypes.NO_SIDE:
		return  # spectators (and players before the server assigns a side) have no paddle
	if (_latest.state != GameTypes.GameState.SERVING
			and _latest.state != GameTypes.GameState.PLAYING):
		return

	var pointer_y := PaddleInput.try_get_pointer_y(get_viewport())
	if is_nan(pointer_y):
		return

	var world_y := FieldView.pointer_to_paddle_target_y(pointer_y)
	PaddleInput.local_target_y = world_y  # feed client-side prediction

	if _throttle.should_send(world_y):
		_net.rpc_id(1, "server_submit_input", world_y)


func _connected() -> bool:
	var peer := multiplayer.multiplayer_peer
	return (peer != null
			and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED
			and not multiplayer.is_server())

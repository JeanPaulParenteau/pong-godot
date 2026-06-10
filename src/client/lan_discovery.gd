## LAN server discovery over UDP broadcast (separate from the game transport). The
## server runs a responder; a client broadcasts a probe and collects replies — a
## "server browser" for the local network. Wire format is DiscoveryProtocol
## (unit-tested); the sockets are polled on the main thread in _process (no
## threads), which at this packet rate is free.
extends Node

const DiscoveryProtocol := preload("res://src/shared/discovery_protocol.gd")

## {address: String, port: int, name: String} per discovered server.
var _found := {}  # "addr:port" -> Dictionary

var _socket: PacketPeerUDP = null
var _mode := MODE_OFF
var _deadline_msec := 0
var _game_port := 0
var _server_name := ""

enum { MODE_OFF, MODE_RESPONDER, MODE_PROBE }


# ---- Server side ----

func start_responder(game_port: int, name: String) -> void:
	stop()
	_socket = PacketPeerUDP.new()
	var err := _socket.bind(DiscoveryProtocol.DISCOVERY_PORT)
	if err != OK:
		push_warning("[LanDiscovery] Responder bind failed: %s" % error_string(err))
		_socket = null
		return
	_game_port = game_port
	_server_name = name
	_mode = MODE_RESPONDER
	print("[LanDiscovery] Responder listening on UDP %d." % DiscoveryProtocol.DISCOVERY_PORT)


# ---- Client side ----

## Broadcast a probe and listen for replies for listen_seconds.
func refresh(listen_seconds := 1.5) -> void:
	stop()
	_found.clear()
	_socket = PacketPeerUDP.new()
	_socket.set_broadcast_enabled(true)
	# Bind an ephemeral port so replies can reach us.
	if _socket.bind(0) != OK:
		push_warning("[LanDiscovery] Probe bind failed.")
		_socket = null
		return
	_socket.set_dest_address("255.255.255.255", DiscoveryProtocol.DISCOVERY_PORT)
	_socket.put_packet(DiscoveryProtocol.request())  # may be blocked on some adapters
	_mode = MODE_PROBE
	_deadline_msec = Time.get_ticks_msec() + int(listen_seconds * 1000.0)


func servers() -> Array:
	return _found.values()


func searching() -> bool:
	return _mode == MODE_PROBE


func stop() -> void:
	if _socket != null:
		_socket.close()
	_socket = null
	_mode = MODE_OFF


func _exit_tree() -> void:
	stop()


func _process(_delta: float) -> void:
	match _mode:
		MODE_RESPONDER:
			while _socket.get_available_packet_count() > 0:
				var data := _socket.get_packet()
				if DiscoveryProtocol.is_request(data):
					var reply := PacketPeerUDP.new()
					reply.set_dest_address(_socket.get_packet_ip(), _socket.get_packet_port())
					reply.put_packet(DiscoveryProtocol.response(_game_port, _server_name))
					reply.close()

		MODE_PROBE:
			while _socket.get_available_packet_count() > 0:
				var data := _socket.get_packet()
				var parsed := DiscoveryProtocol.try_parse_response(data)
				if not parsed.is_empty():
					var server := {
						"address": _socket.get_packet_ip(),
						"port": parsed["port"],
						"name": parsed["name"],
					}
					_found["%s:%d" % [server["address"], server["port"]]] = server
			if Time.get_ticks_msec() >= _deadline_msec:
				stop()

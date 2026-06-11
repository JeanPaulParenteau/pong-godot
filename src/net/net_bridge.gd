## The RPC surface shared by client and server. Godot's high-level multiplayer
## matches RPCs by node path, so this node lives at the same path
## (/root/Main/Net) in every process; main.gd adds it unconditionally. It holds
## no game logic — it routes RPCs to the server-side MatchServer or the
## client-side OnlineMatch, whichever exists in this process.
##
## Replication design (replacing Unity NGO's NetworkVariables + visibility):
## the server pushes each match's snapshot to exactly the peers that should see
## it (its two seated players + any spectators routed to it) as an
## unreliable-ordered RPC at the 30 Hz tick rate. Late joiners need no initial
## sync — the next tick's snapshot is a full state.
extends Node

var server = null  # MatchServer (set in server mode)
var client = null  # OnlineMatch (set in client mode)


# ---- client → server ----

## First message after connecting (Godot has no connection-approval payload, so
## approval happens here): "" = anonymous player, GameConfig.SPECTATOR_TOKEN =
## Pong TV viewer, PlayerHandshake.encode() = identified player.
@rpc("any_peer", "call_remote", "reliable")
func server_hello(payload: String) -> void:
	if server != null:
		server.handle_hello(multiplayer.get_remote_sender_id(), payload)


## The desired paddle Y (clamped on apply). Unreliable: the next sample supersedes.
@rpc("any_peer", "call_remote", "unreliable_ordered")
func server_submit_input(target_y: float) -> void:
	if server != null:
		server.handle_input(multiplayer.get_remote_sender_id(), target_y)


# ---- server-side send surface ----
# MatchServer talks to clients only through these, so the wire method names and
# transport quirks (flush timing, peer enumeration, force-disconnects) live here.
# Tests substitute a fake with the same five methods — the second adapter that
# makes this seam real.

## Peers currently connected (publish targets are filtered against this).
func connected_peers() -> PackedInt32Array:
	return multiplayer.get_peers()


func send_assign_side(peer_id: int, side: int) -> void:
	rpc_id(peer_id, "client_assign_side", side)


func send_snapshot(peer_id: int, wire: Array) -> void:
	rpc_id(peer_id, "client_snapshot", wire)


## Refuse a connection: send the reason, then disconnect — after a beat, so the
## reliable RPC flushes before the channel closes.
func refuse(peer_id: int, reason: String) -> void:
	rpc_id(peer_id, "client_refused", reason)
	get_tree().create_timer(0.25).timeout.connect(func() -> void:
		kick(peer_id))


## Force-disconnect a peer (hello timeout, post-refusal close).
func kick(peer_id: int) -> void:
	var mp_peer := multiplayer.multiplayer_peer
	if mp_peer != null and peer_id in multiplayer.get_peers():
		mp_peer.disconnect_peer(peer_id)


# ---- server → client ----

## Tell one specific client which paddle it controls (drives prediction).
@rpc("authority", "call_remote", "reliable")
func client_assign_side(side: int) -> void:
	if client != null:
		client.handle_assign_side(side)


## One match snapshot (MatchSnapshot.to_wire() array), ~30 Hz.
@rpc("authority", "call_remote", "unreliable_ordered")
func client_snapshot(data: Array) -> void:
	if client != null:
		client.handle_snapshot(data)


## The server refused this connection (full / draining); a disconnect follows.
@rpc("authority", "call_remote", "reliable")
func client_refused(reason: String) -> void:
	if client != null:
		client.handle_refused(reason)

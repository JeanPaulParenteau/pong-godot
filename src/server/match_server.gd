## The dedicated server: owns the ENet listen peer and a GameSession per match.
## Delegates who-goes-where to the pure MatchRoster and enacts its decisions —
## seating players, ticking every session at 30 Hz, and pushing each match's
## snapshot to exactly the peers that observe it (participants + routed
## spectators). The Godot replacement for the Unity MatchManager +
## NetworkGameState pair.
extends Node

const GameConfig := preload("res://src/shared/game_config.gd")
const GameTypes := preload("res://src/shared/game_types.gd")
const GameSession := preload("res://src/shared/game_session.gd")
const MatchSnapshot := preload("res://src/shared/match_snapshot.gd")
const MatchRoster := preload("res://src/shared/match_roster.gd")
const SpectatorRouter := preload("res://src/shared/spectator_router.gd")
const PlayerHandshake := preload("res://src/shared/player_handshake.gd")
const PlayerStore := preload("res://src/server/player_store.gd")
const RankedService := preload("res://src/server/ranked_service.gd")

# How long a connected peer may sit without sending its hello before being dropped.
const HELLO_TIMEOUT_SEC := 5.0

var _net: Node  # NetBridge (RPC surface)
var _roster: MatchRoster
var _store  # player store (duck-typed: in-memory or Supabase)
var _tick_dt := 1.0 / GameConfig.TICK_RATE
var _accum := 0.0

# match_id -> {session, participants: {peer_id: side}, tick: int, result_recorded: bool}
var _matches := {}

# Peers that connected but haven't sent a hello yet: peer_id -> seconds waited.
var _pending := {}

# Ranked: the Player behind each identified connection. Anonymous connections
# simply aren't here, so their games don't count.
var _players := {}  # peer_id -> PlayerHandshake

# Read-only "Pong TV" viewers: no seat, no paddle. _spectator_showing maps a
# spectator to the match it currently watches (so it stays through
# game-over/rematch and re-picks once that match stops being live).
var _spectators := {}         # peer_id -> true (set)
var _spectator_showing := {}  # peer_id -> match_id

# Graceful drain: once draining, refuse new connections, drop spectators and
# lone survivors, let two-player matches finish, then quit.
var _draining := false
var _drain_notified := {}  # peer_id -> true


func start(net: Node, port: int, max_matches := 0, store = null) -> bool:
	_net = net
	net.server = self
	_roster = MatchRoster.new(1, max_matches)  # 0 = unlimited
	_store = store if store != null else PlayerStore.new()

	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port)
	if err != OK:
		printerr("[MatchServer] ERROR: create_server(%d) failed: %s" % [port, error_string(err)])
		return false
	multiplayer.multiplayer_peer = peer
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	print("[MatchServer] Server listening on 0.0.0.0:%d (tick %d Hz)." % [port, GameConfig.TICK_RATE])
	return true


func match_count() -> int:
	return _matches.size()


func is_draining() -> bool:
	return _draining


# -------------------------------------------------------------------
# Connection lifecycle
# -------------------------------------------------------------------

func _on_peer_connected(peer_id: int) -> void:
	# No seat yet — wait for the hello (player / spectator / anonymous). A peer
	# that never says hello is swept by the timeout in _process.
	_pending[peer_id] = 0.0


func _on_peer_disconnected(peer_id: int) -> void:
	_pending.erase(peer_id)
	_players.erase(peer_id)       # ranked identity no longer needed
	_drain_notified.erase(peer_id)

	# Spectator left: drop it.
	if _spectators.erase(peer_id):
		_spectator_showing.erase(peer_id)
		return

	var match_id := _roster.match_for_client(peer_id)
	if match_id == -1:
		return

	if _matches.has(match_id):
		var m: Dictionary = _matches[match_id]
		if m["participants"].has(peer_id):
			var side: int = m["participants"][peer_id]
			m["participants"].erase(peer_id)
			m["session"].remove_player(side)

	var emptied := _roster.release(peer_id)
	print("[MatchServer] Client %d left match %d." % [peer_id, match_id])
	if emptied != -1 and _matches.has(emptied):
		_matches.erase(emptied)
		print("[MatchServer] Match %d empty -> closed (active matches: %d)." % [emptied, _matches.size()])


## First message from a connected peer: route it as a spectator, an identified
## player, or an anonymous player. This is the Godot equivalent of NGO's
## connection approval — refusals send a reason RPC, then disconnect.
func handle_hello(peer_id: int, payload: String) -> void:
	_pending.erase(peer_id)

	# Draining: the server is going away — turn everyone away with the "restarting" reason.
	if _draining:
		_refuse(peer_id, GameConfig.SERVER_DRAINING_REASON)
		return

	if payload == GameConfig.SPECTATOR_TOKEN:
		_spectators[peer_id] = true
		return  # no seat; _reconcile_spectators routes it to a live match

	var placement := _roster.reserve(peer_id)
	if not placement["accepted"]:
		print("[MatchServer] Rejected client %d: server full (match cap reached, active matches: %d)."
				% [peer_id, _matches.size()])
		_refuse(peer_id, GameConfig.SERVER_FULL_REASON)
		return

	# Remember the Player behind this connection for the ranked update at match end,
	# and warm their record into the store now so it's loaded by match end. An empty
	# or malformed payload doesn't decode → the client plays anonymously, unrated.
	var handshake = PlayerHandshake.try_decode(payload)
	if handshake != null:
		_players[peer_id] = handshake
		_store.warm(handshake.player_id)

	var m := _ensure_match(placement["match_id"])
	var side: int = m["session"].add_player()
	if side == GameTypes.NO_SIDE:
		# Shouldn't happen (roster capped the seats), but never strand a client.
		_roster.release(peer_id)
		_refuse(peer_id, GameConfig.SERVER_FULL_REASON)
		return

	m["participants"][peer_id] = side
	_net.rpc_id(peer_id, "client_assign_side", side)
	print("[MatchServer] Client %d -> match %d as %s paddle (active matches: %d)." % [
		peer_id, placement["match_id"],
		"Left" if side == GameTypes.PlayerSide.LEFT else "Right", _matches.size()])


func handle_input(peer_id: int, target_y: float) -> void:
	var match_id := _roster.match_for_client(peer_id)
	if match_id == -1 or not _matches.has(match_id):
		return
	var m: Dictionary = _matches[match_id]
	if m["participants"].has(peer_id):
		m["session"].set_input(m["participants"][peer_id], target_y)


func _refuse(peer_id: int, reason: String) -> void:
	_net.rpc_id(peer_id, "client_refused", reason)
	# Give the refusal RPC a beat to flush before closing the connection.
	get_tree().create_timer(0.25).timeout.connect(func() -> void:
		var mp_peer := multiplayer.multiplayer_peer
		if mp_peer != null and peer_id in multiplayer.get_peers():
			mp_peer.disconnect_peer(peer_id))


func _ensure_match(match_id: int) -> Dictionary:
	if not _matches.has(match_id):
		_matches[match_id] = {
			"session": GameSession.new(),
			"participants": {},
			"tick": 0,
			"result_recorded": false,
		}
		print("[MatchServer] Created match %d." % match_id)
	return _matches[match_id]


# -------------------------------------------------------------------
# Server frame loop: fixed-step tick + publish, spectator routing, drain.
# -------------------------------------------------------------------

func _process(delta: float) -> void:
	_sweep_pending(delta)

	_accum += delta
	var guard := 0
	while _accum >= _tick_dt and guard < 5:
		guard += 1
		_accum -= _tick_dt
		_tick_all()

	if _draining:
		_drain_step()
	elif not _spectators.is_empty():
		_reconcile_spectators()


func _tick_all() -> void:
	var connected := multiplayer.get_peers()
	for match_id in _matches:
		var m: Dictionary = _matches[match_id]
		m["session"].tick(_tick_dt)
		m["tick"] += 1
		_detect_game_completion(m)
		_publish(match_id, m, connected)


## Push this match's snapshot to its participants and any spectators routed to it.
## Guarded against peers that closed this frame (their disconnect event may land
## after the tick that would otherwise still publish to them).
func _publish(match_id: int, m: Dictionary, connected: PackedInt32Array) -> void:
	var wire: Array = MatchSnapshot.from_session(m["session"], match_id, m["tick"]).to_wire()
	for peer_id in m["participants"]:
		if peer_id in connected:
			_net.rpc_id(peer_id, "client_snapshot", wire)
	for spec in _spectator_showing:
		if _spectator_showing[spec] == match_id and spec in connected:
			_net.rpc_id(spec, "client_snapshot", wire)


## Record the ranked result exactly once when a game reaches a winning score.
## Leaves (OPPONENT_LEFT) don't count. Re-arm when the next game starts so a
## rematch produces its own result. Skipped when either side is anonymous.
func _detect_game_completion(m: Dictionary) -> void:
	var session = m["session"]
	if (session.state == GameTypes.GameState.GAME_OVER
			and session.last_game_over_reason == GameTypes.GameOverReason.WIN
			and session.winning_side != GameTypes.NO_SIDE):
		if m["result_recorded"]:
			return
		m["result_recorded"] = true

		var win_side: int = session.winning_side
		var lose_side: int = (GameTypes.PlayerSide.RIGHT if win_side == GameTypes.PlayerSide.LEFT
				else GameTypes.PlayerSide.LEFT)
		var winner_peer := _peer_for_side(m, win_side)
		var loser_peer := _peer_for_side(m, lose_side)
		if winner_peer != -1 and loser_peer != -1:
			_record_ranked(winner_peer, loser_peer)
	elif session.state != GameTypes.GameState.GAME_OVER:
		m["result_recorded"] = false


func _peer_for_side(m: Dictionary, side: int) -> int:
	for peer_id in m["participants"]:
		if m["participants"][peer_id] == side:
			return peer_id
	return -1


## A game finished with a winner: update both Players' aggregates (Elo + W/L) and
## persist. Skipped when either side is anonymous (not in _players) — only
## fully-identified games are rated.
func _record_ranked(winner_peer: int, loser_peer: int) -> void:
	if not _players.has(winner_peer) or not _players.has(loser_peer):
		return
	var winner = _players[winner_peer]
	var loser = _players[loser_peer]

	# Don't record against a cold cache — a not-yet-loaded record would clobber the
	# stored rating with a fresh-from-zero one. Skip (and log) rather than corrupt.
	if not _store.is_ready(winner.player_id) or not _store.is_ready(loser.player_id):
		push_warning("[MatchServer] Skipping ranked update — record(s) not loaded yet (%s / %s)."
				% [winner.display_name, loser.display_name])
		return

	var winner_rec = _store.load_record(winner.player_id).with_display_name(winner.display_name)
	var loser_rec = _store.load_record(loser.player_id).with_display_name(loser.display_name)
	var updated := RankedService.apply_result(winner_rec, loser_rec)
	_store.save_record(updated[0])
	_store.save_record(updated[1])

	print("[MatchServer] Ranked: %s %d->%d, %s %d->%d." % [
		updated[0].display_name, winner_rec.rating, updated[0].rating,
		updated[1].display_name, loser_rec.rating, updated[1].rating])


## Drop peers that connected but never sent their hello.
func _sweep_pending(delta: float) -> void:
	var stale: Array = []
	for peer_id in _pending:
		_pending[peer_id] += delta
		if _pending[peer_id] > HELLO_TIMEOUT_SEC:
			stale.append(peer_id)
	for peer_id in stale:
		_pending.erase(peer_id)
		var mp_peer := multiplayer.multiplayer_peer
		if mp_peer != null and peer_id in multiplayer.get_peers():
			mp_peer.disconnect_peer(peer_id)


# -------------------------------------------------------------------
# Spectator routing ("Pong TV")
# -------------------------------------------------------------------

## Each spectator stays on the match it's already watching while that match is
## still worth watching — live (Serving/Playing) or in the brief game-over dwell
## (so it sees the banner and any rematch); see SpectatorRouter.should_keep_watching.
## When its match closes, or falls back to an idle "Waiting for opponent..." (one
## player left, the other stayed), the spectator is re-routed to the chosen live
## match — or, if none is live, dropped back to the loading screen (no snapshots
## flow, and the client clears its view after a short starvation timeout).
func _reconcile_spectators() -> void:
	var live_id := -2  # -2 = not computed yet; -1 = computed, none live
	for spec in _spectators:
		var current: int = _spectator_showing.get(spec, -1)
		if (current != -1 and _matches.has(current)
				and SpectatorRouter.should_keep_watching(_matches[current]["session"].state)):
			continue  # keep watching it

		if current != -1:
			_spectator_showing.erase(spec)

		if live_id == -2:
			live_id = _pick_live_match_id()
		if live_id == -1:
			continue  # nothing live → stay on the loading screen
		_spectator_showing[spec] = live_id


func _pick_live_match_id() -> int:
	var states: Array = []
	for match_id in _matches:
		states.append([match_id, _matches[match_id]["session"].state])
	return SpectatorRouter.pick_match(states)


# -------------------------------------------------------------------
# Graceful drain
# -------------------------------------------------------------------

## Begin a graceful drain: refuse new connections, drop spectators and any lone
## survivors immediately (no new client will arrive to pair with them), and let
## in-progress two-player matches finish on their own. _drain_step quits once
## nothing remains. Idempotent.
func begin_drain() -> void:
	if _draining:
		return
	_draining = true
	print("[MatchServer] Draining: refusing new connections; dropping spectators and "
			+ "waiting players; active matches will finish.")
	for spec in _spectators.keys():
		_refuse(spec, GameConfig.SERVER_DRAINING_REASON)
	_drop_waiting_clients()


## Drop every lone survivor (a waiting match's single client). Guarded so we don't
## re-issue a disconnect while a previous one is still in flight.
func _drop_waiting_clients() -> void:
	for client_id in _roster.clients_awaiting_opponent():
		if not _drain_notified.has(client_id):
			_drain_notified[client_id] = true
			_refuse(client_id, GameConfig.SERVER_DRAINING_REASON)


## Survivors appear as active matches lose a player; they can't be re-paired during
## a drain, so drop them too. Once no matches (and no spectators) remain, the drain
## is done — quit so a redeploy can bring the new server up on the same port.
func _drain_step() -> void:
	_drop_waiting_clients()
	if _roster.match_count() == 0 and _spectators.is_empty():
		print("[MatchServer] Drain complete — no matches remain; quitting.")
		get_tree().quit(0)

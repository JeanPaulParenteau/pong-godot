## Pure routing/seat-reservation policy for concurrent matches — no networking.
## Places each client into the first match with a free seat (or a new match),
## tracks occupancy, and reports when a match empties so the adapter can close
## it. Unit-tested in isolation; MatchServer is the network adapter over it.

const SEATS_PER_MATCH := 2

## Where a client was placed: {match_id: int, is_new_match: bool, accepted: bool}.
## accepted is false only when the server is at the match cap (REJECTED).
const REJECTED := {"match_id": 0, "is_new_match": false, "accepted": false}

var _match_clients := {}  # match_id -> Dictionary[peer_id -> true] (used as a set)
var _client_match := {}   # peer_id -> match_id
var _max_matches: int
var _next_match_id: int


## first_match_id: id handed to the first match opened.
## max_matches: per-process cap on concurrent matches; 0 or less = unlimited.
func _init(first_match_id := 1, max_matches := 0) -> void:
	_next_match_id = first_match_id
	_max_matches = max_matches


func match_count() -> int:
	return _match_clients.size()


## Matches with both seats filled — a game in progress, not a lone survivor.
func active_match_count() -> int:
	var n := 0
	for clients in _match_clients.values():
		if clients.size() >= SEATS_PER_MATCH:
			n += 1
	return n


## Clients sitting in an under-filled ("waiting") match — a survivor with no opponent.
## On a graceful drain these are released immediately, since no new client will be
## seated to pair with them.
func clients_awaiting_opponent() -> Array:
	var waiting := []
	for clients in _match_clients.values():
		if clients.size() < SEATS_PER_MATCH:
			waiting.append_array(clients.keys())
	return waiting


## Reserve a seat for a client. Idempotent: a client already placed returns its
## current match with is_new_match = false. Returns REJECTED when the server is
## at the match cap and no open seat exists — the caller should refuse the
## connection ("server full").
func reserve(client_id: int) -> Dictionary:
	if _client_match.has(client_id):
		return {"match_id": _client_match[client_id], "is_new_match": false, "accepted": true}

	for match_id in _match_clients:
		var clients: Dictionary = _match_clients[match_id]
		if clients.size() < SEATS_PER_MATCH:
			clients[client_id] = true
			_client_match[client_id] = match_id
			return {"match_id": match_id, "is_new_match": false, "accepted": true}

	# Every open match is full and a new one would exceed the cap → reject.
	if _max_matches > 0 and _match_clients.size() >= _max_matches:
		return REJECTED

	var id := _next_match_id
	_next_match_id += 1
	_match_clients[id] = {client_id: true}
	_client_match[client_id] = id
	return {"match_id": id, "is_new_match": true, "accepted": true}


## Remove a client. Returns the match id if that match is now empty (caller
## should close it), otherwise -1 (the match still has a player waiting).
func release(client_id: int) -> int:
	if not _client_match.has(client_id):
		return -1
	var id: int = _client_match[client_id]
	_client_match.erase(client_id)

	if _match_clients.has(id):
		var clients: Dictionary = _match_clients[id]
		clients.erase(client_id)
		if clients.is_empty():
			_match_clients.erase(id)
			return id
	return -1


## The match a client is seated in, or -1.
func match_for_client(client_id: int) -> int:
	return _client_match.get(client_id, -1)


func is_client_in_match(client_id: int, match_id: int) -> bool:
	return _match_clients.has(match_id) and _match_clients[match_id].has(client_id)

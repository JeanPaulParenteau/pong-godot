## Player store over Supabase PostgREST. warm() (on connect) fetches a player's
## row into an in-memory cache via GET; load_record() reads the cache so it never
## blocks the server tick; save_record() updates the cache and writes behind via
## an upsert POST. is_ready() gates the match-end recorder so a slow/failed fetch
## can't overwrite a stored rating with a fresh-from-zero one. HTTPRequest nodes
## run on the supplied host node (the MatchServer) — all on the main thread, so
## the cache needs no locking.
##
## Server-only — the service_role key bypasses RLS and must never ship in a client.
## Configured from PONG_SUPABASE_URL + PONG_SUPABASE_KEY (same table/columns as
## the Unity original: players(player_id, display_name, rating, wins, losses,
## games_played)).

const PlayerRecord := preload("res://src/server/player_record.gd")

var _url := ""   # e.g. https://abcd.supabase.co (no trailing slash)
var _key := ""   # service_role secret
var _host: Node  # parent for HTTPRequest nodes
var _cache := {}  # player_id -> PlayerRecord
var _ready := {}  # player_id -> true (set)


func _init(host: Node, url: String, service_key: String) -> void:
	_host = host
	_url = url.rstrip("/")
	_key = service_key


## Build from env if configured; null otherwise (caller keeps the in-memory default).
static func try_create(host: Node):  # -> SupabasePlayerStore or null
	var url := OS.get_environment("PONG_SUPABASE_URL")
	var key := OS.get_environment("PONG_SUPABASE_KEY")
	if url.is_empty() or key.is_empty():
		return null
	print("[Supabase] Player store configured from env; ranked results will persist.")
	return new(host, url, key)


func is_ready(player_id: String) -> bool:
	return _ready.has(player_id)


func load_record(player_id: String):  # -> PlayerRecord
	return _cache.get(player_id, PlayerRecord.new_player(player_id, ""))


func warm(player_id: String) -> void:
	if player_id.is_empty() or _ready.has(player_id):
		return
	var req := _make_request()
	var url := "%s/rest/v1/players?select=*&player_id=eq.%s" % [_url, player_id.uri_encode()]
	req.request_completed.connect(func(result: int, code: int, _headers: PackedStringArray,
			body: PackedByteArray) -> void:
		req.queue_free()
		if result != HTTPRequest.RESULT_SUCCESS or code < 200 or code >= 300:
			push_warning("[Supabase] Warm %s failed (result=%d, http=%d); ranked update will be skipped if still cold at match end." % [player_id, result, code])
			return
		_cache[player_id] = _parse_first(body.get_string_from_utf8(), player_id)
		_ready[player_id] = true)
	if req.request(url, _auth_headers()) != OK:
		push_warning("[Supabase] Warm %s: request() failed." % player_id)
		req.queue_free()


func save_record(record) -> void:
	_cache[record.player_id] = record  # cache stays authoritative for subsequent loads
	_ready[record.player_id] = true
	var req := _make_request()
	var body := JSON.stringify({
		"player_id": record.player_id,
		"display_name": record.display_name,
		"rating": record.rating,
		"wins": record.wins,
		"losses": record.losses,
		"games_played": record.games_played,
	})
	var headers := _auth_headers()
	headers.append("Content-Type: application/json")
	headers.append("Prefer: resolution=merge-duplicates,return=minimal")  # upsert, no echo
	req.request_completed.connect(func(result: int, code: int, _h: PackedStringArray,
			_b: PackedByteArray) -> void:
		req.queue_free()
		if result != HTTPRequest.RESULT_SUCCESS or code < 200 or code >= 300:
			push_warning("[Supabase] Upsert %s failed (result=%d, http=%d) — rating change not persisted." % [record.player_id, result, code]))
	if req.request("%s/rest/v1/players" % _url, headers, HTTPClient.METHOD_POST, body) != OK:
		push_warning("[Supabase] Upsert %s: request() failed." % record.player_id)
		req.queue_free()


func _make_request() -> HTTPRequest:
	var req := HTTPRequest.new()
	_host.add_child(req)
	return req


func _auth_headers() -> PackedStringArray:
	return PackedStringArray([
		"apikey: " + _key,
		"Authorization: Bearer " + _key,
	])


## Parse a PostgREST select response (a JSON array) into a record; an empty
## array means an unseen player → start fresh.
func _parse_first(json_text: String, player_id: String):  # -> PlayerRecord
	var parsed = JSON.parse_string(json_text)
	if parsed is Array and not parsed.is_empty() and parsed[0] is Dictionary:
		var row: Dictionary = parsed[0]
		return PlayerRecord.new(
			str(row.get("player_id", player_id)),
			str(row.get("display_name", "")),
			int(row.get("rating", 0)),
			int(row.get("wins", 0)),
			int(row.get("losses", 0)),
			int(row.get("games_played", 0)))
	return PlayerRecord.new_player(player_id, "")

# GdUnit4 suite — SupabasePlayerStore through its request seam. The store builds
# one HTTP request per warm/save via an injectable _request_factory; a FakeRequest
# adapter captures what would hit PostgREST and lets each test script the response
# by emitting request_completed. No sockets — the REST/cache/write-behind rules
# are what's under test, especially the "never rate against a cold cache" gate.
extends GdUnitTestSuite

const SupabasePlayerStore = preload("res://src/server/supabase_player_store.gd")
const PlayerRecord = preload("res://src/server/player_record.gd")


## Captures one request; tests fire `request_completed` to play the server.
class FakeRequest extends Node:
	signal request_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray)
	var url := ""
	var headers := PackedStringArray()
	var method: int = HTTPClient.METHOD_GET
	var body := ""

	func request(p_url: String, p_headers := PackedStringArray(),
			p_method: int = HTTPClient.METHOD_GET, p_body := "") -> int:
		url = p_url
		headers = p_headers
		method = p_method
		body = p_body
		return OK

	func respond(result: int, code: int, json_text := "") -> void:
		request_completed.emit(result, code, PackedStringArray(), json_text.to_utf8_buffer())


var _store
var _requests: Array = []


func before_test() -> void:
	_requests = []
	_store = SupabasePlayerStore.new(self, "https://example.supabase.co/", "sekrit")
	_store._request_factory = func() -> Node:
		var req := FakeRequest.new()
		_requests.append(req)
		return req


func _last_request() -> FakeRequest:
	return _requests.back()


func test_warm_requests_the_players_row_with_auth() -> void:
	_store.warm("abc123")
	assert_int(_requests.size()).is_equal(1)
	var req := _last_request()
	assert_str(req.url).is_equal("https://example.supabase.co/rest/v1/players?select=*&player_id=eq.abc123")
	assert_array(req.headers).contains(["apikey: sekrit", "Authorization: Bearer sekrit"])
	assert_bool(_store.is_ready("abc123")).is_false()  # cold until the row lands


func test_successful_warm_caches_the_stored_record() -> void:
	_store.warm("abc")
	_last_request().respond(HTTPRequest.RESULT_SUCCESS, 200,
			'[{"player_id":"abc","display_name":"Neo","rating":42,"wins":3,"losses":1,"games_played":4}]')
	assert_bool(_store.is_ready("abc")).is_true()
	var rec = _store.load_record("abc")
	assert_int(rec.rating).is_equal(42)
	assert_int(rec.wins).is_equal(3)
	assert_str(rec.display_name).is_equal("Neo")


func test_unseen_player_warms_to_a_fresh_record() -> void:
	_store.warm("newbie")
	_last_request().respond(HTTPRequest.RESULT_SUCCESS, 200, "[]")
	assert_bool(_store.is_ready("newbie")).is_true()
	assert_int(_store.load_record("newbie").games_played).is_equal(0)


func test_failed_warm_stays_cold_so_ratings_cannot_be_clobbered() -> void:
	_store.warm("abc")
	_last_request().respond(HTTPRequest.RESULT_SUCCESS, 500)
	assert_bool(_store.is_ready("abc")).is_false()


func test_transport_error_stays_cold() -> void:
	_store.warm("abc")
	_last_request().respond(HTTPRequest.RESULT_CANT_CONNECT, 0)
	assert_bool(_store.is_ready("abc")).is_false()


func test_warm_is_a_no_op_once_ready() -> void:
	_store.warm("abc")
	_last_request().respond(HTTPRequest.RESULT_SUCCESS, 200, "[]")
	_store.warm("abc")
	assert_int(_requests.size()).is_equal(1)  # no second fetch


func test_save_record_is_immediately_authoritative_in_the_cache() -> void:
	# Write-behind: the cache answers before (and regardless of) the HTTP echo.
	_store.save_record(PlayerRecord.new("abc", "Neo", 99, 5, 2, 7))
	assert_bool(_store.is_ready("abc")).is_true()
	assert_int(_store.load_record("abc").rating).is_equal(99)


func test_save_record_upserts_the_full_row() -> void:
	_store.save_record(PlayerRecord.new("abc", "Neo", 99, 5, 2, 7))
	var req := _last_request()
	assert_int(req.method).is_equal(HTTPClient.METHOD_POST)
	assert_str(req.url).is_equal("https://example.supabase.co/rest/v1/players")
	assert_array(req.headers).contains(["Prefer: resolution=merge-duplicates,return=minimal"])
	var row: Dictionary = JSON.parse_string(req.body)
	assert_that(row["player_id"]).is_equal("abc")
	assert_that(int(row["rating"])).is_equal(99)
	assert_that(int(row["games_played"])).is_equal(7)


func test_malformed_response_parses_to_a_fresh_record() -> void:
	var rec = _store._parse_first("definitely not json", "abc")
	assert_str(rec.player_id).is_equal("abc")
	assert_int(rec.games_played).is_equal(0)

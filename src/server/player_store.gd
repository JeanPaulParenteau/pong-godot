## The persistence seam for Player aggregates, plus the in-memory default.
##
## The server owns one store; ranked results are read and written through it. The
## production implementation is SupabasePlayerStore (REST, write-behind); this
## in-memory store is the test/dev default — durable only for the process lifetime.
## Kept deliberately sync-and-simple: a networked adapter caches reads and writes
## behind so it never blocks the server tick.
##
## Store contract (duck-typed; SupabasePlayerStore implements the same methods):
##   warm(player_id)      — begin loading a player's record into the cache (called at
##                          connect, so it is warm by match end). No-op when always-ready.
##   is_ready(player_id)  — true when load() would return the player's *real* record
##                          (cache warmed), not a cold-miss default. The match-end
##                          recorder checks this so a slow or failed fetch can never
##                          clobber a stored rating with a fresh-from-zero one.
##   load_record(id)      — the stored record, or a fresh PlayerRecord if unseen.
##   save_record(record)  — persist the record (upsert by player_id).

const PlayerRecord := preload("res://src/server/player_record.gd")

var _records := {}  # player_id -> PlayerRecord


func warm(_player_id: String) -> void:
	pass  # always ready — nothing to fetch


func is_ready(_player_id: String) -> bool:
	return true


func load_record(player_id: String):  # -> PlayerRecord
	return _records.get(player_id, PlayerRecord.new_player(player_id, ""))


func save_record(record) -> void:
	_records[record.player_id] = record

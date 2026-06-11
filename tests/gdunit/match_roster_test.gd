# GdUnit4 suite — MatchRoster: the pure seat-reservation policy behind the
# server. Ported from the legacy runner.
extends GdUnitTestSuite

const MatchRoster = preload("res://src/shared/match_roster.gd")


func test_clients_fill_matches_first_free_seat_first() -> void:
	var roster := MatchRoster.new()
	var p1 := roster.reserve(10)
	assert_bool(p1["accepted"]).is_true()
	assert_bool(p1["is_new_match"]).is_true()
	assert_int(p1["match_id"]).is_equal(1)
	var p2 := roster.reserve(20)
	assert_int(p2["match_id"]).is_equal(1)
	assert_bool(p2["is_new_match"]).is_false()
	var p3 := roster.reserve(30)
	assert_int(p3["match_id"]).is_equal(2)
	assert_bool(p3["is_new_match"]).is_true()


func test_reserve_is_idempotent_for_a_seated_client() -> void:
	var roster := MatchRoster.new()
	roster.reserve(10)
	roster.reserve(20)
	var again := roster.reserve(10)
	assert_int(again["match_id"]).is_equal(1)
	assert_bool(again["is_new_match"]).is_false()


func test_lookups_report_seating_and_waiting() -> void:
	var roster := MatchRoster.new()
	roster.reserve(10)
	roster.reserve(20)
	roster.reserve(30)
	assert_int(roster.match_for_client(20)).is_equal(1)
	assert_bool(roster.is_client_in_match(20, 1)).is_true()
	assert_bool(roster.is_client_in_match(20, 2)).is_false()
	assert_array(roster.clients_awaiting_opponent()).is_equal([30])
	assert_int(roster.active_match_count()).is_equal(1)


func test_release_closes_the_match_only_when_it_empties() -> void:
	var roster := MatchRoster.new()
	roster.reserve(10)
	roster.reserve(20)
	assert_int(roster.release(10)).is_equal(-1)  # one player still waiting
	assert_int(roster.release(20)).is_equal(1)   # now empty -> close it


func test_the_match_cap_rejects_and_recovers() -> void:
	var capped := MatchRoster.new(1, 1)
	capped.reserve(1)
	capped.reserve(2)
	assert_bool(capped.reserve(3)["accepted"]).is_false()
	capped.release(1)
	assert_bool(capped.reserve(3)["accepted"]).is_true()

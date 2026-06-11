# GdUnit4 suite — RankedService + PlayerRecord + the in-memory PlayerStore.
# Ported from the legacy runner.
extends GdUnitTestSuite

const GameConfig = preload("res://src/shared/game_config.gd")
const PlayerRecord = preload("res://src/server/player_record.gd")
const PlayerStore = preload("res://src/server/player_store.gd")
const RankedService = preload("res://src/server/ranked_service.gd")


func test_apply_result_bumps_both_aggregates_and_applies_elo() -> void:
	var w = PlayerRecord.new("a", "Alice", 100, 2, 1, 3)
	var l = PlayerRecord.new("b", "Bob", 100, 1, 2, 3)
	var updated := RankedService.apply_result(w, l)
	assert_int(updated[0].wins).is_equal(3)
	assert_int(updated[0].losses).is_equal(1)
	assert_int(updated[0].games_played).is_equal(4)
	assert_int(updated[1].wins).is_equal(1)
	assert_int(updated[1].losses).is_equal(3)
	assert_int(updated[1].games_played).is_equal(4)
	assert_int(updated[0].rating).is_equal(116)
	assert_int(updated[1].rating).is_equal(84)


func test_in_memory_store_is_always_ready() -> void:
	assert_bool(PlayerStore.new().is_ready("x")).is_true()


func test_unseen_player_starts_fresh() -> void:
	assert_int(PlayerStore.new().load_record("x").rating).is_equal(GameConfig.ELO_START_RATING)


func test_store_round_trips_a_record() -> void:
	var store := PlayerStore.new()
	store.save_record(PlayerRecord.new("a", "Alice", 116, 3, 1, 4))
	assert_int(store.load_record("a").rating).is_equal(116)

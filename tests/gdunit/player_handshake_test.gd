# GdUnit4 suite — PlayerHandshake: wire round-trip + name sanitization. Ported
# from the legacy runner.
extends GdUnitTestSuite

const GameConfig = preload("res://src/shared/game_config.gd")
const PlayerHandshake = preload("res://src/shared/player_handshake.gd")


func test_name_is_trimmed_on_construction() -> void:
	assert_str(PlayerHandshake.new("abc123", "  Ben  ").display_name).is_equal("Ben")


func test_handshake_round_trips_the_wire() -> void:
	var decoded = PlayerHandshake.try_decode(PlayerHandshake.new("abc123", "Ben").encode())
	assert_object(decoded).is_not_null()
	assert_str(decoded.player_id).is_equal("abc123")
	assert_str(decoded.display_name).is_equal("Ben")


func test_non_handshake_payloads_decode_to_null() -> void:
	assert_object(PlayerHandshake.try_decode("")).is_null()
	assert_object(PlayerHandshake.try_decode(GameConfig.SPECTATOR_TOKEN)).is_null()
	assert_object(PlayerHandshake.try_decode("garbage")).is_null()


func test_sanitize_falls_back_strips_and_clamps() -> void:
	assert_str(PlayerHandshake.sanitize_name("")).is_equal(PlayerHandshake.DEFAULT_NAME)
	assert_str(PlayerHandshake.sanitize_name("a%sb" % String.chr(31))).is_equal("ab")  # control chars stripped
	assert_int(PlayerHandshake.sanitize_name("12345678901234567890").length()) \
			.is_equal(PlayerHandshake.MAX_NAME_LENGTH)

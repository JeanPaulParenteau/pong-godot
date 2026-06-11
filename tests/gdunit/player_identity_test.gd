# GdUnit4 suite — PlayerIdentity persists through a ConfigFile at
# PlayerIdentity.file_path. Tests point that at a throwaway user:// file so they
# never touch (or regenerate!) the real device identity on a dev machine.
extends GdUnitTestSuite

const PlayerIdentity = preload("res://src/client/player_identity.gd")
const PlayerHandshake = preload("res://src/shared/player_handshake.gd")

const TEST_PATH := "user://test_identity.cfg"


func before_test() -> void:
	PlayerIdentity.file_path = TEST_PATH
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))


func after_test() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
	PlayerIdentity.file_path = "user://identity.cfg"


func test_player_id_is_32_hex_chars() -> void:
	var id := PlayerIdentity.player_id()
	assert_int(id.length()).is_equal(32)
	assert_bool(id.is_valid_hex_number()).is_true()


func test_player_id_is_stable_across_accesses() -> void:
	# Created on first access, persisted, and re-read — not regenerated.
	assert_str(PlayerIdentity.player_id()).is_equal(PlayerIdentity.player_id())


func test_fresh_installs_get_distinct_ids() -> void:
	var first := PlayerIdentity.player_id()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))  # "reinstall"
	assert_str(PlayerIdentity.player_id()).is_not_equal(first)


func test_display_name_defaults_until_set() -> void:
	assert_str(PlayerIdentity.display_name()).is_equal(PlayerHandshake.DEFAULT_NAME)


func test_set_display_name_persists_sanitized() -> void:
	PlayerIdentity.set_display_name("  Neo  ")
	assert_str(PlayerIdentity.display_name()).is_equal("Neo")


func test_overlong_names_are_clamped() -> void:
	PlayerIdentity.set_display_name("A".repeat(40))
	assert_int(PlayerIdentity.display_name().length()).is_equal(PlayerHandshake.MAX_NAME_LENGTH)


func test_current_builds_the_handshake_from_persisted_identity() -> void:
	PlayerIdentity.set_display_name("Trinity")
	var hs = PlayerIdentity.current()
	assert_str(hs.player_id).is_equal(PlayerIdentity.player_id())
	assert_str(hs.display_name).is_equal("Trinity")

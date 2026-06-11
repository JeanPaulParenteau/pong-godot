# GdUnit4 suite — Settings persists through a ConfigFile at Settings.file_path.
# Tests point that at a throwaway user:// file so they never touch the real
# settings.cfg on a dev machine. apply() is exercised implicitly by the setters;
# headless its AudioServer/DisplayServer calls are harmless no-ops.
extends GdUnitTestSuite

const Settings = preload("res://src/client/settings.gd")

const TEST_PATH := "user://test_settings.cfg"


func before_test() -> void:
	Settings.file_path = TEST_PATH
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))


func after_test() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
	Settings.file_path = "user://settings.cfg"


func test_defaults_are_unmuted_and_windowed() -> void:
	assert_bool(Settings.muted()).is_false()
	assert_bool(Settings.fullscreen()).is_false()


func test_set_muted_persists() -> void:
	Settings.set_muted(true)
	assert_bool(Settings.muted()).is_true()  # re-reads from disk — proves the write landed


func test_set_fullscreen_persists() -> void:
	Settings.set_fullscreen(true)
	assert_bool(Settings.fullscreen()).is_true()


func test_settings_are_independent() -> void:
	Settings.set_muted(true)
	Settings.set_fullscreen(true)
	Settings.set_muted(false)
	assert_bool(Settings.muted()).is_false()
	assert_bool(Settings.fullscreen()).is_true()  # untouched by the muted write

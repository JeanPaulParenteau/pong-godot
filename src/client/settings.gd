## Player-facing client settings (sound, fullscreen), persisted to user:// and
## applied through the engine in one place. Read by the menu's toggle buttons;
## applied once at client startup and on every change.

# Where settings persist. A var (not const) so tests can point it at a throwaway
# file instead of the player's real settings.cfg.
static var file_path := "user://settings.cfg"

const SECTION := "client"


static func muted() -> bool:
	return _load().get_value(SECTION, "muted", false)


static func set_muted(value: bool) -> void:
	_save("muted", value)
	apply()


static func fullscreen() -> bool:
	return _load().get_value(SECTION, "fullscreen", false)


static func set_fullscreen(value: bool) -> void:
	_save("fullscreen", value)
	apply()


## Push the persisted settings into the engine (audio bus, window mode).
static func apply() -> void:
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), muted())
	var mode := DisplayServer.window_get_mode()
	if fullscreen() and mode != DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	elif not fullscreen() and mode == DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)


static func _load() -> ConfigFile:
	var cfg := ConfigFile.new()
	cfg.load(file_path)  # missing file is fine — treated as defaults
	return cfg


static func _save(key: String, value) -> void:
	var cfg := _load()
	cfg.set_value(SECTION, key, value)
	cfg.save(file_path)

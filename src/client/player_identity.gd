## The local device-bound, unauthenticated Player: a stable id generated on first
## launch plus a self-chosen display name, persisted in user:// and sent on
## connect as a PlayerHandshake. Clearing user data / reinstalling yields a new
## Player by design — identity does not survive that, and is never authenticated.

const PlayerHandshake := preload("res://src/shared/player_handshake.gd")

const FILE_PATH := "user://identity.cfg"
const SECTION := "player"


## The stable id for this install, created and persisted on first access.
static func player_id() -> String:
	var cfg := _load()
	var id: String = cfg.get_value(SECTION, "id", "")
	if id.is_empty():
		id = _new_guid()
		cfg.set_value(SECTION, "id", id)
		cfg.save(FILE_PATH)
	return id


## The player's chosen handle, sanitized. Defaults to PlayerHandshake.DEFAULT_NAME
## until set.
static func display_name() -> String:
	return PlayerHandshake.sanitize_name(_load().get_value(SECTION, "name", ""))


static func set_display_name(value: String) -> void:
	var cfg := _load()
	cfg.set_value(SECTION, "name", PlayerHandshake.sanitize_name(value))
	cfg.save(FILE_PATH)


## The handshake to send on connect.
static func current():  # -> PlayerHandshake
	return PlayerHandshake.new(player_id(), display_name())


static func _load() -> ConfigFile:
	var cfg := ConfigFile.new()
	cfg.load(FILE_PATH)  # missing file is fine — treated as empty
	return cfg


static func _new_guid() -> String:
	# 32 hex chars from a CSPRNG — equivalent to the Unity Guid.NewGuid().ToString("N").
	var bytes := Crypto.new().generate_random_bytes(16)
	return bytes.hex_encode()

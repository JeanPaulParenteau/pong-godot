## Debug-only viewport screenshotter. The reliable way to *see* the running game,
## especially on Android where `adb screencap` can't read Godot's GL SurfaceView —
## the engine's own `get_image()` always can. main.gd adds this node only in
## `OS.is_debug_build()`, so it can never run in a release build.
##
## Two modes (combinable):
##   F12                 → save one timestamped-by-counter shot to user://shots/
##   --shot-interval N   → overwrite user://cap.png every N frames (for adb-driven
##                         testing: drive the app with `input tap`, then pull the
##                         file with `adb exec-out run-as <pkg> cat files/cap.png`)
##
## On Android, user:// is the app's files dir, so pulls are:
##   adb exec-out run-as com.parenteau.ponggodot cat files/cap.png > cap.png
extends Node

const CAP_PATH := "user://cap.png"
const SHOT_DIR := "user://shots"

var _interval := 0
var _frame := 0
var _shot_n := 0


## interval: frames between continuous captures (0 = manual F12 only).
func setup(interval: int) -> void:
	_interval = maxi(0, interval)
	if _interval > 0:
		print("[DebugCapture] capturing %s every %d frames" % [CAP_PATH, _interval])


func _process(_delta: float) -> void:
	if _interval <= 0:
		return
	_frame += 1
	if _frame % _interval == 0:
		_save(CAP_PATH)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F12:
		DirAccess.make_dir_recursive_absolute(SHOT_DIR)
		var path := "%s/shot_%03d.png" % [SHOT_DIR, _shot_n]
		_shot_n += 1
		_save(path)
		print("[DebugCapture] saved ", path)


func _save(path: String) -> void:
	var tex := get_viewport().get_texture()
	if tex == null:
		return
	tex.get_image().save_png(path)

## Headless UI-layout smoke test. Pure unit tests don't render, so the class of
## bug that shipped in v0.1.0–0.1.2 (Controls parented under the plain Node scene
## root left at size 0×0 → menu off-screen, menu hidden, Leave button invisible)
## was invisible to them. This boots the real client node graph (Main → Net,
## OnlineMatch, GameRenderer, ConnectScreen — exactly as main.gd wires it),
## lets layout settle, and asserts the geometry invariants those bugs violated:
##   - ConnectScreen / GameRenderer actually fill the viewport (not 0×0)
##   - the menu panel is visible, sized, and fully on-screen
##   - the corner Leave buttons have a real rect (the 0×0-anchor bug)
##
## Run:  godot --headless --path . --script tests/ui_smoke.gd   (exits 0/1)
extends SceneTree

const NetBridge := preload("res://src/net/net_bridge.gd")
const OnlineMatch := preload("res://src/client/online_match.gd")
const GameRenderer := preload("res://src/client/game_renderer.gd")
const ConnectScreen := preload("res://src/client/connect_screen.gd")

var _screen
var _renderer
var _frames := 0
var _tests := 0
var _failures := 0


func _initialize() -> void:
	# Headless boots a tiny 64×64 root window, so host the UI in a SubViewport with
	# a realistic landscape size — that becomes get_viewport() for the Controls, so
	# _fit_to_viewport sees real dimensions instead of 64×64.
	var sub := SubViewport.new()
	sub.size = Vector2i(1280, 720)
	root.add_child(sub)

	# Mirror main.gd's CLIENT graph EXACTLY: the Controls hang off a plain Node
	# (not the viewport), which is the whole reason they need explicit sizing.
	var main := Node.new()
	main.name = "Main"
	sub.add_child(main)

	var net := NetBridge.new()
	net.name = "Net"
	main.add_child(net)

	var online := OnlineMatch.new()
	online.name = "OnlineMatch"
	main.add_child(online)
	online.start(net)

	_renderer = GameRenderer.new()
	_renderer.name = "GameRenderer"
	main.add_child(_renderer)

	_screen = ConnectScreen.new()
	_screen.name = "ConnectScreen"
	_screen.setup(net, online)
	main.add_child(_screen)


func _process(_delta: float) -> bool:
	# Give _ready, _fit_to_viewport, and a few _process/layout passes time to settle.
	_frames += 1
	if _frames < 5:
		return false

	_run_checks()

	print("")
	if _failures == 0:
		print("UI SMOKE PASSED (%d checks)" % _tests)
	else:
		print("%d/%d UI CHECKS FAILED" % [_failures, _tests])
	quit(0 if _failures == 0 else 1)
	return true


func check(cond: bool, name: String) -> void:
	_tests += 1
	if not cond:
		_failures += 1
		print("FAIL: " + name)


func _run_checks() -> void:
	var vp: Vector2 = _screen.get_viewport().get_visible_rect().size
	check(vp.x > 0.0 and vp.y > 0.0, "viewport has a non-zero size (got %s)" % vp)

	# The two top-level Controls must fill the viewport (the off-screen-menu bug
	# left these at 0×0 because anchors resolve against a 0×0 Node parent).
	check(_screen.size.x > 0.0 and _screen.size.y > 0.0,
			"ConnectScreen filled the viewport (got %s)" % _screen.size)
	check(_renderer.size.x > 0.0 and _renderer.size.y > 0.0,
			"GameRenderer filled the viewport (got %s)" % _renderer.size)

	# Menu panel: visible at startup (the offline-peer bug hid it behind the
	# in-match leave state), sized, and fully within the viewport (not off-screen).
	var mp: Control = _screen._menu_panel
	check(mp.visible, "menu panel is visible at startup")
	check(mp.size.x > 0.0 and mp.size.y > 0.0, "menu panel is sized (got %s)" % mp.size)
	check(_on_screen(mp, vp), "menu panel is on-screen")

	# Corner Leave buttons: a real rect even while hidden (the 0×0 anchor bug made
	# them invisible, stranding touch players in a match with no way out).
	check(_on_screen(_screen._leave_button, vp), "online Leave button is sized + on-screen")
	check(_on_screen(_screen._solo_leave_button, vp), "solo Leave button is sized + on-screen")


# A Control whose rect is non-empty and fully inside [0,0]-vp (1px slack).
func _on_screen(c: Control, vp: Vector2) -> bool:
	var r := Rect2(c.global_position, c.size)
	if r.size.x <= 0.0 or r.size.y <= 0.0:
		print("  (off: zero-size rect %s)" % r)
		return false
	if r.position.x < -1.0 or r.position.y < -1.0 or r.end.x > vp.x + 1.0 or r.end.y > vp.y + 1.0:
		print("  (off: rect %s outside %s)" % [r, vp])
		return false
	return true

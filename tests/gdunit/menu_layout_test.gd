# GdUnit4 UI-layout suite — the guard against the "Controls under a plain Node root
# left at 0×0 / off-screen" bug class (grey screen, hidden menu, missing Leave
# button — shipped in v0.1.0–0.1.3). Boots the real client node graph exactly as
# main.gd wires it, in a sized SubViewport (headless boots a 64×64 root window),
# lets layout settle, and asserts the geometry invariants those bugs violated.
extends GdUnitTestSuite

const NetBridge = preload("res://src/net/net_bridge.gd")
const OnlineMatch = preload("res://src/client/online_match.gd")
const GameRenderer = preload("res://src/client/game_renderer.gd")
const ConnectScreen = preload("res://src/client/connect_screen.gd")

const VP := Vector2(1280, 720)

var _screen
var _renderer


func before_test() -> void:
	var sub := SubViewport.new()
	sub.size = Vector2i(int(VP.x), int(VP.y))
	add_child(auto_free(sub))

	# Mirror main.gd's CLIENT graph: Controls hang off a plain Node (not the
	# viewport), which is exactly why they need explicit sizing.
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

	# Let _ready, _fit_to_viewport, and a few layout/_process passes settle.
	for i in 6:
		await get_tree().process_frame


func test_top_level_controls_fill_the_viewport() -> void:
	assert_float(_screen.size.x).is_greater(0.0)
	assert_float(_screen.size.y).is_greater(0.0)
	assert_float(_renderer.size.x).is_greater(0.0)
	assert_float(_renderer.size.y).is_greater(0.0)


func test_menu_panel_is_visible_sized_and_on_screen() -> void:
	var mp: Control = _screen._menu_panel
	assert_bool(mp.visible).is_true()
	assert_float(mp.size.x).is_greater(0.0)
	assert_float(mp.size.y).is_greater(0.0)
	assert_bool(_on_screen(mp)).is_true()


func test_leave_buttons_are_on_screen() -> void:
	# Hidden by default, but must still have a real on-screen rect (the off-screen
	# corner-button bug stranded touch players in a match with no way out).
	assert_bool(_on_screen(_screen._leave_button)).is_true()
	assert_bool(_on_screen(_screen._solo_leave_button)).is_true()


# A Control's rect is non-empty and fully inside [0,0]–VP (1px slack).
func _on_screen(c: Control) -> bool:
	var r := Rect2(c.global_position, c.size)
	return (r.size.x > 0.0 and r.size.y > 0.0
			and r.position.x >= -1.0 and r.position.y >= -1.0
			and r.end.x <= VP.x + 1.0 and r.end.y <= VP.y + 1.0)

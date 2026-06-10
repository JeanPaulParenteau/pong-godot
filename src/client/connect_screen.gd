## Client connect screen: type a server IP/port or pick one discovered on the LAN,
## set a display name, then connect. Auto-reconnects with backoff on an unexpected
## drop. The menu chrome is code-built Control nodes; the connection/reconnect/
## spectator decisions live in the pure ConnectionFlow state machine — this node
## just pumps multiplayer signals + timer ticks into it and renders state/status.
## Also hosts the solo (vs CPU) overlay: in-match Leave and the result screen.
extends Control

const GameConfig := preload("res://src/shared/game_config.gd")
const GameTypes := preload("res://src/shared/game_types.gd")
const MatchSource := preload("res://src/shared/match_source.gd")
const PlayerHandshake := preload("res://src/shared/player_handshake.gd")
const BotProfile := preload("res://src/shared/bot_profile.gd")
const ConnectionFlow := preload("res://src/client/connection_flow.gd")
const PlayerIdentity := preload("res://src/client/player_identity.gd")
const Palette := preload("res://src/client/palette.gd")
const LanDiscovery := preload("res://src/client/lan_discovery.gd")
const LocalMatch := preload("res://src/client/local_match.gd")

var _net: Node      # NetBridge
var _online: Node   # OnlineMatch

var _ip: String = GameConfig.PRODUCTION_SERVER_ADDRESS
var _port_text := str(GameConfig.DEFAULT_PORT)
var _status := ""

# The connection/reconnect decisions live in this pure state machine.
var _flow := ConnectionFlow.new()
var _reconnect_gen := 0      # bumped to cancel any in-flight reconnect loop
var _reconnect_running := false
var _spectating := false     # "Pong TV": connected as a read-only viewer (no seat/paddle)

var _discovery: LanDiscovery = null
var _was_searching := false
var _solo: LocalMatch = null

# ---- UI nodes ----
var _menu_panel: Control
var _spectator_panel: Control
var _solo_panel: Control
var _custom_panel: Control
var _server_list: VBoxContainer
var _online_button: Button
var _lan_button: Button
var _custom_toggle: Button
var _leave_button: Button
var _solo_leave_button: Button
var _status_label: Label
var _spectator_wait_label: Label
var _solo_result_label: Label
var _name_field: LineEdit
var _ip_field: LineEdit
var _port_field: LineEdit
var _show_custom := false


func setup(net: Node, online: Node) -> void:
	_net = net
	_online = online


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	_build_ui()


# ==================================================================
# Connection lifecycle
# ==================================================================

func _on_connected() -> void:
	# A spectator ("Pong TV") connection must NOT enter the player connection flow.
	# If it did, _flow would go CONNECTED, and a later Leave (or an unexpected drop)
	# would be misread as a player drop and trigger auto-reconnect *as a player* —
	# landing on "Waiting for opponent". Spectator visibility is server-driven.
	if _spectating:
		_net.rpc_id(1, "server_hello", GameConfig.SPECTATOR_TOKEN)
		_status = ""
		return

	_flow.on_connected()
	_reconnect_gen += 1  # stop any reconnect loop
	_status = _flow.status
	# Connect as a player, carrying this device's Player identity.
	_net.rpc_id(1, "server_hello", PlayerIdentity.current().encode())


func _on_connection_failed() -> void:
	_handle_disconnect()


func _on_server_disconnected() -> void:
	_handle_disconnect()


func _handle_disconnect() -> void:
	_close_peer()
	_online.reset()

	# A spectator drop just returns to the menu (no auto-reconnect).
	if _spectating:
		_spectating = false
		_status = _online.take_refusal()
		return

	var reconnect := _flow.on_disconnected(_online.take_refusal())
	if reconnect and not _reconnect_running:
		_reconnect_loop()
	else:
		_status = _flow.status


## Reconnect with exponential backoff after an unexpected drop. The generation
## counter cancels the loop when the user leaves / connects / starts solo.
func _reconnect_loop() -> void:
	_reconnect_running = true
	_reconnect_gen += 1
	var gen := _reconnect_gen
	while true:
		var delay := _flow.next_reconnect_delay()
		_status = _flow.status
		if delay < 0.0:
			break  # attempts exhausted → ConnectionFlow.State.FAILED
		await get_tree().create_timer(delay).timeout
		if gen != _reconnect_gen:
			break
		if _is_connected():
			break
		_start_client_to(_ip, _port_text)  # flow stays RECONNECTING
		await get_tree().create_timer(2.5).timeout
		if gen != _reconnect_gen or _is_connected():
			break
	_reconnect_running = false


## Cancel an in-flight connect, or leave an established online match — without
## re-arming auto-reconnect (that's only for unexpected drops).
func _leave_online() -> void:
	_reconnect_gen += 1
	_flow.reset()
	_close_peer()
	_online.reset()
	_status = _flow.status


## Connect as a read-only spectator. Tears down any player connection first.
func _start_spectating() -> void:
	_reconnect_gen += 1
	_flow.reset()
	_close_peer()
	_online.reset()

	_spectating = true
	_status = ""
	if not _start_client_to(_ip, _port_text):
		_spectating = false
		_status = "Pong TV: connection failed to start."


## Leave Pong TV (from the loading screen or while watching) → back to the menu,
## never into a player match: the flow stays reset, so nothing can auto-reconnect
## as a player.
func _leave_spectating() -> void:
	_reconnect_gen += 1
	_flow.reset()
	_status = ""
	_spectating = false
	_close_peer()
	_online.reset()


## Start offline single-player. Tears down any in-progress/established client
## connection so a late connected_to_server can't yank the player back online.
func _start_solo(profile) -> void:
	_reconnect_gen += 1
	_flow.reset()
	_close_peer()
	_online.reset()
	_spectating = false
	_status = _flow.status

	if _solo == null:
		_solo = LocalMatch.new()
		add_child(_solo)
	_solo.begin(profile)


## User-initiated connect: mark the flow CONNECTING, then start the ENet client.
func _connect_to(ip: String, port_text: String) -> void:
	_flow.begin_connect(ip, port_text)
	_status = _flow.status
	if not _start_client_to(ip, port_text):
		_flow.reset()
		_status = "Connection failed to start."


## Mechanical ENet client start (also used by the reconnect loop, which manages
## flow state itself).
func _start_client_to(ip: String, port_text: String) -> bool:
	_close_peer()
	var port := port_text.to_int() if port_text.is_valid_int() else GameConfig.DEFAULT_PORT
	if port <= 0 or port > 65535:
		port = GameConfig.DEFAULT_PORT
	var peer := ENetMultiplayerPeer.new()
	if peer.create_client(ip.strip_edges(), port) != OK:
		return false
	multiplayer.multiplayer_peer = peer
	return true


func _close_peer() -> void:
	var peer := multiplayer.multiplayer_peer
	if peer != null:
		peer.close()
	multiplayer.multiplayer_peer = null


func _is_connected() -> bool:
	var peer := multiplayer.multiplayer_peer
	return peer != null and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


func _in_flight() -> bool:
	return (_flow.state == ConnectionFlow.State.CONNECTING
			or _flow.state == ConnectionFlow.State.RECONNECTING)


# ==================================================================
# LAN discovery
# ==================================================================

func _search_lan() -> void:
	if _discovery == null:
		_discovery = LanDiscovery.new()
		add_child(_discovery)
	_rebuild_server_list([])
	_discovery.refresh(1.5)
	_was_searching = true


func _poll_lan() -> void:
	if _discovery == null or not _was_searching or _discovery.searching():
		return
	_was_searching = false
	var found := _discovery.servers()
	_rebuild_server_list(found)
	_status = "No LAN games found." if found.is_empty() else "Found %d LAN game(s)." % found.size()


func _rebuild_server_list(servers: Array) -> void:
	for child in _server_list.get_children():
		child.queue_free()
	for s in servers:
		var server: Dictionary = s
		_add_button(_server_list, "%s  (%s:%d)" % [server["name"], server["address"], server["port"]],
				Palette.NEUTRAL, func() -> void:
					_ip = server["address"]
					_port_text = str(server["port"])
					_ip_field.text = _ip
					_port_field.text = _port_text
					_commit_name()
					_connect_to(_ip, _port_text))


# ==================================================================
# Per-frame UI state (mirrors the Unity Update loop)
# ==================================================================

func _process(_delta: float) -> void:
	_poll_lan()

	var solo_active := _solo != null and _solo.active
	var show_menu := false
	var show_spectator := false
	var show_leave := false
	var show_solo := false

	if _spectating:
		if MatchSource.current == null:
			show_spectator = true
		else:
			show_leave = true
	elif _is_connected():
		show_leave = true
	elif solo_active:
		show_solo = true
	else:
		show_menu = true

	_menu_panel.visible = show_menu
	_spectator_panel.visible = show_spectator
	_leave_button.visible = show_leave
	_solo_panel.visible = show_solo and _solo.finished
	_solo_leave_button.visible = show_solo and not _solo.finished

	if show_menu:
		_refresh_menu()
	if show_spectator:
		_spectator_wait_label.text = "Waiting for a live game" + _dots()
	if show_solo and _solo.finished:
		_solo_result_label.text = _solo.result_text


func _refresh_menu() -> void:
	_online_button.text = "Cancel" if _in_flight() else "Play Online"
	_set_button_color(_online_button, Palette.HARD if _in_flight() else Palette.ACCENT)
	_lan_button.text = "Searching LAN..." if (_discovery != null and _discovery.searching()) else "Find LAN games"
	_custom_toggle.text = "Custom server  ▾" if _show_custom else "Custom server  ▸"
	_custom_panel.visible = _show_custom
	_status_label.text = _status


func _on_online_clicked() -> void:
	if _in_flight():
		_leave_online()
		return
	_commit_name()
	_connect_to(_ip, _port_text)


func _on_leave_clicked() -> void:
	# Contextual: while watching Pong TV this must take the spectator-exit path,
	# not the player leave path.
	if _spectating:
		_leave_spectating()
	else:
		_leave_online()


func _commit_name() -> void:
	PlayerIdentity.set_display_name(_name_field.text)
	_name_field.text = PlayerIdentity.display_name()  # reflect the sanitized value


static func _dots() -> String:
	return ".".repeat((Time.get_ticks_msec() / 500) % 4)


# ==================================================================
# UI construction (code-built Controls; no scene/asset wiring)
# ==================================================================

func _build_ui() -> void:
	_menu_panel = _card(460)
	_build_menu_panel()
	_spectator_panel = _card(440)
	_build_spectator_panel()
	_solo_panel = _card(380)
	_build_solo_panel()
	_leave_button = _corner_button("Leave", _on_leave_clicked)
	_solo_leave_button = _corner_button("Leave", func() -> void:
		if _solo != null:
			_solo.stop())


func _build_menu_panel() -> void:
	var box := _menu_panel.get_node("Box") as VBoxContainer
	_title(box, "Networked Pong")

	# Display name — persisted to PlayerIdentity, sent on connect.
	var name_row := HBoxContainer.new()
	box.add_child(name_row)
	var name_label := Label.new()
	name_label.text = "Name"
	name_label.custom_minimum_size.x = 78
	name_label.add_theme_font_size_override("font_size", 18)
	name_row.add_child(name_label)
	_name_field = LineEdit.new()
	_name_field.text = PlayerIdentity.display_name()
	_name_field.max_length = PlayerHandshake.MAX_NAME_LENGTH
	_name_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_field.custom_minimum_size.y = 46
	_name_field.add_theme_font_size_override("font_size", 18)
	_name_field.focus_exited.connect(_commit_name)
	name_row.add_child(_name_field)

	# Primary action.
	_online_button = _add_button(box, "Play Online", Palette.ACCENT, _on_online_clicked, true)

	# Single-player vs the CPU — the difficulties speak for themselves, so no blurb.
	_section_label(box, "Vs Computer")
	var cpu_row := HBoxContainer.new()
	box.add_child(cpu_row)
	_add_button(cpu_row, "Easy", Palette.EASY, func() -> void: _start_solo(BotProfile.easy()), false, true)
	_add_button(cpu_row, "Medium", Palette.MEDIUM, func() -> void: _start_solo(BotProfile.medium()), false, true)
	_add_button(cpu_row, "Hard", Palette.HARD, func() -> void: _start_solo(BotProfile.hard()), false, true)

	_add_button(box, "Pong TV (watch live)", Palette.NEUTRAL, _start_spectating)

	# Advanced, collapsed by default: a non-default server and LAN discovery live in
	# here so the home screen stays uncluttered.
	_custom_toggle = _add_button(box, "Custom server  ▸", Palette.NEUTRAL, func() -> void:
		_show_custom = not _show_custom)
	_custom_panel = VBoxContainer.new()
	box.add_child(_custom_panel)
	_ip_field = _labeled_field(_custom_panel, "Server IP", _ip, func(v: String) -> void: _ip = v)
	_port_field = _labeled_field(_custom_panel, "Port", _port_text, func(v: String) -> void: _port_text = v)
	_lan_button = _add_button(_custom_panel, "Find LAN games", Palette.NEUTRAL, _search_lan)
	_server_list = VBoxContainer.new()
	_custom_panel.add_child(_server_list)

	_status_label = Label.new()
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.add_theme_font_size_override("font_size", 16)
	_status_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
	box.add_child(_status_label)


func _build_spectator_panel() -> void:
	var box := _spectator_panel.get_node("Box") as VBoxContainer
	_title(box, "Pong TV")
	_spectator_wait_label = Label.new()
	_spectator_wait_label.text = "Waiting for a live game"
	_spectator_wait_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_spectator_wait_label.add_theme_font_size_override("font_size", 18)
	box.add_child(_spectator_wait_label)
	_add_button(box, "Leave", Palette.NEUTRAL, _leave_spectating)


func _build_solo_panel() -> void:
	var box := _solo_panel.get_node("Box") as VBoxContainer
	_solo_result_label = Label.new()
	_solo_result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_solo_result_label.add_theme_font_size_override("font_size", 26)
	box.add_child(_solo_result_label)

	_add_button(box, "Rematch", Palette.ACCENT, func() -> void: _solo.begin(_solo.profile))

	_section_label(box, "Change difficulty:")
	var row := HBoxContainer.new()
	box.add_child(row)
	_add_button(row, "Easy", Palette.EASY, func() -> void: _solo.begin(BotProfile.easy()), false, true)
	_add_button(row, "Medium", Palette.MEDIUM, func() -> void: _solo.begin(BotProfile.medium()), false, true)
	_add_button(row, "Hard", Palette.HARD, func() -> void: _solo.begin(BotProfile.hard()), false, true)

	_add_button(box, "Main Menu", Palette.NEUTRAL, func() -> void: _solo.stop())


# ---- small construction helpers ----

func _card(width: float) -> PanelContainer:
	var card := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Palette.CARD_BG
	style.set_corner_radius_all(14)
	style.set_content_margin_all(24)
	card.add_theme_stylebox_override("panel", style)
	card.custom_minimum_size.x = width
	card.set_anchors_preset(Control.PRESET_CENTER)
	card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	card.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(card)
	var box := VBoxContainer.new()
	box.name = "Box"
	box.add_theme_constant_override("separation", 8)
	card.add_child(box)
	return card


static func _title(parent: Control, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 34)
	parent.add_child(label)


static func _section_label(parent: Control, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
	parent.add_child(label)


func _add_button(parent: Control, text: String, tint: Color, on_click: Callable,
		primary := false, grow := false) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size.y = 64 if primary else 56
	b.add_theme_font_size_override("font_size", 26 if primary else 22)
	b.add_theme_color_override("font_color", Palette.BUTTON_TEXT)
	b.add_theme_color_override("font_hover_color", Palette.BUTTON_TEXT)
	b.add_theme_color_override("font_pressed_color", Palette.BUTTON_TEXT)
	_set_button_color(b, tint)
	if grow:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(on_click)
	parent.add_child(b)
	return b


static func _set_button_color(b: Button, tint: Color) -> void:
	for state_style in [["normal", 1.0], ["hover", 1.1], ["pressed", 0.85]]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color(tint.r * state_style[1], tint.g * state_style[1], tint.b * state_style[1])
		style.set_corner_radius_all(6)
		style.set_content_margin_all(8)
		b.add_theme_stylebox_override(state_style[0], style)


func _labeled_field(parent: Control, label_text: String, value: String,
		on_change: Callable) -> LineEdit:
	var label := Label.new()
	label.text = label_text
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	parent.add_child(label)
	var field := LineEdit.new()
	field.text = value
	field.custom_minimum_size.y = 44
	field.add_theme_font_size_override("font_size", 17)
	field.text_changed.connect(on_change)
	parent.add_child(field)
	return field


func _corner_button(text: String, on_click: Callable) -> Button:
	var b := _add_button(self, text, Palette.NEUTRAL, on_click)
	b.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	b.position = Vector2(-164, 14)
	b.custom_minimum_size = Vector2(150, 48)
	b.visible = false
	return b

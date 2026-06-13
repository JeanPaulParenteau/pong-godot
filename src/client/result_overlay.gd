## The unified game-over result card for BOTH solo and online — one overlay whose
## content is decided by a pure classifier (model) keyed on MatchSource state +
## snapshot, replacing the old split between the solo result panel and the online
## buttonless banner. The Control builds its children once and apply() drives them
## from the model; buttons fire injected Callables, so it owns zero match logic.
## Fills its parent and centers the card via a CenterContainer (layout-driven, so it
## can't mis-position when shown late in a session, unlike anchor-offset centering).
extends Control

const Palette := preload("res://src/client/palette.gd")
const BotProfile := preload("res://src/shared/bot_profile.gd")
const GameTypes := preload("res://src/shared/game_types.gd")


# ==================================================================
# Pure model — the tested kernel (no nodes/tree access).
# ==================================================================

## The result model for a source at game-over. `snapshot` is the source's current
## MatchSnapshot (passed in so the classifier stays pure and node-free).
static func model(source, snapshot) -> Dictionary:
	var me_right: bool = source.local_side() == GameTypes.PlayerSide.RIGHT
	var near: int = snapshot.right_score if me_right else snapshot.left_score
	var far: int = snapshot.left_score if me_right else snapshot.right_score

	var m := {
		"visible": snapshot.state == GameTypes.GameState.GAME_OVER,
		"title": _title(source, snapshot),
		"subtitle": "%d – %d" % [near, far],
	}
	if source.is_local():
		m["primary"] = {"label": "Rematch", "role": "accent", "action": "rematch"}
		m["secondary"] = {"label": "Main Menu", "role": "neutral", "action": "menu"}
		m["show_difficulty"] = true
		m["hint"] = ""
	else:
		m["primary"] = {"label": "Find new game", "role": "accent", "action": "find_new_game"}
		m["secondary"] = {"label": "Leave", "role": "neutral", "action": "leave"}
		m["show_difficulty"] = false
		m["hint"] = "Rematching..."
	return m


static func _title(source, snapshot) -> String:
	if snapshot.game_over_reason == GameTypes.GameOverReason.OPPONENT_LEFT:
		return "Opponent left"
	if source.is_local():
		return "YOU WIN!" if snapshot.winning_side == GameTypes.PlayerSide.LEFT else "CPU WINS"
	var ls: int = source.local_side()
	if ls != GameTypes.NO_SIDE and snapshot.winning_side != GameTypes.NO_SIDE:
		return "YOU WIN!" if snapshot.winning_side == ls else "YOU LOSE"
	if snapshot.winning_side == GameTypes.PlayerSide.LEFT:
		return "LEFT PLAYER WINS!"
	if snapshot.winning_side == GameTypes.PlayerSide.RIGHT:
		return "RIGHT PLAYER WINS!"
	return "Game over"


# ==================================================================
# Control — built once, driven by apply(model, callbacks).
# ==================================================================

var _title_label: Label
var _subtitle_label: Label
var _primary: Button
var _difficulty: HBoxContainer
var _secondary: Button
var _hint_label: Label
var _cb := {}
var _primary_action := ""
var _secondary_action := ""


func _ready() -> void:
	# Size to the viewport explicitly (same as ConnectScreen/GameRenderer): the
	# Control chain hangs off a plain Node, so anchors against the parent can resolve
	# to 0×0. The surround ignores the mouse so only the card's buttons capture clicks.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fit_to_viewport()
	get_viewport().size_changed.connect(_fit_to_viewport)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var card := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Palette.CARD_BG
	style.set_corner_radius_all(14)
	style.set_content_margin_all(24)
	card.add_theme_stylebox_override("panel", style)
	card.custom_minimum_size.x = 420
	center.add_child(card)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	card.add_child(box)

	_title_label = _make_label(box, 30)
	_subtitle_label = _make_label(box, 24)
	_primary = _make_button(box)
	_primary.pressed.connect(func() -> void:
		if _cb.has(_primary_action):
			_cb[_primary_action].call())

	_difficulty = HBoxContainer.new()
	box.add_child(_difficulty)
	_make_diff_button("Easy", Palette.EASY, BotProfile.easy())
	_make_diff_button("Medium", Palette.MEDIUM, BotProfile.medium())
	_make_diff_button("Hard", Palette.HARD, BotProfile.hard())

	_secondary = _make_button(box)
	_secondary.pressed.connect(func() -> void:
		if _cb.has(_secondary_action):
			_cb[_secondary_action].call())

	_hint_label = _make_label(box, 16)
	_hint_label.modulate = Color(1, 1, 1, 0.7)


func _fit_to_viewport() -> void:
	position = Vector2.ZERO
	size = get_viewport().get_visible_rect().size


## Drive the card from a model (see model()) plus a callbacks dict keyed by action
## name: "rematch", "menu", "find_new_game", "leave", "difficulty" (takes a BotProfile).
func apply(m: Dictionary, callbacks: Dictionary) -> void:
	_cb = callbacks
	_title_label.text = m["title"]
	_subtitle_label.text = m["subtitle"]
	_primary.text = m["primary"]["label"]
	_primary_action = m["primary"]["action"]
	_set_button_color(_primary, _role_color(m["primary"]["role"]))
	_secondary.text = m["secondary"]["label"]
	_secondary_action = m["secondary"]["action"]
	_difficulty.visible = m["show_difficulty"]
	_hint_label.text = m["hint"]
	_hint_label.visible = not String(m["hint"]).is_empty()


# ---- construction helpers (mirror connect_screen's card/button styling) ----

func _make_label(parent: Control, font_size: int) -> Label:
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	parent.add_child(label)
	return label


func _make_button(parent: Control) -> Button:
	var b := Button.new()
	b.custom_minimum_size.y = 56
	b.add_theme_font_size_override("font_size", 22)
	b.add_theme_color_override("font_color", Palette.BUTTON_TEXT)
	b.add_theme_color_override("font_hover_color", Palette.BUTTON_TEXT)
	b.add_theme_color_override("font_pressed_color", Palette.BUTTON_TEXT)
	_set_button_color(b, Palette.NEUTRAL)
	parent.add_child(b)
	return b


func _make_diff_button(text: String, tint: Color, profile) -> void:
	var b := _make_button(_difficulty)
	b.text = text
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_set_button_color(b, tint)
	b.pressed.connect(func() -> void:
		if _cb.has("difficulty"):
			_cb["difficulty"].call(profile))


func _role_color(role: String) -> Color:
	return Palette.ACCENT if role == "accent" else Palette.NEUTRAL


static func _set_button_color(b: Button, tint: Color) -> void:
	for state_style in [["normal", 1.0], ["hover", 1.1], ["pressed", 0.85]]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color(tint.r * state_style[1], tint.g * state_style[1], tint.b * state_style[1])
		style.set_corner_radius_all(6)
		style.set_content_margin_all(8)
		b.add_theme_stylebox_override(state_style[0], style)

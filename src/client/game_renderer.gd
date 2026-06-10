## Thin client view (custom _draw on a full-screen Control). Reads the active match
## from MatchSource, so it serves online, offline (solo), and Pong TV. Online:
## remote state (ball + opponent paddle) is drawn from a SnapshotBuffer interpolated
## ~100 ms in the past for smoothness, and the LOCAL paddle from a PaddlePredictor
## (immediate input). Solo is zero-latency (is_local), so it skips both. Discrete
## fields (state, score, banners) come from the latest snapshot. Game-feel effects
## (shake, particles, pulses, rally counter) live in the pure FxState, driven by
## MatchEvents off the authoritative counters. No game logic here.
extends Control

const GameConfig := preload("res://src/shared/game_config.gd")
const GameTypes := preload("res://src/shared/game_types.gd")
const MatchSource := preload("res://src/shared/match_source.gd")
const FieldView := preload("res://src/client/field_view.gd")
const Palette := preload("res://src/client/palette.gd")
const PaddleInput := preload("res://src/client/paddle_input.gd")
const PaddlePredictor := preload("res://src/client/paddle_predictor.gd")
const SnapshotBuffer := preload("res://src/client/snapshot_buffer.gd")
const MatchEvents := preload("res://src/client/match_events.gd")
const FxState := preload("res://src/client/fx_state.gd")

const INTERP_DELAY := 0.10  # render remote state this far in the past
const TRAIL_LENGTH := 10
const HOT_BALL := Color(1.0, 0.55, 0.25)  # tint as the ball approaches the speed cap

var _buffer := SnapshotBuffer.new()
var _predictor := PaddlePredictor.new()
var _trail: Array[Vector2] = []
var _events := MatchEvents.new()
var _fx := FxState.new()

var _has_view := false
var _latest = null  # MatchSnapshot — newest snapshot (discrete fields)
var _view = null    # MatchSnapshot — interpolated snapshot (remote positions)
var _local_paddle_y := 0.0  # predicted local paddle
var _score_flash := 0.0
var _last_total_score := -1
var _edge_clip_flash := 0.0
var _last_edge_clips := -1


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE  # gameplay input is polled, not event-driven
	# Parented under a plain Node, so fill the viewport explicitly (anchors would
	# resolve against a 0x0 parent rect, leaving FieldView mapping into nothing).
	_fit_to_viewport()
	get_viewport().size_changed.connect(_fit_to_viewport)


func _fit_to_viewport() -> void:
	position = Vector2.ZERO
	size = get_viewport().get_visible_rect().size


func _process(delta: float) -> void:
	FieldView.screen_size = size

	var source = MatchSource.current
	if source == null:
		_buffer.clear()
		_predictor.reset()
		_trail.clear()
		_events.reset()
		_fx.clear()
		_has_view = false
		_last_total_score = -1
		_last_edge_clips = -1
		FieldView.flip_x = false  # back to the absolute layout when nothing is rendered
		queue_redraw()
		return

	_latest = source.snapshot()
	# Offline solo is zero-latency: render the live state directly. Online play
	# interpolates ~100 ms in the past to smooth network jitter.
	if source.is_local():
		_view = _latest
	else:
		var now := Time.get_ticks_msec() / 1000.0
		_buffer.add(now, _latest)
		var sampled = _buffer.try_sample(now - INTERP_DELAY)
		_view = sampled if sampled != null else _latest
	_has_view = true

	# Game-feel: authoritative events → shake/particles/pulses/rally.
	for event in _events.process(_latest):
		_fx.apply_event(event, _view)
	_fx.update(delta, _latest.state)

	# Near (local) paddle: render the player's own input immediately every frame, in BOTH
	# modes — no easing toward the network-late authoritative value. Both online
	# PaddleInput and offline LocalMatch publish local_target_y; the predictor just
	# trusts the server on the very first frame, before any input.
	var side: int = source.local_side()
	if side != GameTypes.NO_SIDE and PaddleInput.has_local_target():
		var authoritative: float = (_latest.left_paddle_y if side == GameTypes.PlayerSide.LEFT
				else _latest.right_paddle_y)
		_local_paddle_y = _predictor.update(PaddleInput.local_target_y, authoritative, delta)
	else:
		_predictor.reset()

	# Ball trail follows the interpolated ball while playing.
	if _latest.state == GameTypes.GameState.PLAYING:
		_trail.append(_view.ball_position)
		while _trail.size() > TRAIL_LENGTH:
			_trail.pop_front()
	else:
		_trail.clear()

	var total: int = _latest.left_score + _latest.right_score
	if total < _last_total_score:
		_last_total_score = -1  # score dropped → new match (e.g. rematch), don't flash
	if _last_total_score >= 0 and total != _last_total_score:
		_score_flash = 1.0
	_last_total_score = total
	if _score_flash > 0.0:
		_score_flash = maxf(0.0, _score_flash - delta * 2.5)

	# Flash the field border when someone clips the ball off their own paddle edge.
	var edge: int = _latest.edge_clips
	if edge < _last_edge_clips:
		_last_edge_clips = -1  # new match
	if _last_edge_clips >= 0 and edge != _last_edge_clips:
		_edge_clip_flash = 1.0
	_last_edge_clips = edge
	if _edge_clip_flash > 0.0:
		_edge_clip_flash = maxf(0.0, _edge_clip_flash - delta * 2.0)

	queue_redraw()


func _draw() -> void:
	var source = MatchSource.current
	if source == null or not _has_view:
		return

	var side: int = source.local_side()
	var me_right := side == GameTypes.PlayerSide.RIGHT

	# Local-relative view: mirror so the local player is always the near (blue, left)
	# paddle. Spectators / unassigned (NO_SIDE) → absolute layout.
	FieldView.flip_x = me_right

	# Screen shake: a decaying random offset applied to everything in the field.
	var shake := _fx.shake_offset()
	draw_set_transform(shake)

	# Near paddle = local input every frame; far paddle (and ball) from the view.
	var near_left := side == GameTypes.PlayerSide.LEFT and PaddleInput.has_local_target()
	var near_right := side == GameTypes.PlayerSide.RIGHT and PaddleInput.has_local_target()
	var left_y: float = _local_paddle_y if near_left else _view.left_paddle_y
	var right_y: float = _local_paddle_y if near_right else _view.right_paddle_y

	# Colour by near/far (local = blue, opponent = orange), not by seat. With the mirror
	# the near paddle lands on the left in blue for both players. Hit pulses flash the
	# struck paddle toward white for a beat.
	var left_col: Color = (Palette.CPU if me_right else Palette.HUMAN).lerp(
			Color.WHITE, _fx.paddle_pulse_left * 0.7)
	var right_col: Color = (Palette.HUMAN if me_right else Palette.CPU).lerp(
			Color.WHITE, _fx.paddle_pulse_right * 0.7)

	_draw_field()
	_draw_world_rect(Vector2(-GameConfig.PADDLE_X, left_y), GameConfig.PADDLE_WIDTH,
			GameConfig.PADDLE_HALF_HEIGHT * 2.0, left_col)
	_draw_world_rect(Vector2(GameConfig.PADDLE_X, right_y), GameConfig.PADDLE_WIDTH,
			GameConfig.PADDLE_HALF_HEIGHT * 2.0, right_col)

	_draw_particles(shake)

	if _latest.state == GameTypes.GameState.PLAYING:
		_draw_trail()
	if _latest.state == GameTypes.GameState.PLAYING or _latest.state == GameTypes.GameState.SERVING:
		var ball: Vector2 = _view.ball_position if _latest.state == GameTypes.GameState.PLAYING else Vector2.ZERO
		_draw_ball(ball, shake)

	draw_set_transform(Vector2.ZERO)  # HUD (score, banners) doesn't shake

	# Scores follow the view: the local player's score sits on the near (left) half.
	var left_half_score: int = _latest.right_score if me_right else _latest.left_score
	var right_half_score: int = _latest.left_score if me_right else _latest.right_score
	_draw_score(left_half_score, right_half_score, me_right)
	_draw_rally()

	# In solo, the solo overlay draws its own result screen (YOU WIN / CPU WINS +
	# actions), so suppress the generic game-over banner to avoid double messaging.
	if not (source.is_local() and _latest.state == GameTypes.GameState.GAME_OVER):
		_draw_banner(_latest, side)

	# A brief full-field white flash when a point lands.
	if _score_flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, 0.10 * _score_flash))


func _draw_field() -> void:
	var field := FieldView.world_rect(Vector2.ZERO,
			GameConfig.FIELD_HALF_WIDTH * 2.0, GameConfig.FIELD_HALF_HEIGHT * 2.0)
	var line_color := Color(Palette.LINE.r, Palette.LINE.g, Palette.LINE.b, 0.45).lerp(
			Color(1.0, 0.45, 0.2, 0.95), _edge_clip_flash)
	_draw_outline(field, 2.0 + 1.5 * _edge_clip_flash, line_color)

	const DASHES := 15
	var seg := (GameConfig.FIELD_HALF_HEIGHT * 2.0) / DASHES
	var dash_color := Color(Palette.LINE.r, Palette.LINE.g, Palette.LINE.b, 0.22)
	for i in DASHES:
		var cy := GameConfig.FIELD_HALF_HEIGHT - (i + 0.5) * seg
		_draw_world_rect(Vector2(0.0, cy), 0.08, seg * 0.5, dash_color)


func _draw_particles(shake: Vector2) -> void:
	var ppu := FieldView.pixels_per_unit()
	for p in _fx.particles:
		var t: float = p["life"] / p["max_life"]  # 1 → fresh, 0 → expired
		var c: Color = p["color"]
		var px := FieldView.world_to_screen(p["pos"])
		var s: float = p["size"] * ppu * (0.5 + 0.5 * t)
		draw_rect(Rect2(px.x - s * 0.5, px.y - s * 0.5, s, s), Color(c.r, c.g, c.b, 0.7 * t))
	# (shake is already applied via the canvas transform; parameter kept for clarity)


func _draw_trail() -> void:
	var heat := FxState.heat(_view.ball_velocity.length())
	var c := Palette.BALL.lerp(HOT_BALL, heat)
	var n := _trail.size()
	for i in n:
		var a := float(i) / maxi(1, n)  # oldest first → most faded
		var ball_size := GameConfig.BALL_RADIUS * 2.0 * (0.3 + 0.6 * a)
		_draw_world_rect(_trail[i], ball_size, ball_size, Color(c.r, c.g, c.b, 0.05 + 0.18 * a))


## The ball with a soft two-layer glow halo, tinted hotter as it approaches the
## speed cap and squash-stretched along its heading so speed reads at a glance.
func _draw_ball(pos: Vector2, shake: Vector2) -> void:
	var ppu := FieldView.pixels_per_unit()
	var d := GameConfig.BALL_RADIUS * 2.0 * ppu
	var heat := FxState.heat(_view.ball_velocity.length())
	var c := Palette.BALL.lerp(HOT_BALL, heat)
	var center := FieldView.world_to_screen(pos) + shake

	# Screen-space heading (world Y is up, screen Y is down; mirror may flip X).
	var v: Vector2 = _view.ball_velocity
	var vx := -v.x if FieldView.flip_x else v.x
	var angle := atan2(-v.y, vx) if v.length_squared() > 1e-6 else 0.0
	var stretch := 0.30 * heat

	draw_set_transform(center, angle, Vector2(1.0 + stretch, 1.0 - stretch * 0.55))
	_centered_rect(d * 2.8, Color(c.r, c.g, c.b, 0.06 + 0.05 * heat))
	_centered_rect(d * 1.8, Color(c.r, c.g, c.b, 0.13 + 0.07 * heat))
	_centered_rect(d, c)
	draw_set_transform(shake)  # back to the shaken field transform


func _centered_rect(side_px: float, color: Color) -> void:
	draw_rect(Rect2(-side_px * 0.5, -side_px * 0.5, side_px, side_px), color)


func _draw_world_rect(world_center: Vector2, world_w: float, world_h: float, color: Color) -> void:
	draw_rect(FieldView.world_rect(world_center, world_w, world_h), color)


func _draw_outline(r: Rect2, t: float, color: Color) -> void:
	draw_rect(Rect2(r.position.x, r.position.y, r.size.x, t), color)
	draw_rect(Rect2(r.position.x, r.end.y - t, r.size.x, t), color)
	draw_rect(Rect2(r.position.x, r.position.y, t, r.size.y), color)
	draw_rect(Rect2(r.end.x - t, r.position.y, t, r.size.y), color)


func _draw_score(left: int, right: int, me_right: bool) -> void:
	var font := ThemeDB.fallback_font
	var fs := 40 + int(_score_flash * 18.0)
	var y := 64.0
	var half := size.x * 0.5
	var pad := 36.0
	var left_col := (Palette.CPU if me_right else Palette.HUMAN).lerp(Color.WHITE, _score_flash)
	var right_col := (Palette.HUMAN if me_right else Palette.CPU).lerp(Color.WHITE, _score_flash)
	draw_string(font, Vector2(0, y), str(left), HORIZONTAL_ALIGNMENT_RIGHT,
			half - pad, fs, left_col)
	draw_string(font, Vector2(half + pad, y), str(right), HORIZONTAL_ALIGNMENT_LEFT,
			half - pad, fs, right_col)


## A long rally is worth celebrating: counter fades in from RALLY_SHOW_MIN hits.
func _draw_rally() -> void:
	if _latest.state != GameTypes.GameState.PLAYING or _fx.rally < FxState.RALLY_SHOW_MIN:
		return
	var font := ThemeDB.fallback_font
	var heat := FxState.heat(_view.ball_velocity.length())
	var col := Color(1, 1, 1, 0.35).lerp(Color(1.0, 0.7, 0.3, 0.85), heat)
	draw_string(font, Vector2(0, 100), "RALLY  ×%d" % _fx.rally,
			HORIZONTAL_ALIGNMENT_CENTER, size.x, 20, col)


func _draw_banner(snap, local_side: int) -> void:
	var font := ThemeDB.fallback_font
	var msg := ""
	var fs := 36
	match snap.state:
		GameTypes.GameState.WAITING_FOR_PLAYERS:
			msg = "Waiting for opponent..."
		GameTypes.GameState.SERVING:
			# The countdown digit "pops" — largest the instant it appears, settling
			# as the second drains.
			var frac: float = snap.serve_countdown - floorf(snap.serve_countdown)
			msg = str(ceili(maxf(0.0, snap.serve_countdown)))
			fs = int(64.0 * (1.0 + 0.30 * frac))
			if FxState.is_match_point(snap.left_score, snap.right_score):
				draw_string(font, Vector2(0, size.y * 0.5 - 70.0), "MATCH POINT",
						HORIZONTAL_ALIGNMENT_CENTER, size.x, 24, Color(1.0, 0.7, 0.3, 0.9))
		GameTypes.GameState.GAME_OVER:
			if snap.game_over_reason == GameTypes.GameOverReason.OPPONENT_LEFT:
				msg = "Opponent left"
			# A player sees it from their own side; a spectator sees absolute Left/Right.
			elif snap.winning_side != GameTypes.NO_SIDE and local_side != GameTypes.NO_SIDE:
				msg = "YOU WIN!" if snap.winning_side == local_side else "YOU LOSE"
			elif snap.winning_side == GameTypes.PlayerSide.LEFT:
				msg = "LEFT PLAYER WINS!"
			elif snap.winning_side == GameTypes.PlayerSide.RIGHT:
				msg = "RIGHT PLAYER WINS!"
			else:
				msg = "Game over"
	if msg.is_empty():
		return

	var text_size := font.get_string_size(msg, HORIZONTAL_ALIGNMENT_CENTER, -1, fs)
	draw_string(font, Vector2((size.x - text_size.x) * 0.5, (size.y + text_size.y * 0.5) * 0.5),
			msg, HORIZONTAL_ALIGNMENT_CENTER, -1, fs, Color.WHITE)

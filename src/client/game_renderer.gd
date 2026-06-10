## Thin client view (custom _draw on a full-screen Control). Reads the active match
## from MatchSource, so it serves online, offline (solo), and Pong TV. Online:
## remote state (ball + opponent paddle) is drawn from a SnapshotBuffer interpolated
## ~100 ms in the past for smoothness, and the LOCAL paddle from a PaddlePredictor
## (immediate input). Solo is zero-latency (is_local), so it skips both. Discrete
## fields (state, score, banners) come from the latest snapshot. No game logic here.
extends Control

const GameConfig := preload("res://src/shared/game_config.gd")
const GameTypes := preload("res://src/shared/game_types.gd")
const MatchSource := preload("res://src/shared/match_source.gd")
const FieldView := preload("res://src/client/field_view.gd")
const Palette := preload("res://src/client/palette.gd")
const PaddleInput := preload("res://src/client/paddle_input.gd")
const PaddlePredictor := preload("res://src/client/paddle_predictor.gd")
const SnapshotBuffer := preload("res://src/client/snapshot_buffer.gd")

const INTERP_DELAY := 0.10  # render remote state this far in the past
const TRAIL_LENGTH := 10

var _buffer := SnapshotBuffer.new()
var _predictor := PaddlePredictor.new()
var _trail: Array[Vector2] = []

var _has_view := false
var _latest = null  # MatchSnapshot — newest snapshot (discrete fields)
var _view = null    # MatchSnapshot — interpolated snapshot (remote positions)
var _local_paddle_y := 0.0  # predicted local paddle
var _score_flash := 0.0
var _last_total_score := -1
var _edge_clip_flash := 0.0
var _last_edge_clips := -1


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE  # gameplay input is polled, not event-driven


func _process(delta: float) -> void:
	FieldView.screen_size = size

	var source = MatchSource.current
	if source == null:
		_buffer.clear()
		_predictor.reset()
		_trail.clear()
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

	# Near paddle = local input every frame; far paddle (and ball) from the view.
	var near_left := side == GameTypes.PlayerSide.LEFT and PaddleInput.has_local_target()
	var near_right := side == GameTypes.PlayerSide.RIGHT and PaddleInput.has_local_target()
	var left_y: float = _local_paddle_y if near_left else _view.left_paddle_y
	var right_y: float = _local_paddle_y if near_right else _view.right_paddle_y

	# Colour by near/far (local = blue, opponent = orange), not by seat. With the mirror
	# the near paddle lands on the left in blue for both players.
	var left_col: Color = Palette.CPU if me_right else Palette.HUMAN
	var right_col: Color = Palette.HUMAN if me_right else Palette.CPU

	_draw_field()
	_draw_world_rect(Vector2(-GameConfig.PADDLE_X, left_y), GameConfig.PADDLE_WIDTH,
			GameConfig.PADDLE_HALF_HEIGHT * 2.0, left_col)
	_draw_world_rect(Vector2(GameConfig.PADDLE_X, right_y), GameConfig.PADDLE_WIDTH,
			GameConfig.PADDLE_HALF_HEIGHT * 2.0, right_col)

	if _latest.state == GameTypes.GameState.PLAYING:
		_draw_trail()
	if _latest.state == GameTypes.GameState.PLAYING or _latest.state == GameTypes.GameState.SERVING:
		var ball: Vector2 = _view.ball_position if _latest.state == GameTypes.GameState.PLAYING else Vector2.ZERO
		_draw_ball(ball)

	# Scores follow the view: the local player's score sits on the near (left) half.
	var left_half_score: int = _latest.right_score if me_right else _latest.left_score
	var right_half_score: int = _latest.left_score if me_right else _latest.right_score
	_draw_score(left_half_score, right_half_score, me_right)

	# In solo, the solo overlay draws its own result screen (YOU WIN / CPU WINS +
	# actions), so suppress the generic game-over banner to avoid double messaging.
	if not (source.is_local() and _latest.state == GameTypes.GameState.GAME_OVER):
		_draw_banner(_latest, side)


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


func _draw_trail() -> void:
	var c := Palette.BALL
	var n := _trail.size()
	for i in n:
		var a := float(i) / maxi(1, n)  # oldest first → most faded
		var ball_size := GameConfig.BALL_RADIUS * 2.0 * (0.3 + 0.6 * a)
		_draw_world_rect(_trail[i], ball_size, ball_size, Color(c.r, c.g, c.b, 0.05 + 0.18 * a))


## The ball with a soft two-layer glow halo behind it.
func _draw_ball(pos: Vector2) -> void:
	var d := GameConfig.BALL_RADIUS * 2.0
	var c := Palette.BALL
	_draw_world_rect(pos, d * 2.8, d * 2.8, Color(c.r, c.g, c.b, 0.06))
	_draw_world_rect(pos, d * 1.8, d * 1.8, Color(c.r, c.g, c.b, 0.13))
	_draw_world_rect(pos, d, d, c)


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


func _draw_banner(snap, local_side: int) -> void:
	var msg := ""
	match snap.state:
		GameTypes.GameState.WAITING_FOR_PLAYERS:
			msg = "Waiting for opponent..."
		GameTypes.GameState.SERVING:
			msg = str(ceili(maxf(0.0, snap.serve_countdown)))
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

	var font := ThemeDB.fallback_font
	var fs := 64 if snap.state == GameTypes.GameState.SERVING else 36
	var text_size := font.get_string_size(msg, HORIZONTAL_ALIGNMENT_CENTER, -1, fs)
	draw_string(font, Vector2((size.x - text_size.x) * 0.5, (size.y + text_size.y * 0.5) * 0.5),
			msg, HORIZONTAL_ALIGNMENT_CENTER, -1, fs, Color.WHITE)

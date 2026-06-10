## Offline single-player: drives a local GameSession with the human on the LEFT
## paddle and a PongBot on the RIGHT. No networking — it publishes itself as the
## active match source so the existing renderer/audio draw it unchanged. Ticks the
## session on a fixed 30 Hz accumulator so physics matches online play exactly.
## The result/leave UI lives in ConnectScreen's solo overlay (which reads this node).
extends Node

const GameConfig := preload("res://src/shared/game_config.gd")
const GameTypes := preload("res://src/shared/game_types.gd")
const GameSession := preload("res://src/shared/game_session.gd")
const MatchSnapshot := preload("res://src/shared/match_snapshot.gd")
const MatchSource := preload("res://src/shared/match_source.gd")
const BotController := preload("res://src/shared/bot_controller.gd")
const FieldView := preload("res://src/client/field_view.gd")
const PaddleInput := preload("res://src/client/paddle_input.gd")

const LOCAL_MATCH_ID := 0

var active := false
var finished := false  # game over reached → freeze (suppress the session's auto-rematch)
var profile = null     # BotProfile of the current match (for Rematch)
var result_text := ""  # built once at game over

var _dt := 1.0 / GameConfig.TICK_RATE
var _session: GameSession = null
var _accum := 0.0
var _local_tick := 0
var _bot: BotController = null  # the CPU opponent's stateful driver


# ---- Match-source contract (read by GameRenderer / AudioFx) ----

func snapshot():  # -> MatchSnapshot
	if _session == null:
		return MatchSnapshot.new()
	return MatchSnapshot.from_session(_session, LOCAL_MATCH_ID, _local_tick)


func local_side() -> int:
	return GameTypes.PlayerSide.LEFT


func is_local() -> bool:
	return true


## Start (or restart) a solo match at the given difficulty.
func begin(p_profile) -> void:
	profile = p_profile
	_session = GameSession.new()
	_session.add_player()  # Left  = human
	_session.add_player()  # Right = bot → both seats filled → match begins serving
	_bot = BotController.new(p_profile)
	_accum = 0.0
	_local_tick = 0
	finished = false
	active = true
	MatchSource.set_source(self)


## Tear down and hand control back to the connect screen menu.
func stop() -> void:
	active = false
	finished = false
	_session = null
	PaddleInput.clear_local_target()  # don't leak this match's input into the next view
	MatchSource.clear(self)


func _exit_tree() -> void:
	if active:
		stop()


func _process(delta: float) -> void:
	if not active:
		return

	if Input.is_action_just_pressed("ui_cancel"):
		stop()
		return
	if finished:
		return

	# Human paddle: pointer → world Y, fed every frame (the session applies it on tick).
	var pointer_y := PaddleInput.try_get_pointer_y(get_viewport())
	if not is_nan(pointer_y):
		var target := FieldView.pointer_to_paddle_target_y(pointer_y)
		_session.set_input(GameTypes.PlayerSide.LEFT, target)
		PaddleInput.local_target_y = target  # drive the frame-rate near-paddle render

	# Fixed-step simulation (guarded against spiral-of-death after a hitch).
	_accum += delta
	var guard := 0
	while _accum >= _dt and guard < 5:
		guard += 1
		_step_once()
		_accum -= _dt
		if finished:
			break


func _step_once() -> void:
	# The bot's stateful decision (cadence, aim error, rate limit) lives in BotController.
	_session.set_input(GameTypes.PlayerSide.RIGHT,
			_bot.step(_session.ball_position, _session.ball_velocity, _dt))

	_session.tick(_dt)
	_local_tick += 1
	if _session.state == GameTypes.GameState.GAME_OVER:
		finished = true  # hold on the result screen (don't tick → no auto-rematch)
		var who := "Game over"
		if _session.winning_side == GameTypes.PlayerSide.LEFT:
			who = "YOU WIN!"
		elif _session.winning_side == GameTypes.PlayerSide.RIGHT:
			who = "CPU WINS"
		result_text = "%s   %d–%d" % [who, _session.left_score, _session.right_score]

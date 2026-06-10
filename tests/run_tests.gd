## Headless test runner: ports the Unity EditMode suite's key behaviours for the
## pure shared/client logic. Run with:
##   godot --headless --path . --script tests/run_tests.gd
## Exits 0 when green, 1 on any failure.
extends SceneTree

const GameConfig := preload("res://src/shared/game_config.gd")
const GameTypes := preload("res://src/shared/game_types.gd")
const GameSession := preload("res://src/shared/game_session.gd")
const MatchSnapshot := preload("res://src/shared/match_snapshot.gd")
const PongBot := preload("res://src/shared/pong_bot.gd")
const BotProfile := preload("res://src/shared/bot_profile.gd")
const BotController := preload("res://src/shared/bot_controller.gd")
const EloRating := preload("res://src/shared/elo_rating.gd")
const MatchRoster := preload("res://src/shared/match_roster.gd")
const SpectatorRouter := preload("res://src/shared/spectator_router.gd")
const PlayerHandshake := preload("res://src/shared/player_handshake.gd")
const DiscoveryProtocol := preload("res://src/shared/discovery_protocol.gd")
const LaunchConfig := preload("res://src/shared/launch_config.gd")
const PlayerRecord := preload("res://src/server/player_record.gd")
const PlayerStore := preload("res://src/server/player_store.gd")
const RankedService := preload("res://src/server/ranked_service.gd")
const ConnectionFlow := preload("res://src/client/connection_flow.gd")
const ReconnectPolicy := preload("res://src/client/reconnect_policy.gd")
const InputThrottle := preload("res://src/client/input_throttle.gd")
const SnapshotBuffer := preload("res://src/client/snapshot_buffer.gd")
const PaddlePredictor := preload("res://src/client/paddle_predictor.gd")
const MatchEvents := preload("res://src/client/match_events.gd")
const FxState := preload("res://src/client/fx_state.gd")

const DT := 1.0 / 30.0

var _tests := 0
var _failures := 0


func _init() -> void:
	_test_game_session()
	_test_session_physics()
	_test_bounce_math()
	_test_bot()
	_test_bot_controller()
	_test_elo()
	_test_ranked()
	_test_roster()
	_test_spectator_router()
	_test_handshake()
	_test_discovery()
	_test_launch_config()
	_test_connection_flow()
	_test_throttle()
	_test_snapshot_buffer()
	_test_predictor()
	_test_snapshot_wire()
	_test_match_events()
	_test_fx_state()

	print("")
	if _failures == 0:
		print("ALL TESTS PASSED (%d checks)" % _tests)
	else:
		print("%d/%d CHECKS FAILED" % [_failures, _tests])
	quit(0 if _failures == 0 else 1)


func check(cond: bool, name: String) -> void:
	_tests += 1
	if not cond:
		_failures += 1
		print("FAIL: " + name)


func check_approx(a: float, b: float, name: String, eps := 1e-4) -> void:
	check(absf(a - b) <= eps, "%s (got %f, want %f)" % [name, a, b])


## A session seeded for determinism, ticked into PLAYING.
func _playing_session() -> GameSession:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	var s := GameSession.new(rng)
	s.add_player()
	s.add_player()
	for i in 40:
		s.tick(DT)
		if s.state == GameTypes.GameState.PLAYING:
			break
	return s


# -------------------------------------------------------------------

func _test_game_session() -> void:
	var s := GameSession.new()
	check(s.state == GameTypes.GameState.WAITING_FOR_PLAYERS, "session starts waiting")
	check(s.add_player() == GameTypes.PlayerSide.LEFT, "first player gets left")
	check(s.state == GameTypes.GameState.WAITING_FOR_PLAYERS, "one player still waiting")
	check(s.add_player() == GameTypes.PlayerSide.RIGHT, "second player gets right")
	check(s.state == GameTypes.GameState.SERVING, "two players -> serving")
	check_approx(s.serve_countdown, GameConfig.SERVE_DELAY, "serve countdown set")
	check(s.add_player() == GameTypes.NO_SIDE, "third player rejected")

	var p := _playing_session()
	check(p.state == GameTypes.GameState.PLAYING, "serve countdown elapses -> playing")
	check_approx(p.ball_velocity.length(), GameConfig.BALL_BASE_SPEED, "launch at base speed", 1e-3)

	# Opponent leaves mid-game -> game over with OPPONENT_LEFT, no winner.
	p.remove_player(GameTypes.PlayerSide.RIGHT)
	check(p.state == GameTypes.GameState.GAME_OVER, "leave -> game over")
	check(p.last_game_over_reason == GameTypes.GameOverReason.OPPONENT_LEFT, "leave reason")
	check(p.winning_side == GameTypes.NO_SIDE, "no winner on leave")

	# Game-over dwell with one seat empty -> back to waiting.
	for i in int(GameConfig.GAME_OVER_DELAY / DT) + 2:
		p.tick(DT)
	check(p.state == GameTypes.GameState.WAITING_FOR_PLAYERS, "dwell with empty seat -> waiting")

	# Paddle easing: input far away moves at most PADDLE_SPEED * dt per tick.
	var e := _playing_session()
	e.teleport_paddle(GameTypes.PlayerSide.LEFT, 0.0)
	e.set_input(GameTypes.PlayerSide.LEFT, 10.0)  # clamped to PADDLE_MAX_Y on apply
	var before := e.left_paddle_y
	e.tick(DT)
	check_approx(e.left_paddle_y - before, GameConfig.PADDLE_SPEED * DT,
			"paddle eases at capped speed", 1e-4)


func _test_session_physics() -> void:
	# Wall bounce reflects Y and counts.
	var s := _playing_session()
	s.teleport_ball(Vector2(0.0, GameConfig.BALL_MAX_Y - 0.05), Vector2(0.0, 5.0))
	var walls := s.wall_hit_count
	s.tick(DT)
	check(s.ball_velocity.y < 0.0, "wall bounce reflects down")
	check(s.wall_hit_count == walls + 1, "wall hit counted")
	check(s.ball_position.y <= GameConfig.BALL_MAX_Y + 1e-5, "ball clamped at wall")

	# Front-face paddle bounce: reflects X, speeds up, reseats flush.
	s = _playing_session()
	s.teleport_paddle(GameTypes.PlayerSide.RIGHT, 0.0)
	s.set_input(GameTypes.PlayerSide.RIGHT, 0.0)
	s.teleport_ball(Vector2(GameConfig.PADDLE_X - GameConfig.BALL_RADIUS - 0.1, 0.0), Vector2(8.0, 0.0))
	var hits := s.paddle_hit_count
	s.tick(DT)
	check(s.ball_velocity.x < 0.0, "paddle bounce reflects left")
	check(s.paddle_hit_count == hits + 1, "paddle hit counted")
	check_approx(s.ball_velocity.length(), 8.0 + GameConfig.BALL_SPEED_STEP, "bounce adds speed step", 1e-3)
	check_approx(s.ball_position.x, GameConfig.PADDLE_X - GameConfig.BALL_RADIUS, "ball reseated at face", 1e-4)

	# Tunneling guard: a very fast ball still bounces (leading-edge sweep).
	s = _playing_session()
	s.teleport_paddle(GameTypes.PlayerSide.RIGHT, 0.0)
	s.set_input(GameTypes.PlayerSide.RIGHT, 0.0)
	s.teleport_ball(Vector2(GameConfig.PADDLE_X - 2.0, 0.0), Vector2(120.0, 0.0))
	s.tick(DT)
	check(s.ball_velocity.x < 0.0, "fast ball cannot tunnel through paddle")

	# Edge clip: contact in the edge band keeps X heading and self-scores.
	s = _playing_session()
	s.teleport_paddle(GameTypes.PlayerSide.RIGHT, 0.0)
	s.set_input(GameTypes.PlayerSide.RIGHT, 0.0)
	s.teleport_ball(Vector2(GameConfig.PADDLE_X - GameConfig.BALL_RADIUS - 0.1, 1.0), Vector2(8.0, 0.0))
	var clips := s.edge_clip_count
	var left_score := s.left_score
	s.tick(DT)
	check(s.edge_clip_count == clips + 1, "edge clip counted")
	check(s.ball_velocity.x > 0.0, "edge clip keeps heading toward the goal")
	for i in 30:
		if s.left_score != left_score:
			break
		s.tick(DT)
	check(s.left_score == left_score + 1, "edge clip concedes the point (self-score)")

	# Clean miss scores and serves toward the scored-on side.
	s = _playing_session()
	s.teleport_paddle(GameTypes.PlayerSide.RIGHT, GameConfig.PADDLE_MIN_Y)
	s.set_input(GameTypes.PlayerSide.RIGHT, GameConfig.PADDLE_MIN_Y)
	s.teleport_ball(Vector2(GameConfig.PADDLE_X - 0.5, 3.0), Vector2(10.0, 0.0))
	for i in 30:
		if s.left_score == 1:
			break
		s.tick(DT)
	check(s.left_score == 1, "clean miss -> left scores")
	check(s.state == GameTypes.GameState.SERVING, "score -> serving again")

	# Win at WIN_SCORE.
	s = _playing_session()
	for point in GameConfig.WIN_SCORE:
		# Force a left goal each rally.
		for i in 200:
			if s.state == GameTypes.GameState.PLAYING:
				break
			s.tick(DT)
		s.teleport_paddle(GameTypes.PlayerSide.RIGHT, GameConfig.PADDLE_MIN_Y)
		s.set_input(GameTypes.PlayerSide.RIGHT, GameConfig.PADDLE_MIN_Y)
		s.teleport_ball(Vector2(GameConfig.PADDLE_X - 0.5, 3.0), Vector2(12.0, 0.0))
		for i in 60:
			if s.state != GameTypes.GameState.PLAYING:
				break
			s.tick(DT)
	check(s.state == GameTypes.GameState.GAME_OVER, "win score -> game over")
	check(s.last_game_over_reason == GameTypes.GameOverReason.WIN, "game over reason is win")
	check(s.winning_side == GameTypes.PlayerSide.LEFT, "left player wins")

	# Rematch: both players present, dwell elapses -> a fresh serve at 0-0.
	for i in int(GameConfig.GAME_OVER_DELAY / DT) + 2:
		s.tick(DT)
	check(s.state == GameTypes.GameState.SERVING, "rematch after dwell with both seated")
	check(s.left_score == 0 and s.right_score == 0, "rematch resets the score")


func _test_bounce_math() -> void:
	# Pure bounce: centre hit, still paddle -> horizontal at speed+step.
	var v: Vector2 = GameSession._bounce_off_paddle(Vector2(8.0, 0.0), 0.0, 0.0, 0.0, false)
	check_approx(v.y, 0.0, "centre hit, no spin -> horizontal", 1e-4)
	check_approx(v.length(), 9.2, "bounce speed = speed + step", 1e-3)
	check(v.x < 0.0, "bounce reverses X")

	# Offset hit: top of the face -> MAX_BOUNCE_ANGLE_DEG upward.
	v = GameSession._bounce_off_paddle(Vector2(8.0, 0.0), GameConfig.PADDLE_HALF_HEIGHT, 0.0, 0.0, false)
	check_approx(rad_to_deg(atan2(v.y, -v.x)), GameConfig.MAX_BOUNCE_ANGLE_DEG,
			"edge-of-face hit deflects at max bounce angle", 0.01)

	# Spin: paddle at full speed adds a capped MAX_SPIN_ANGLE_DEG.
	v = GameSession._bounce_off_paddle(Vector2(8.0, 0.0), 0.0, 0.0, GameConfig.PADDLE_SPEED, false)
	check_approx(rad_to_deg(atan2(v.y, -v.x)), GameConfig.MAX_SPIN_ANGLE_DEG,
			"full-speed paddle spin hits the spin cap", 0.01)
	# (PADDLE_SPEED * PADDLE_SPIN_DEG_PER_UNIT = 35.2 > 30 -> the cap binds.)
	check(GameConfig.PADDLE_SPEED * GameConfig.PADDLE_SPIN_DEG_PER_UNIT > GameConfig.MAX_SPIN_ANGLE_DEG,
			"spin tuning keeps the cap reachable")

	# Total angle cap: max offset + max spin clamps at MAX_TOTAL_BOUNCE_ANGLE_DEG.
	v = GameSession._bounce_off_paddle(Vector2(8.0, 0.0), GameConfig.PADDLE_HALF_HEIGHT, 0.0,
			GameConfig.PADDLE_SPEED, false)
	check_approx(rad_to_deg(atan2(v.y, -v.x)), GameConfig.MAX_TOTAL_BOUNCE_ANGLE_DEG,
			"offset + spin clamps at the total cap", 0.01)

	# Speed cap.
	v = GameSession._bounce_off_paddle(Vector2(15.5, 0.0), 0.0, 0.0, 0.0, false)
	check_approx(v.length(), GameConfig.BALL_MAX_SPEED, "speed clamps at the cap", 1e-3)

	# Edge deflect keeps the X heading and pushes away from the paddle centre.
	v = GameSession._edge_deflect(Vector2(8.0, 0.0), 0.5)
	check(v.x > 0.0 and v.y > 0.0, "top-tip clip pushes up, keeps heading")
	v = GameSession._edge_deflect(Vector2(8.0, 0.0), -0.5)
	check(v.x > 0.0 and v.y < 0.0, "bottom-tip clip pushes down, keeps heading")


func _test_bot() -> void:
	check_approx(PongBot.desired_aim_y(Vector2(0, 2), Vector2(-5, 0), false), 0.0,
			"bot centres when ball moves away")
	check_approx(PongBot.desired_aim_y(Vector2(0, 2), Vector2(5, 0), false), 2.0,
			"bot chases ball y without prediction")

	# Straight-line intercept (no wall bounce).
	var y := PongBot.intercept_y(Vector2(0.0, 0.0), Vector2(7.0, 1.0))
	var t := (GameConfig.PADDLE_X - GameConfig.BALL_RADIUS) / 7.0
	check_approx(y, t * 1.0, "straight intercept", 1e-4)

	# fold_into_field: triangle-wave reflection.
	check_approx(PongBot.fold_into_field(0.0), 0.0, "fold identity in range")
	check_approx(PongBot.fold_into_field(GameConfig.BALL_MAX_Y + 1.0),
			GameConfig.BALL_MAX_Y - 1.0, "fold reflects off the top")
	check_approx(PongBot.fold_into_field(GameConfig.BALL_MIN_Y - 1.0),
			GameConfig.BALL_MIN_Y + 1.0, "fold reflects off the bottom")

	# Rate-limited step clamps to paddle range.
	check_approx(PongBot.rate_limited_step(0.0, 100.0, 0.5), 0.5, "rate limit binds")
	check_approx(PongBot.rate_limited_step(GameConfig.PADDLE_MAX_Y, 100.0, 5.0),
			GameConfig.PADDLE_MAX_Y, "step clamps to paddle max")

	# Edge-safe aim keeps the worst sample on the front face.
	var safe := PongBot.edge_safe_offset(0.8)
	check_approx(safe, GameConfig.PADDLE_HALF_HEIGHT - GameConfig.BALL_RADIUS,
			"sloppy tier capped a ball radius inside the face")
	check_approx(PongBot.edge_safe_offset(0.12), 0.12, "tight tier unchanged")
	check_approx(PongBot.edge_safe_aim(2.0, 3.5, 0.8), 2.0 + safe, "aim error clamped toward target")
	check_approx(PongBot.edge_safe_aim(2.0, 2.1, 0.8), 2.1, "aim inside the safe band is a no-op")


func _test_bot_controller() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var bot := BotController.new(BotProfile.medium(), rng)
	# First step commits an aim immediately (timer pre-armed) and rate-limits travel.
	var y1 := bot.step(Vector2(0, 3.0), Vector2(5, 0), DT)
	check(absf(y1) <= BotProfile.medium().max_speed * DT + 1e-5,
			"bot travel rate-limited on first step")
	# Marching on, it approaches the (error-biased) aim near 3.0.
	var y := y1
	for i in 120:
		y = bot.step(Vector2(0, 3.0), Vector2(5, 0), DT)
	check(absf(y - 3.0) <= BotProfile.medium().aim_error + 1e-3,
			"bot settles within aim error of the target")

	# Determinism: same seed, same trajectory.
	var rng2 := RandomNumberGenerator.new()
	rng2.seed = 42
	var bot2 := BotController.new(BotProfile.medium(), rng2)
	var y2 := bot2.step(Vector2(0, 3.0), Vector2(5, 0), DT)
	check_approx(y1, y2, "seeded bot is deterministic")


func _test_elo() -> void:
	check_approx(EloRating.expected_score(0, 0), 0.5, "equal ratings -> 0.5 expected")
	var r := EloRating.after_win(0, 0)
	check(r[0] == 16 and r[1] == -16, "equal-rating win moves +-K/2")
	r = EloRating.after_win(400, 0)
	check(r[0] - 400 < 16, "expected win earns little")
	var upset := EloRating.after_win(0, 400)
	check(upset[0] > 16, "upset earns more than K/2")
	check((upset[0] - 0) == -(upset[1] - 400), "elo is zero-sum")


func _test_ranked() -> void:
	var w = PlayerRecord.new("a", "Alice", 100, 2, 1, 3)
	var l = PlayerRecord.new("b", "Bob", 100, 1, 2, 3)
	var updated := RankedService.apply_result(w, l)
	check(updated[0].wins == 3 and updated[0].losses == 1 and updated[0].games_played == 4,
			"winner aggregates bumped")
	check(updated[1].wins == 1 and updated[1].losses == 3 and updated[1].games_played == 4,
			"loser aggregates bumped")
	check(updated[0].rating == 116 and updated[1].rating == 84, "elo applied to both")

	var store := PlayerStore.new()
	check(store.is_ready("x"), "in-memory store always ready")
	check(store.load_record("x").rating == GameConfig.ELO_START_RATING, "unseen player starts fresh")
	store.save_record(updated[0])
	check(store.load_record("a").rating == 116, "store round-trips a record")


func _test_roster() -> void:
	var roster := MatchRoster.new()
	var p1 := roster.reserve(10)
	check(p1["accepted"] and p1["is_new_match"] and p1["match_id"] == 1, "first client opens match 1")
	var p2 := roster.reserve(20)
	check(p2["match_id"] == 1 and not p2["is_new_match"], "second client fills match 1")
	var p3 := roster.reserve(30)
	check(p3["match_id"] == 2 and p3["is_new_match"], "third client opens match 2")
	var again := roster.reserve(10)
	check(again["match_id"] == 1 and not again["is_new_match"], "reserve is idempotent")

	check(roster.match_for_client(20) == 1, "match_for_client")
	check(roster.is_client_in_match(20, 1) and not roster.is_client_in_match(20, 2), "is_client_in_match")
	check(roster.clients_awaiting_opponent() == [30], "lone survivor reported as waiting")
	check(roster.active_match_count() == 1, "one full match active")

	check(roster.release(10) == -1, "releasing one of two keeps the match")
	check(roster.release(20) == 1, "releasing the last empties the match")

	var capped := MatchRoster.new(1, 1)
	capped.reserve(1)
	capped.reserve(2)
	var rejected := capped.reserve(3)
	check(not rejected["accepted"], "cap rejects a third match seat")
	capped.release(1)
	check(capped.reserve(3)["accepted"], "freed seat accepted again under cap")


func _test_spectator_router() -> void:
	check(SpectatorRouter.is_live(GameTypes.GameState.PLAYING), "playing is live")
	check(SpectatorRouter.is_live(GameTypes.GameState.SERVING), "serving is live")
	check(not SpectatorRouter.is_live(GameTypes.GameState.WAITING_FOR_PLAYERS), "waiting is not live")
	check(SpectatorRouter.should_keep_watching(GameTypes.GameState.GAME_OVER),
			"stay through the game-over dwell")
	check(not SpectatorRouter.should_keep_watching(GameTypes.GameState.WAITING_FOR_PLAYERS),
			"leave an idle match")
	check(SpectatorRouter.pick_match([
		[3, GameTypes.GameState.PLAYING],
		[1, GameTypes.GameState.WAITING_FOR_PLAYERS],
		[2, GameTypes.GameState.SERVING],
	]) == 2, "lowest live id wins")
	check(SpectatorRouter.pick_match([[1, GameTypes.GameState.WAITING_FOR_PLAYERS]]) == -1,
			"nothing live -> -1")


func _test_handshake() -> void:
	var h = PlayerHandshake.new("abc123", "  Ben  ")
	check(h.display_name == "Ben", "name trimmed on construction")
	var decoded = PlayerHandshake.try_decode(h.encode())
	check(decoded != null and decoded.player_id == "abc123" and decoded.display_name == "Ben",
			"handshake round-trips")
	check(PlayerHandshake.try_decode("") == null, "empty payload is not a handshake")
	check(PlayerHandshake.try_decode(GameConfig.SPECTATOR_TOKEN) == null,
			"spectator token is not a handshake")
	check(PlayerHandshake.try_decode("garbage") == null, "garbage is not a handshake")
	check(PlayerHandshake.sanitize_name("") == PlayerHandshake.DEFAULT_NAME, "empty name -> default")
	check(PlayerHandshake.sanitize_name("a]b".replace("]", String.chr(31))) == "ab",
			"control chars stripped")
	check(PlayerHandshake.sanitize_name("12345678901234567890").length()
			== PlayerHandshake.MAX_NAME_LENGTH, "name clamped to max length")


func _test_discovery() -> void:
	check(DiscoveryProtocol.is_request(DiscoveryProtocol.request()), "request round-trips")
	check(not DiscoveryProtocol.is_request("PONGv1|SERVER|7777|x".to_ascii_buffer()),
			"response is not a request")
	var parsed := DiscoveryProtocol.try_parse_response(DiscoveryProtocol.response(7777, "My|Server"))
	check(parsed["port"] == 7777 and parsed["name"] == "My/Server",
			"response round-trips with sanitized name")
	check(DiscoveryProtocol.try_parse_response("junk".to_ascii_buffer()).is_empty(),
			"junk rejected")


func _test_launch_config() -> void:
	var no_env := func(_key: String) -> String: return ""
	var c = LaunchConfig.parse(PackedStringArray(["--server", "--port", "9000"]), no_env)
	check(c.has_server_flag and c.port == 9000, "server flag + port arg")
	check(c.resolve_mode(false) == LaunchConfig.LaunchMode.SERVER, "server flag wins windowed")

	c = LaunchConfig.parse(PackedStringArray([]), no_env)
	check(c.resolve_mode(true) == LaunchConfig.LaunchMode.SERVER, "headless defaults to server")
	check(c.resolve_mode(false) == LaunchConfig.LaunchMode.CLIENT, "windowed defaults to client")
	check(c.port == GameConfig.DEFAULT_PORT, "default port")

	var env := func(key: String) -> String: return "8123" if key == "PONG_PORT" else ""
	c = LaunchConfig.parse(PackedStringArray([]), env)
	check(c.port == 8123, "PONG_PORT env honored")
	c = LaunchConfig.parse(PackedStringArray(["--port", "9001"]), env)
	check(c.port == 9001, "port arg beats env")

	c = LaunchConfig.parse(PackedStringArray(
		["--autoclient", "--smoke", "--address", "1.2.3.4", "--quitafter", "30",
		 "--playerid", "p1", "--playername", "Ann", "--maxmatches", "5"]), no_env)
	check(c.resolve_mode(true) == LaunchConfig.LaunchMode.AUTO_CLIENT, "autoclient flag wins headless")
	check(c.require_play and c.client_address == "1.2.3.4" and is_equal_approx(c.quit_after, 30.0),
			"smoke/address/quitafter parsed")
	check(c.player_id == "p1" and c.player_name == "Ann" and c.max_matches == 5,
			"identity + maxmatches parsed")


func _test_connection_flow() -> void:
	var f := ConnectionFlow.new()
	check(f.state == ConnectionFlow.State.IDLE, "flow starts idle")
	f.begin_connect("1.2.3.4", "7777")
	check(f.state == ConnectionFlow.State.CONNECTING, "begin_connect -> connecting")
	check(not f.on_disconnected("nope"), "initial connect failure does not reconnect")
	check(f.state == ConnectionFlow.State.IDLE and f.status == "nope", "failure surfaces the reason")

	f.begin_connect("1.2.3.4", "7777")
	f.on_connected()
	check(f.state == ConnectionFlow.State.CONNECTED, "connected")
	check(f.on_disconnected(), "unexpected drop -> reconnect")
	check(f.state == ConnectionFlow.State.RECONNECTING, "reconnecting state")
	check(not f.on_disconnected(), "failed attempt inside the loop does not re-trigger")

	var delays: Array[float] = []
	for i in ReconnectPolicy.MAX_ATTEMPTS:
		delays.append(f.next_reconnect_delay())
	check(delays == [1.0, 2.0, 4.0, 8.0], "exponential backoff 1,2,4,8")
	check(f.next_reconnect_delay() < 0.0, "attempts exhausted -> -1")
	check(f.state == ConnectionFlow.State.FAILED, "exhausted -> failed")

	f.reset()
	check(f.state == ConnectionFlow.State.IDLE, "reset -> idle")
	f.on_connected()
	f.on_disconnected()
	check_approx(f.next_reconnect_delay(), 1.0, "backoff resets after a connect")


func _test_throttle() -> void:
	var t := InputThrottle.new()
	check(t.should_send(0.5), "first sample always sends")
	check(not t.should_send(0.5), "repeat suppressed")
	check(not t.should_send(0.51), "tiny move suppressed")
	check(t.should_send(0.6), "meaningful move sends")
	t.reset()
	check(t.should_send(0.6), "reset re-arms")


func _snap_at(tick: int, ball: Vector2, left_y := 0.0) -> MatchSnapshot:
	var s := MatchSnapshot.new()
	s.tick = tick
	s.ball_position = ball
	s.left_paddle_y = left_y
	s.state = GameTypes.GameState.PLAYING
	return s


func _test_snapshot_buffer() -> void:
	var buf := SnapshotBuffer.new()
	check(buf.try_sample(0.0) == null, "empty buffer has no sample")

	buf.add(1.0, _snap_at(1, Vector2(0, 0), 0.0))
	buf.add(2.0, _snap_at(2, Vector2(1, 0), 1.0))
	buf.add(2.0, _snap_at(2, Vector2(9, 9), 9.0))  # duplicate tick ignored
	check(buf.count() == 2, "duplicate tick deduped")

	var mid = buf.try_sample(1.5)
	check_approx(mid.ball_position.x, 0.5, "ball interpolates at the midpoint")
	check_approx(mid.left_paddle_y, 0.5, "paddle interpolates at the midpoint")
	check(buf.try_sample(0.5).ball_position == Vector2(0, 0), "clamp to oldest")
	check(buf.try_sample(3.0).ball_position == Vector2(1, 0), "clamp to newest")

	# Teleport (serve reset) snaps instead of sliding.
	buf.clear()
	buf.add(1.0, _snap_at(1, Vector2(7, 0)))
	buf.add(2.0, _snap_at(2, Vector2(0, 0)))
	check(buf.try_sample(1.5).ball_position == Vector2(0, 0), "teleport snaps to the new position")


func _test_predictor() -> void:
	var p := PaddlePredictor.new()
	check_approx(p.update(3.0, 1.5, DT), 1.5, "first frame trusts the server")
	var v := p.update(3.0, 1.5, DT)
	check_approx(v, 1.5 + GameConfig.PADDLE_SPEED * DT, "then predicts capped motion")
	p.reset()
	check_approx(p.update(3.0, 0.0, DT), 0.0, "reset re-seeds from authoritative")


func _test_snapshot_wire() -> void:
	var s := GameSession.new()
	s.add_player()
	s.add_player()
	for i in 50:
		s.tick(DT)
	var snap = MatchSnapshot.from_session(s, 7, 42)
	var back = MatchSnapshot.from_wire(snap.to_wire())
	check(back != null, "wire decodes")
	check(back.state == snap.state and back.tick == 42 and back.match_id == 7,
			"discrete fields survive the wire")
	check(back.ball_position == snap.ball_position and back.ball_velocity == snap.ball_velocity,
			"ball state survives the wire")
	check(back.left_score == snap.left_score and back.right_score == snap.right_score,
			"scores survive the wire")
	check(MatchSnapshot.from_wire([1, 2, 3]) == null, "short wire payload rejected")


func _fx_snap(paddle := 0, wall := 0, edge := 0, left := 0, right := 0,
		ball := Vector2.ZERO) -> MatchSnapshot:
	var s := MatchSnapshot.new()
	s.paddle_hits = paddle
	s.wall_hits = wall
	s.edge_clips = edge
	s.left_score = left
	s.right_score = right
	s.ball_position = ball
	s.state = GameTypes.GameState.PLAYING
	return s


func _test_match_events() -> void:
	var det := MatchEvents.new()
	check(det.process(_fx_snap(5, 3, 1, 2, 2)).is_empty(), "first snapshot only primes")
	check(det.process(_fx_snap(5, 3, 1, 2, 2)).is_empty(), "no change -> no events")
	check(det.process(_fx_snap(6, 3, 1, 2, 2)) == [MatchEvents.EV_PADDLE_HIT],
			"paddle counter bump -> paddle event")
	check(det.process(_fx_snap(7, 3, 2, 2, 2)) == [MatchEvents.EV_EDGE_CLIP],
			"edge clip suppresses the same-frame paddle event")
	var multi := det.process(_fx_snap(7, 4, 2, 3, 2))
	check(MatchEvents.EV_WALL_HIT in multi and MatchEvents.EV_SCORE in multi and multi.size() == 2,
			"wall + score in one frame both emitted")
	# Counter regression (new match on the same source) re-primes — no phantom events.
	check(det.process(_fx_snap(0, 0, 0, 0, 0)).is_empty(), "regression re-primes silently")
	check(det.process(_fx_snap(1, 0, 0, 0, 0)) == [MatchEvents.EV_PADDLE_HIT],
			"events resume after re-prime")
	det.reset()
	check(det.process(_fx_snap(9, 9, 9, 4, 1)).is_empty(), "reset re-primes")


func _test_fx_state() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var fx := FxState.new(rng)

	fx.apply_event(MatchEvents.EV_PADDLE_HIT, _fx_snap(1, 0, 0, 0, 0, Vector2(7.0, 0.0)))
	check(fx.shake > 0.0, "paddle hit raises shake")
	check(fx.rally == 1, "paddle hit counts toward the rally")
	check(fx.paddle_pulse_right == 1.0 and fx.paddle_pulse_left == 0.0,
			"hit at +x pulses the right paddle")
	check(not fx.particles.is_empty(), "paddle hit spawns particles")

	var shake_before := fx.shake
	fx.update(0.1, GameTypes.GameState.PLAYING)
	check(fx.shake < shake_before, "shake decays")
	check(fx.paddle_pulse_right < 1.0, "pulse decays")
	check(fx.rally == 1, "rally persists while playing")

	fx.apply_event(MatchEvents.EV_SCORE, _fx_snap(1, 0, 0, 1, 0, Vector2(8.0, 0.0)))
	check(fx.rally == 0, "score resets the rally")
	fx.apply_event(MatchEvents.EV_PADDLE_HIT, _fx_snap(2, 0, 0, 1, 0, Vector2(-7.0, 0.0)))
	check(fx.paddle_pulse_left == 1.0, "hit at -x pulses the left paddle")
	fx.update(0.1, GameTypes.GameState.SERVING)
	check(fx.rally == 0, "rally clears outside PLAYING")

	# Particles expire within their lifetime.
	for i in 80:
		fx.update(0.05, GameTypes.GameState.PLAYING)
	check(fx.particles.is_empty(), "particles expire")
	check(fx.shake == 0.0, "shake settles to zero")

	fx.apply_event(MatchEvents.EV_EDGE_CLIP, _fx_snap(3, 0, 1, 1, 0))
	fx.clear()
	check(fx.particles.is_empty() and fx.shake == 0.0 and fx.rally == 0, "clear wipes all FX")

	check_approx(FxState.heat(GameConfig.BALL_BASE_SPEED), 0.0, "heat 0 at launch speed")
	check_approx(FxState.heat(GameConfig.BALL_MAX_SPEED), 1.0, "heat 1 at the cap")
	check_approx(FxState.heat(0.0), 0.0, "heat clamps below")

	check(FxState.is_match_point(GameConfig.WIN_SCORE - 1, 0), "match point at win-1")
	check(FxState.is_match_point(2, GameConfig.WIN_SCORE - 1), "match point for either side")
	check(not FxState.is_match_point(GameConfig.WIN_SCORE - 2, GameConfig.WIN_SCORE - 2),
			"no match point below win-1")

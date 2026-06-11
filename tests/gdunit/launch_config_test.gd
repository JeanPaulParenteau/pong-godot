# GdUnit4 suite — LaunchConfig: argument/env parsing + mode precedence. parse()
# is pure (env injected as a Callable). Ported from the legacy runner.
extends GdUnitTestSuite

const GameConfig = preload("res://src/shared/game_config.gd")
const LaunchConfig = preload("res://src/shared/launch_config.gd")

var _no_env := func(_key: String) -> String: return ""


func test_server_flag_and_port_arg() -> void:
	var c = LaunchConfig.parse(PackedStringArray(["--server", "--port", "9000"]), _no_env)
	assert_bool(c.has_server_flag).is_true()
	assert_int(c.port).is_equal(9000)
	assert_int(c.resolve_mode(false)).is_equal(LaunchConfig.LaunchMode.SERVER)  # flag wins windowed


func test_mode_defaults_follow_the_display() -> void:
	var c = LaunchConfig.parse(PackedStringArray([]), _no_env)
	assert_int(c.resolve_mode(true)).is_equal(LaunchConfig.LaunchMode.SERVER)
	assert_int(c.resolve_mode(false)).is_equal(LaunchConfig.LaunchMode.CLIENT)
	assert_int(c.port).is_equal(GameConfig.DEFAULT_PORT)


func test_port_precedence_arg_beats_env_beats_default() -> void:
	var env := func(key: String) -> String: return "8123" if key == "PONG_PORT" else ""
	assert_int(LaunchConfig.parse(PackedStringArray([]), env).port).is_equal(8123)
	assert_int(LaunchConfig.parse(PackedStringArray(["--port", "9001"]), env).port).is_equal(9001)


func test_autoclient_flags_parse_together() -> void:
	var c = LaunchConfig.parse(PackedStringArray(
		["--autoclient", "--smoke", "--address", "1.2.3.4", "--quitafter", "30",
		 "--playerid", "p1", "--playername", "Ann", "--maxmatches", "5"]), _no_env)
	assert_int(c.resolve_mode(true)).is_equal(LaunchConfig.LaunchMode.AUTO_CLIENT)  # beats headless->server
	assert_bool(c.require_play).is_true()
	assert_str(c.client_address).is_equal("1.2.3.4")
	assert_float(c.quit_after).is_equal_approx(30.0, 1e-6)
	assert_str(c.player_id).is_equal("p1")
	assert_str(c.player_name).is_equal("Ann")
	assert_int(c.max_matches).is_equal(5)


func test_solo_and_shot_interval_parse_and_default_off() -> void:
	var c = LaunchConfig.parse(PackedStringArray(["--solo", "--shot-interval", "20"]), _no_env)
	assert_bool(c.has_solo_flag).is_true()
	assert_int(c.shot_interval).is_equal(20)
	assert_int(LaunchConfig.parse(PackedStringArray([]), _no_env).shot_interval).is_equal(0)

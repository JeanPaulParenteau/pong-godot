## The startup configuration, resolved once from command-line args + env.
## parse() is pure (args + env lookup in, config out) so the precedence rules are
## unit-tested; from_command_line() wires it to the process.
##
## Godot only forwards args after a literal `--` to the project
## (OS.get_cmdline_user_args()), so launches look like:
##   godot --headless -- --server --port 7777
## Both "--flag" and "-flag" spellings are accepted for parity with the Unity build.

const GameConfig := preload("res://src/shared/game_config.gd")

enum LaunchMode { CLIENT, SERVER, AUTO_CLIENT }

var has_server_flag := false
var has_auto_client_flag := false
var has_solo_flag := false  # client: jump straight into a vs-CPU match (dev/demo)
var port: int = GameConfig.DEFAULT_PORT
var client_address: String = GameConfig.DEFAULT_CLIENT_ADDRESS
var drop_after := -1.0    # autoclient: never, unless set
var quit_after := 8.0     # autoclient: quit after N seconds
var require_play := false # autoclient smoke: exit non-zero unless a real match was observed
var max_matches := 0      # server: per-process match cap; 0 = unlimited
var player_id := ""       # autoclient: connect as this Player (ranked smoke)
var player_name := ""     # autoclient: display name for -playerid
var shot_interval := 0    # debug builds: save a viewport PNG every N frames (0 = off)


## Mode precedence: -autoclient, then -server/-dedicated, else headless→Server / windowed→Client.
func resolve_mode(is_headless: bool) -> int:
	if has_auto_client_flag:
		return LaunchMode.AUTO_CLIENT
	if has_server_flag:
		return LaunchMode.SERVER
	return LaunchMode.SERVER if is_headless else LaunchMode.CLIENT


static func from_command_line():  # -> LaunchConfig
	# Desktop/headless pass project args after `--` (get_cmdline_user_args). The
	# Android export's command_line/extra_args land in the full arg list with no
	# `--` separator, so fall back to that — parse() ignores unrecognized flags.
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		args = OS.get_cmdline_args()
	return parse(args, func(key: String) -> String:
		return OS.get_environment(key))


## env: Callable(String) -> String ("" when unset).
static func parse(args: PackedStringArray, env: Callable):  # -> LaunchConfig
	var config = new()
	var port_arg := ""
	var max_matches_arg := ""

	for i in args.size():
		match _norm(args[i]):
			"server", "dedicated":
				config.has_server_flag = true
			"autoclient":
				config.has_auto_client_flag = true
			"solo":
				config.has_solo_flag = true
			"smoke":
				config.require_play = true
			"address":
				if i + 1 < args.size():
					config.client_address = args[i + 1]
			"port":
				if i + 1 < args.size():
					port_arg = args[i + 1]
			"maxmatches":
				if i + 1 < args.size():
					max_matches_arg = args[i + 1]
			"playerid":
				if i + 1 < args.size():
					config.player_id = args[i + 1]
			"playername":
				if i + 1 < args.size():
					config.player_name = args[i + 1]
			"dropafter":
				if i + 1 < args.size() and args[i + 1].is_valid_float():
					config.drop_after = args[i + 1].to_float()
			"quitafter":
				if i + 1 < args.size() and args[i + 1].is_valid_float():
					config.quit_after = args[i + 1].to_float()
			"shot-interval", "shotinterval":
				if i + 1 < args.size() and args[i + 1].is_valid_int():
					config.shot_interval = args[i + 1].to_int()

	# Port precedence: -port arg > PONG_PORT env > default.
	if _valid_port(port_arg):
		config.port = port_arg.to_int()
	else:
		var env_port: String = env.call("PONG_PORT")
		if _valid_port(env_port):
			config.port = env_port.to_int()

	# max_matches precedence: -maxmatches arg > PONG_MAX_MATCHES env > default (0 = unlimited).
	if max_matches_arg.is_valid_int():
		config.max_matches = max_matches_arg.to_int()
	else:
		var env_max: String = env.call("PONG_MAX_MATCHES")
		if env_max.is_valid_int():
			config.max_matches = env_max.to_int()

	return config


static func _norm(arg: String) -> String:
	return arg.trim_prefix("--").trim_prefix("-")


static func _valid_port(s: String) -> bool:
	return s.is_valid_int() and s.to_int() > 0 and s.to_int() <= 65535

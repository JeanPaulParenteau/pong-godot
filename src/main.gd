## Shared entry point. Resolves the LaunchConfig, then branches: dedicated server,
## client (menu + renderer + audio), or the headless -autoclient test harness.
## The NetBridge RPC surface is added at the same node path in every mode so
## client/server RPCs always resolve.
extends Node

const GameConfig := preload("res://src/shared/game_config.gd")
const LaunchConfig := preload("res://src/shared/launch_config.gd")
const NetBridge := preload("res://src/net/net_bridge.gd")
const MatchServer := preload("res://src/server/match_server.gd")
const SupabasePlayerStore := preload("res://src/server/supabase_player_store.gd")
const LanDiscovery := preload("res://src/client/lan_discovery.gd")
const GameRenderer := preload("res://src/client/game_renderer.gd")
const AudioFx := preload("res://src/client/audio_fx.gd")
const OnlineMatch := preload("res://src/client/online_match.gd")
const ConnectScreen := preload("res://src/client/connect_screen.gd")
const AutoClient := preload("res://src/client/autoclient.gd")
const Settings := preload("res://src/client/settings.gd")

var _server: MatchServer = null


func _ready() -> void:
	# Cap the frame loop. Without this the headless dedicated server spins its update
	# loop as fast as possible (~100% CPU forever): on a small shared-core VM that
	# exhausts CPU credits and makes the 30 Hz tick run late/irregularly → severe
	# client lag. 60 fps gives ample headroom over the tick and also smooths the client.
	Engine.max_fps = 60

	var config = LaunchConfig.from_command_line()
	var is_headless := DisplayServer.get_name() == "headless"
	var mode: int = config.resolve_mode(is_headless)
	print("[Main] Starting in %s mode." % ["Client", "Server", "AutoClient"][mode])

	var net := NetBridge.new()
	net.name = "Net"  # RPC path must match on client and server: /root/Main/Net
	add_child(net)

	match mode:
		LaunchConfig.LaunchMode.SERVER:
			# Intercept the close request so a quit drains first (window close on
			# desktop; headless SIGTERM still hard-exits, as it did on Unity).
			get_tree().auto_accept_quit = false
			_server = MatchServer.new()
			_server.name = "MatchServer"
			add_child(_server)
			# Persist ranked results to Supabase when configured; otherwise the
			# in-memory store keeps everything working (ratings reset on restart).
			var store = SupabasePlayerStore.try_create(_server)
			if not _server.start(net, config.port, config.max_matches, store):
				get_tree().quit(1)
				return
			var lan := LanDiscovery.new()
			add_child(lan)
			lan.start_responder(config.port, "Pong Dedicated Server")

		LaunchConfig.LaunchMode.CLIENT:
			Settings.apply()  # persisted sound/fullscreen preferences
			var online := OnlineMatch.new()
			online.name = "OnlineMatch"
			add_child(online)
			online.start(net)

			var renderer := GameRenderer.new()
			renderer.name = "GameRenderer"
			add_child(renderer)

			add_child(AudioFx.new())

			var screen := ConnectScreen.new()
			screen.name = "ConnectScreen"
			screen.setup(net, online)
			add_child(screen)
			if config.has_solo_flag:
				screen.debug_start_solo()

		LaunchConfig.LaunchMode.AUTO_CLIENT:
			var online := OnlineMatch.new()
			online.name = "OnlineMatch"
			add_child(online)
			online.start(net)

			var auto := AutoClient.new()
			auto.name = "AutoClient"
			add_child(auto)
			auto.start(net, online, config)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if _server != null and not _server.is_draining():
			_server.begin_drain()  # _drain_step quits once nothing remains
		else:
			get_tree().quit()

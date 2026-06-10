## Classic Pong beeps, generated procedurally (no audio assets). Plays off the
## authoritative event stream (MatchEvents over the replicated collision/score
## counters) so audio stays in lock-step with the real simulation — never a
## client-side guess. Added by main.gd on clients; skipped on headless builds.
extends Node

const MatchSource := preload("res://src/shared/match_source.gd")
const MatchEvents := preload("res://src/client/match_events.gd")

var _events := MatchEvents.new()

var _paddle_player: AudioStreamPlayer
var _wall_player: AudioStreamPlayer
var _score_player: AudioStreamPlayer
var _edge_player: AudioStreamPlayer


func _ready() -> void:
	_paddle_player = _make_player(_make_beep(459.0, 0.07))
	_wall_player = _make_player(_make_beep(226.0, 0.07))
	_score_player = _make_player(_make_beep(490.0, 0.22))
	_edge_player = _make_player(_make_beep(150.0, 0.20, 0.4))  # low buzzer: you clipped it off your own edge


func _process(_delta: float) -> void:
	var source = MatchSource.current
	if source == null:
		_events.reset()
		return

	for event in _events.process(source.snapshot()):
		match event:
			MatchEvents.EV_PADDLE_HIT:
				_paddle_player.play()
			MatchEvents.EV_WALL_HIT:
				_wall_player.play()
			MatchEvents.EV_EDGE_CLIP:
				_edge_player.play()
			MatchEvents.EV_SCORE:
				_score_player.play()


func _make_player(stream: AudioStreamWAV) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.stream = stream
	add_child(player)
	return player


## A short square-wave beep with a quick exponential decay, as 16-bit PCM.
static func _make_beep(frequency: float, duration: float, volume := 0.35) -> AudioStreamWAV:
	const RATE := 44100
	var samples := maxi(1, int(RATE * duration))
	var data := PackedByteArray()
	data.resize(samples * 2)
	for i in samples:
		var t := float(i) / RATE
		var envelope := exp(-t * 18.0)
		var square := signf(sin(TAU * frequency * t))
		var v := int(clampf(square * envelope * volume, -1.0, 1.0) * 32767.0)
		data.encode_s16(i * 2, v)

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.data = data
	return stream

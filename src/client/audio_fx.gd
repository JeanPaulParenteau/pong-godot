## Classic Pong beeps, generated procedurally (no audio assets). Watches the
## replicated, server-authoritative collision/score counters on the active match
## source and plays a sound when they increment — so audio stays in lock-step with
## the real simulation. Added by main.gd on clients; skipped on headless builds.
extends Node

const MatchSource := preload("res://src/shared/match_source.gd")

var _paddle_player: AudioStreamPlayer
var _wall_player: AudioStreamPlayer
var _score_player: AudioStreamPlayer
var _edge_player: AudioStreamPlayer

var _last_paddle := 0
var _last_wall := 0
var _last_score_total := 0
var _last_edge_clip := 0
var _primed := false


func _ready() -> void:
	_paddle_player = _make_player(_make_beep(459.0, 0.07))
	_wall_player = _make_player(_make_beep(226.0, 0.07))
	_score_player = _make_player(_make_beep(490.0, 0.22))
	_edge_player = _make_player(_make_beep(150.0, 0.20, 0.4))  # low buzzer: you clipped it off your own edge


func _process(_delta: float) -> void:
	var source = MatchSource.current
	if source == null:
		_primed = false
		return

	var snap = source.snapshot()
	var paddle: int = snap.paddle_hits
	var wall: int = snap.wall_hits
	var edge: int = snap.edge_clips
	var score_total: int = snap.left_score + snap.right_score

	# These counters only climb within a match; a drop means a new match started without
	# MatchSource going null (e.g. a solo rematch reuses the same source). Re-prime so we
	# don't replay phantom hits from the finished match.
	if paddle < _last_paddle or wall < _last_wall or edge < _last_edge_clip \
			or score_total < _last_score_total:
		_primed = false

	if not _primed:
		# Sync to current values on (re)connect so we don't replay history.
		_last_paddle = paddle
		_last_wall = wall
		_last_edge_clip = edge
		_last_score_total = score_total
		_primed = true
		return

	# An edge clip also bumps the paddle counter; play only the distinct buzzer for it
	# (suppressing the generic paddle beep that same frame) so the self-score reads clearly.
	var edge_clipped := edge != _last_edge_clip
	if edge_clipped:
		_edge_player.play()
		_last_edge_clip = edge
	if paddle != _last_paddle:
		if not edge_clipped:
			_paddle_player.play()
		_last_paddle = paddle
	if wall != _last_wall:
		_wall_player.play()
		_last_wall = wall
	if score_total != _last_score_total:
		_score_player.play()
		_last_score_total = score_total


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

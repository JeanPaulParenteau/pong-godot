# GdUnit4 suite — AudioFx: the procedural beep synth (pure) and the event→player
# wiring driven through a stub match source. Headless Godot runs a dummy audio
# driver, but AudioStreamPlayer.playing still flips on play(), which is what the
# wiring assertions read — no actual mixing is needed.
extends GdUnitTestSuite

const AudioFx = preload("res://src/client/audio_fx.gd")
const MatchSource = preload("res://src/shared/match_source.gd")
const MatchSnapshot = preload("res://src/shared/match_snapshot.gd")


## Stands in for a match source; tests mutate `snap` counters between frames.
class StubSource:
	var snap = MatchSnapshot.new()

	func snapshot():
		return snap


var _fx: AudioFx
var _source: StubSource


func before_test() -> void:
	MatchSource.current = null
	_fx = auto_free(AudioFx.new())
	add_child(_fx)  # _ready builds the four players
	_source = StubSource.new()


func after_test() -> void:
	MatchSource.current = null


## Feed one snapshot frame to the node.
func _frame() -> void:
	_fx._process(0.0)


func test_beep_is_16_bit_pcm_of_the_requested_duration() -> void:
	var beep := AudioFx._make_beep(440.0, 0.1)
	assert_int(beep.format).is_equal(AudioStreamWAV.FORMAT_16_BITS)
	assert_int(beep.data.size()).is_equal(int(44100 * 0.1) * 2)  # 2 bytes per sample


func test_beep_starts_loud_and_decays() -> void:
	var beep := AudioFx._make_beep(440.0, 0.1, 0.35)
	var first := absi(beep.data.decode_s16(2))  # one sample in (t>0, envelope ~1)
	var last := absi(beep.data.decode_s16(beep.data.size() - 2))
	assert_int(first).is_greater(int(0.2 * 32767))
	assert_int(last).is_less(first)


func test_ready_builds_one_player_per_event_kind() -> void:
	var players := _fx.get_children().filter(func(c): return c is AudioStreamPlayer)
	assert_int(players.size()).is_equal(4)


func test_first_snapshot_only_primes_no_replayed_history() -> void:
	_source.snap.paddle_hits = 7
	_source.snap.wall_hits = 3
	MatchSource.set_source(_source)
	_frame()
	assert_bool(_fx._paddle_player.playing).is_false()
	assert_bool(_fx._wall_player.playing).is_false()


func test_each_counter_bump_plays_its_own_beep() -> void:
	MatchSource.set_source(_source)
	_frame()  # prime
	_source.snap.paddle_hits += 1
	_frame()
	assert_bool(_fx._paddle_player.playing).is_true()
	assert_bool(_fx._wall_player.playing).is_false()

	_source.snap.wall_hits += 1
	_frame()
	assert_bool(_fx._wall_player.playing).is_true()


func test_score_plays_the_score_beep() -> void:
	MatchSource.set_source(_source)
	_frame()  # prime
	_source.snap.left_score += 1
	_frame()
	assert_bool(_fx._score_player.playing).is_true()


func test_losing_the_source_reprimes_so_reconnect_is_silent() -> void:
	MatchSource.set_source(_source)
	_frame()  # prime
	MatchSource.current = null
	_frame()  # source gone → detector reset
	_source.snap.paddle_hits += 5  # "history" accumulated while away
	MatchSource.set_source(_source)
	_frame()  # first frame back only re-primes
	assert_bool(_fx._paddle_player.playing).is_false()

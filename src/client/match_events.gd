## Pure detector that turns the replicated, monotonic collision/score counters on
## a match snapshot into discrete events — the one place the "what just happened"
## rule lives, shared by audio (beeps) and visual FX (shake/particles) so both
## stay in lock-step with the authoritative simulation, never a client guess.
##
## Priming semantics (ported from the Unity AudioFx): the first snapshot after a
## (re)connect only syncs the counters — no events — so history isn't replayed;
## a counter regression means a new match started without the source going null
## (e.g. a solo rematch), which re-primes the same way.

const EV_PADDLE_HIT := "paddle_hit"
const EV_WALL_HIT := "wall_hit"
const EV_EDGE_CLIP := "edge_clip"
const EV_SCORE := "score"

var _last_paddle := 0
var _last_wall := 0
var _last_edge := 0
var _last_score_total := 0
var _primed := false


func reset() -> void:
	_primed = false


## Events that occurred since the last call (empty while priming). An edge clip
## also bumps the paddle counter; only the distinct edge event is emitted for it
## (suppressing the generic paddle hit that same frame) so the self-score cue
## reads clearly.
func process(snap) -> Array:
	var paddle: int = snap.paddle_hits
	var wall: int = snap.wall_hits
	var edge: int = snap.edge_clips
	var score_total: int = snap.left_score + snap.right_score

	if paddle < _last_paddle or wall < _last_wall or edge < _last_edge \
			or score_total < _last_score_total:
		_primed = false  # counters dropped → new match on the same source

	if not _primed:
		_last_paddle = paddle
		_last_wall = wall
		_last_edge = edge
		_last_score_total = score_total
		_primed = true
		return []

	var events: Array = []
	var edge_clipped := edge != _last_edge
	if edge_clipped:
		events.append(EV_EDGE_CLIP)
		_last_edge = edge
	if paddle != _last_paddle:
		if not edge_clipped:
			events.append(EV_PADDLE_HIT)
		_last_paddle = paddle
	if wall != _last_wall:
		events.append(EV_WALL_HIT)
		_last_wall = wall
	if score_total != _last_score_total:
		events.append(EV_SCORE)
		_last_score_total = score_total
	return events

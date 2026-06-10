## The read-model a client observes for its match — one value bundling the
## replicated state, so client modules read a single snapshot instead of a
## dozen networked fields. Built by the server from a GameSession and shipped
## over the wire as a flat array (see to_wire/from_wire).

const GameTypes := preload("res://src/shared/game_types.gd")

## Sentinel stored in winning_side when no side has won yet (same as GameTypes.NO_SIDE).
const NO_WINNER := -1

var state: int = GameTypes.GameState.WAITING_FOR_PLAYERS
var ball_position := Vector2.ZERO
var ball_velocity := Vector2.ZERO
var left_paddle_y := 0.0
var right_paddle_y := 0.0
var left_score := 0
var right_score := 0
var serve_countdown := 0.0
var game_over_reason: int = GameTypes.GameOverReason.NONE
var winning_side: int = NO_WINNER  # NO_WINNER = none, else GameTypes.PlayerSide
var paddle_hits := 0
var wall_hits := 0
var edge_clips := 0
var match_id := -1
var tick := 0  # server publish sequence — clients order/dedupe snapshots for interpolation


## Assemble the read-model directly from an authoritative GameSession.
## This is the single GameSession → snapshot field mapping; the offline
## LocalMatch uses it directly, and the server publish path shares it.
static func from_session(session, p_match_id: int, p_tick: int):  # -> MatchSnapshot
	var snap = new()
	snap.state = session.state
	snap.ball_position = session.ball_position
	snap.ball_velocity = session.ball_velocity
	snap.left_paddle_y = session.left_paddle_y
	snap.right_paddle_y = session.right_paddle_y
	snap.left_score = session.left_score
	snap.right_score = session.right_score
	snap.serve_countdown = session.serve_countdown
	snap.game_over_reason = session.last_game_over_reason
	snap.winning_side = session.winning_side
	snap.paddle_hits = session.paddle_hit_count
	snap.wall_hits = session.wall_hit_count
	snap.edge_clips = session.edge_clip_count
	snap.match_id = p_match_id
	snap.tick = p_tick
	return snap


## Flat-array wire encoding (sent via unreliable RPC at the tick rate).
## The one place the field order lives; from_wire is its exact inverse.
func to_wire() -> Array:
	return [
		state, ball_position.x, ball_position.y, ball_velocity.x, ball_velocity.y,
		left_paddle_y, right_paddle_y, left_score, right_score, serve_countdown,
		game_over_reason, winning_side, paddle_hits, wall_hits, edge_clips,
		match_id, tick,
	]


static func from_wire(data: Array):  # -> MatchSnapshot or null
	if data.size() != 17:
		return null
	var snap = new()
	snap.state = int(data[0])
	snap.ball_position = Vector2(data[1], data[2])
	snap.ball_velocity = Vector2(data[3], data[4])
	snap.left_paddle_y = float(data[5])
	snap.right_paddle_y = float(data[6])
	snap.left_score = int(data[7])
	snap.right_score = int(data[8])
	snap.serve_countdown = float(data[9])
	snap.game_over_reason = int(data[10])
	snap.winning_side = int(data[11])
	snap.paddle_hits = int(data[12])
	snap.wall_hits = int(data[13])
	snap.edge_clips = int(data[14])
	snap.match_id = int(data[15])
	snap.tick = int(data[16])
	return snap

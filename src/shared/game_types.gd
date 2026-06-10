## Shared enums for the match state machine. Replicated to clients as plain ints.
##
## GDScript has no nullable ints, so "no side" / "no winner" is the NO_SIDE
## sentinel (-1) everywhere a side can be absent (spectators, unfinished games).

enum GameState {
	WAITING_FOR_PLAYERS = 0,
	SERVING = 1,
	PLAYING = 2,
	GAME_OVER = 3,
}

enum PlayerSide {
	LEFT = 0,
	RIGHT = 1,
}

enum GameOverReason {
	NONE = 0,
	WIN = 1,
	OPPONENT_LEFT = 2,
}

## Sentinel for "no side" (no winner yet / spectator / match full).
const NO_SIDE := -1

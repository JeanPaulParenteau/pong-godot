## Pure spectator routing for "Pong TV": which live match a viewer should watch.
## A match is live while it is Serving or Playing (two players actively in a
## point/rally). With several live matches the lowest match id wins, so the choice
## is stable. No networking — unit-tested in isolation; MatchServer is the adapter
## that enacts it.

const GameTypes := preload("res://src/shared/game_types.gd")


static func is_live(state: int) -> bool:
	return state == GameTypes.GameState.SERVING or state == GameTypes.GameState.PLAYING


## Whether a spectator should keep watching the match it's already on. We stay through a
## live point (Serving/Playing) and the brief GameOver dwell — so the game-over banner and
## any rematch are seen — but leave a match that has fallen back to WaitingForPlayers (e.g.
## one player left while the other stayed): an idle "Waiting for opponent..." screen the
## viewer would otherwise be stuck on. Leaving lets the router re-pick another live match.
static func should_keep_watching(state: int) -> bool:
	return is_live(state) or state == GameTypes.GameState.GAME_OVER


## The match a spectator should watch: the lowest-id live match, or -1 if none.
## matches: Array of [id: int, state: int] pairs.
static func pick_match(matches: Array) -> int:
	var best := -1
	for m in matches:
		if is_live(m[1]) and (best == -1 or m[0] < best):
			best = m[0]
	return best

## Pure, dependency-free Elo math for ranked play. Pong is a symmetric 1v1
## with exactly one winner and no draws, so the only operation is "winner beat
## loser". The server calls after_win at match end to update both Players'
## ratings. Unit-tested in isolation, like GameSession and PongBot.

const GameConfig := preload("res://src/shared/game_config.gd")


## Expected score (win probability) of rating against opponent_rating, in [0, 1].
## Equal ratings → 0.5.
static func expected_score(rating: int, opponent_rating: int) -> float:
	return 1.0 / (1.0 + pow(10.0, (opponent_rating - rating) / 400.0))


## New ratings after winner_rating beats loser_rating, as [winner, loser].
## Zero-sum and symmetric: the winner gains exactly what the loser loses (the raw
## loser delta is the negation of the raw winner delta, so one rounding keeps them
## mirrored). An expected win earns little; an upset earns near the full K.
static func after_win(winner_rating: int, loser_rating: int,
		k: int = GameConfig.ELO_K_FACTOR) -> Array:
	# Raw delta = K * (actual - expected); actual is 1 for the winner.
	# round() is round-half-away-from-zero, matching the C# original.
	var delta := int(roundf(k * (1.0 - expected_score(winner_rating, loser_rating))))
	return [winner_rating + delta, loser_rating - delta]

## The pure ranked update: given the two Players' records and who won, produce their
## updated records — Elo applied (EloRating.after_win) and win/loss/games bumped.
## No I/O; the caller loads from and saves to a player store. Unit-tested.

const EloRating := preload("res://src/shared/elo_rating.gd")
const PlayerRecord := preload("res://src/server/player_record.gd")


## Returns [updated_winner, updated_loser].
static func apply_result(winner, loser) -> Array:
	var ratings := EloRating.after_win(winner.rating, loser.rating)

	var updated_winner = PlayerRecord.new(
		winner.player_id, winner.display_name, ratings[0],
		winner.wins + 1, winner.losses, winner.games_played + 1)

	var updated_loser = PlayerRecord.new(
		loser.player_id, loser.display_name, ratings[1],
		loser.wins, loser.losses + 1, loser.games_played + 1)

	return [updated_winner, updated_loser]

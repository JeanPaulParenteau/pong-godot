## The persisted aggregate for one Player: identity, rating, and win/loss totals —
## no per-match history. Treated as immutable; updates produce a new record (see
## RankedService). This is exactly the document a player store reads and writes.

const GameConfig := preload("res://src/shared/game_config.gd")

var player_id := ""
var display_name := ""
var rating: int = GameConfig.ELO_START_RATING
var wins := 0
var losses := 0
var games_played := 0


func _init(p_player_id := "", p_display_name := "", p_rating: int = GameConfig.ELO_START_RATING,
		p_wins := 0, p_losses := 0, p_games_played := 0) -> void:
	player_id = p_player_id
	display_name = p_display_name
	rating = p_rating
	wins = p_wins
	losses = p_losses
	games_played = p_games_played


## A brand-new Player at the starting rating with no games played.
static func new_player(p_player_id: String, p_display_name: String):  # -> PlayerRecord
	return new(p_player_id, p_display_name)


## Same record with the display name refreshed to what the client last sent.
func with_display_name(p_display_name: String):  # -> PlayerRecord
	return get_script().new(player_id, p_display_name, rating, wins, losses, games_played)

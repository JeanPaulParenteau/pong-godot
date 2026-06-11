# GdUnit4 suite — SpectatorRouter: which match Pong TV shows. Ported from the
# legacy runner.
extends GdUnitTestSuite

const GameTypes = preload("res://src/shared/game_types.gd")
const SpectatorRouter = preload("res://src/shared/spectator_router.gd")


func test_live_means_serving_or_playing() -> void:
	assert_bool(SpectatorRouter.is_live(GameTypes.GameState.PLAYING)).is_true()
	assert_bool(SpectatorRouter.is_live(GameTypes.GameState.SERVING)).is_true()
	assert_bool(SpectatorRouter.is_live(GameTypes.GameState.WAITING_FOR_PLAYERS)).is_false()


func test_spectators_stay_through_the_game_over_dwell() -> void:
	assert_bool(SpectatorRouter.should_keep_watching(GameTypes.GameState.GAME_OVER)).is_true()
	assert_bool(SpectatorRouter.should_keep_watching(GameTypes.GameState.WAITING_FOR_PLAYERS)).is_false()


func test_pick_match_prefers_the_lowest_live_id() -> void:
	assert_int(SpectatorRouter.pick_match([
		[3, GameTypes.GameState.PLAYING],
		[1, GameTypes.GameState.WAITING_FOR_PLAYERS],
		[2, GameTypes.GameState.SERVING],
	])).is_equal(2)


func test_pick_match_with_nothing_live_returns_none() -> void:
	assert_int(SpectatorRouter.pick_match([[1, GameTypes.GameState.WAITING_FOR_PLAYERS]])).is_equal(-1)

# GdUnit4 suite — exemplar pure-logic test. Mirrors the Elo checks from the legacy
# runner in idiomatic GdUnit4 form (fluent assertions, one behaviour per method).
extends GdUnitTestSuite

const EloRating = preload("res://src/shared/elo_rating.gd")


func test_expected_score_is_half_for_equal_ratings() -> void:
	assert_float(EloRating.expected_score(0, 0)).is_equal_approx(0.5, 0.0001)


func test_equal_rating_win_moves_half_k_each_way() -> void:
	var r := EloRating.after_win(0, 0)
	assert_int(r[0]).is_equal(16)
	assert_int(r[1]).is_equal(-16)


func test_expected_win_earns_little() -> void:
	var r := EloRating.after_win(400, 0)
	assert_int(r[0] - 400).is_less(16)


func test_elo_is_zero_sum() -> void:
	var r := EloRating.after_win(0, 400)
	assert_int(r[0] - 0).is_equal(-(r[1] - 400))

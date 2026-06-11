# GdUnit4 suite — MatchSource is the static seam between the active match and the
# view code. Pure static state, no nodes: any object can stand in as a source, so
# plain RefCounted instances do here. The behaviour that matters is the stale-clear
# guard — a source being torn down must not wipe out a newer one.
extends GdUnitTestSuite

const MatchSource = preload("res://src/shared/match_source.gd")


func before_test() -> void:
	# Static state persists across tests — start each from the menu (no match).
	MatchSource.current = null


func test_starts_with_no_source() -> void:
	assert_object(MatchSource.current).is_null()


func test_set_source_makes_it_current() -> void:
	var source := RefCounted.new()
	MatchSource.set_source(source)
	assert_object(MatchSource.current).is_same(source)


func test_set_source_replaces_the_previous_one() -> void:
	var old := RefCounted.new()
	var new_source := RefCounted.new()
	MatchSource.set_source(old)
	MatchSource.set_source(new_source)
	assert_object(MatchSource.current).is_same(new_source)


func test_clear_removes_the_active_source() -> void:
	var source := RefCounted.new()
	MatchSource.set_source(source)
	MatchSource.clear(source)
	assert_object(MatchSource.current).is_null()


func test_clear_of_a_stale_source_does_not_clobber_the_newer_one() -> void:
	# The teardown race: source A is replaced by B, then A's teardown calls clear.
	var a := RefCounted.new()
	var b := RefCounted.new()
	MatchSource.set_source(a)
	MatchSource.set_source(b)
	MatchSource.clear(a)
	assert_object(MatchSource.current).is_same(b)


func test_clear_when_nothing_is_active_is_a_no_op() -> void:
	MatchSource.clear(RefCounted.new())
	assert_object(MatchSource.current).is_null()

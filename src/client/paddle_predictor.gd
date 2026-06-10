## Client-side prediction for the LOCAL player's paddle. The server eases the paddle
## toward the input at a capped speed; we run the *same* capped easing toward the
## player's own input locally, so the paddle responds with no network round-trip lag
## while staying in lock-step with the server (both share the cap, so there's nothing
## to reconcile). The first frame trusts the server, until the player has provided
## input. Pure → unit-tested.

const GameConfig := preload("res://src/shared/game_config.gd")

var _value := 0.0
var _has := false


func reset() -> void:
	_has = false


## Advance one frame. local_input is the player's clamped desired Y; authoritative
## seeds the very first frame (before the player has moved).
func update(local_input: float, authoritative: float, dt: float) -> float:
	if not _has:
		_value = authoritative  # first frame: trust the server
		_has = true
		return _value
	# Predict the same capped motion the server applies — no easing toward a stale server value.
	_value = move_toward(_value, local_input, GameConfig.PADDLE_SPEED * dt)
	return _value

## Gates paddle input: report a send only when the desired paddle target has moved
## past a small threshold since the last send, so the client doesn't flood the server.
## Pure, so the threshold behaviour is unit-tested without the input loop.

const EPSILON := 0.02

var _last := NAN


func should_send(target: float) -> bool:
	if is_nan(_last) or absf(target - _last) > EPSILON:
		_last = target
		return true
	return false


func reset() -> void:
	_last = NAN

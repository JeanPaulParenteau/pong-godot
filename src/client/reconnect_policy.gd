## Decides whether/when to retry after an unexpected disconnect, with exponential
## backoff. Pure → unit-tested. The ConnectScreen drives the actual reconnect
## attempts from it.

const MAX_ATTEMPTS := 4
const BASE_DELAY_SECONDS := 1.0

var _attempts := 0


func attempt() -> int:
	return _attempts


func exhausted() -> bool:
	return _attempts >= MAX_ATTEMPTS


func reset() -> void:
	_attempts = 0


## Delay before the next attempt (seconds), or -1 when no attempts remain.
func next_delay() -> float:
	if _attempts >= MAX_ATTEMPTS:
		return -1.0
	var delay := BASE_DELAY_SECONDS * pow(2.0, _attempts)  # 1, 2, 4, 8...
	_attempts += 1
	return delay

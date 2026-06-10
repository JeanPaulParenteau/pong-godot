## Pure connection / reconnection state machine for the client. ConnectScreen
## pumps multiplayer signals and reconnect-timer ticks into it and renders
## state/status; the bug-prone "when do we auto-reconnect, when do we give up"
## logic lives here so it can be unit-tested without a network, a timer, or a
## frame loop. Backoff timing is delegated to ReconnectPolicy.

const ReconnectPolicy := preload("res://src/client/reconnect_policy.gd")

## The client's connection lifecycle phase.
enum State { IDLE, CONNECTING, CONNECTED, RECONNECTING, FAILED }

var state: int = State.IDLE
var status := ""

var _reconnect := ReconnectPolicy.new()


## User initiated a connect (Play Online / picked a LAN server).
func begin_connect(ip: String, port: String) -> void:
	state = State.CONNECTING
	status = "Connecting to %s:%s..." % [ip, port]


## The peer reports the client connected: reset the backoff and clear any reconnect.
func on_connected() -> void:
	state = State.CONNECTED
	status = "Connected."
	_reconnect.reset()


## The peer reports a disconnect. Returns true only when this is an unexpected drop
## of an established connection — the caller should start the reconnect loop. A drop
## during an initial connect, or a failed attempt while already reconnecting,
## returns false.
func on_disconnected(disconnect_reason := "") -> bool:
	match state:
		State.CONNECTED:
			state = State.RECONNECTING  # unexpected drop → auto-reconnect
			return true
		State.RECONNECTING:
			return false  # a failed attempt inside the loop; the loop drives the retries
		_:
			state = State.IDLE  # initial connect failed / wasn't connected
			status = "Disconnected." if disconnect_reason.is_empty() else disconnect_reason
			return false


## The next reconnect step: the delay (seconds) to wait before the next attempt, or
## -1 when attempts are exhausted — at which point state becomes FAILED and the
## caller stops looping.
func next_reconnect_delay() -> float:
	if _reconnect.exhausted():
		state = State.FAILED
		status = "Could not reconnect. Check the server and try again."
		return -1.0
	var delay := _reconnect.next_delay()
	status = "Connection lost — reconnecting (attempt %d/%d)..." % [
		_reconnect.attempt(), ReconnectPolicy.MAX_ATTEMPTS]
	return delay


## Cancel / leave / start solo → a clean idle with no auto-reconnect armed.
func reset() -> void:
	state = State.IDLE
	status = ""
	_reconnect.reset()

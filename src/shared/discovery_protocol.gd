## Tiny wire protocol for LAN server discovery (a UDP broadcast separate from the
## game transport). A client broadcasts a request; servers reply with their game
## port + name. Pure encode/parse so the format is unit-tested without sockets.
##
## Wire-identical to the Unity original ("PONGv1|..."), so a Godot client's LAN
## browser also lists Unity Pong servers (and vice versa) — though the game
## transports themselves are not cross-compatible.

const DISCOVERY_PORT := 47776
const MAGIC := "PONGv1"
const REQ := "DISCOVER"
const RESP := "SERVER"


static func request() -> PackedByteArray:
	return (MAGIC + "|" + REQ).to_ascii_buffer()


static func response(game_port: int, name: String) -> PackedByteArray:
	return (MAGIC + "|" + RESP + "|" + str(game_port) + "|" + _sanitize(name)).to_ascii_buffer()


static func is_request(data: PackedByteArray) -> bool:
	if data.is_empty():
		return false
	return data.get_string_from_ascii() == MAGIC + "|" + REQ


## Parses a response into {port: int, name: String}, or returns an empty
## Dictionary when the payload is not a valid response.
static func try_parse_response(data: PackedByteArray) -> Dictionary:
	if data.is_empty():
		return {}
	var parts := data.get_string_from_ascii().split("|")
	if parts.size() < 4 or parts[0] != MAGIC or parts[1] != RESP:
		return {}
	if not parts[2].is_valid_int():
		return {}
	var port := parts[2].to_int()
	if port <= 0 or port > 65535:
		return {}
	return {"port": port, "name": parts[3]}


static func _sanitize(name: String) -> String:
	return "Pong Server" if name.is_empty() else name.replace("|", "/")

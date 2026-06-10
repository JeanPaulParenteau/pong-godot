## The hello payload that identifies a Player (device-bound id + display name).
## Pure encode/decode shared by the client (which builds it) and the server
## (which reads it). Distinct from the spectator token (GameConfig.SPECTATOR_TOKEN),
## which carries no identity, and from an empty payload (an anonymous player).

# Unit separator: a C0 control char, so sanitize_name strips it from names — it can
# never appear inside a field, which keeps decoding to an exact 3-way split.
const SEP := "\u001f"
# Versioned tag so the server can tell a player payload from a spectator/empty/garbage
# one, and so a future field can bump to "P2" without ambiguity.
const TAG := "P1"

const MAX_NAME_LENGTH := 16
const DEFAULT_NAME := "Player"

var player_id := ""
var display_name := ""


func _init(p_player_id := "", p_display_name := "") -> void:
	player_id = p_player_id
	display_name = sanitize_name(p_display_name)


func encode() -> String:
	return TAG + SEP + player_id + SEP + display_name


## Decodes a player handshake (tagged, with a non-empty id), or returns null for
## spectator, empty, and malformed payloads so the caller can treat them as a
## spectator or an anonymous player. The name is re-sanitized — never trust the wire.
static func try_decode(payload: String):  # -> PlayerHandshake or null
	if payload.is_empty():
		return null
	var parts := payload.split(SEP)
	if parts.size() != 3 or parts[0] != TAG or parts[1].is_empty():
		return null
	return new(parts[1], parts[2])


## Trim, drop control chars (incl. the separator), clamp to MAX_NAME_LENGTH, and
## fall back to DEFAULT_NAME when empty. Pure and idempotent.
static func sanitize_name(raw: String) -> String:
	if raw.strip_edges().is_empty():
		return DEFAULT_NAME

	var cleaned := ""
	for c in raw:
		if c.unicode_at(0) >= 0x20 and c.unicode_at(0) != 0x7f:  # drop control chars
			cleaned += c

	cleaned = cleaned.strip_edges()
	if cleaned.is_empty():
		return DEFAULT_NAME
	return cleaned.substr(0, MAX_NAME_LENGTH) if cleaned.length() > MAX_NAME_LENGTH else cleaned

## The single match the local client is currently observing, or null when none (menu).
## Set by whichever source is active; the renderer and audio read it instead of
## reaching directly into the networking layer. Decoupling the view from the
## transport behind this seam is what lets one set of view code serve online play,
## offline solo, and Pong TV.
##
## A "match source" is any object exposing:
##   snapshot()    -> MatchSnapshot  — the current match read-model
##   local_side()  -> int            — which paddle the local player controls
##                                     (GameTypes.NO_SIDE = spectator/unassigned)
##   is_local()    -> bool           — true when the match runs on-device with zero
##                                     latency, so the renderer can skip the
##                                     interpolation buffer (it exists only to
##                                     smooth network jitter)

static var current = null


## Make source the active match (idempotent).
static func set_source(source) -> void:
	current = source


## Clear only if source is still the active one — avoids a stale source wiping
## out a newer one during teardown races.
static func clear(source) -> void:
	if current == source:
		current = null

## Captures the local pointer (touch on mobile, mouse on desktop) and exposes the
## desired paddle Y. The online node sends it to the server via RPC, throttled so
## the client doesn't flood the server; offline solo reads the same static helpers.
## No local paddle movement — the server (or local session) is authoritative.

const FieldView := preload("res://src/client/field_view.gd")

## The local player's latest clamped desired paddle Y — read by the renderer for
## client-side prediction. NAN until the player has provided input (GDScript has
## no nullable float).
static var local_target_y := NAN


static func has_local_target() -> bool:
	return not is_nan(local_target_y)


static func clear_local_target() -> void:
	local_target_y = NAN


## Pointer Y in screen pixels (top-left origin). Touch is emulated as mouse via
## project settings, so the mouse position covers both. On desktop the pointer
## drives the paddle whenever it is over the window (matching the Unity editor
## behaviour); on touch devices only while pressed. Returns NAN when no input.
static func try_get_pointer_y(viewport: Viewport) -> float:
	var pressed := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	if not pressed and not DisplayServer.has_feature(DisplayServer.FEATURE_MOUSE):
		return NAN
	return viewport.get_mouse_position().y

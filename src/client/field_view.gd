## Maps the origin-centred world field to a letterboxed rectangle on screen.
## Shared by the renderer (world → screen rect) and input (pointer → world Y) so
## what you touch lines up with what you see. World Y is up-positive; screen Y
## is down-positive, so the mapping flips Y.

const GameConfig := preload("res://src/shared/game_config.gd")

const SCREEN_FILL := 0.92

## Mirror the field on the X axis so the local player always sees themselves on
## the left (the "local-relative view"). Render-only: the vertical pointer→paddle
## mapping below is unaffected. Set per-frame by the renderer from the local side
## (true for the Right seat); false = the absolute layout (Left seat on the left).
static var flip_x := false

## The screen size the mapping is computed against. Updated each frame by the
## renderer (the one node that always exists while a match is shown).
static var screen_size := Vector2(1280, 720)


static func pixels_per_unit() -> float:
	var fit_w := screen_size.x * SCREEN_FILL / (2.0 * GameConfig.FIELD_HALF_WIDTH)
	var fit_h := screen_size.y * SCREEN_FILL / (2.0 * GameConfig.FIELD_HALF_HEIGHT)
	return minf(fit_w, fit_h)


## World point → screen coordinates (top-left origin, y down).
static func world_to_screen(world: Vector2) -> Vector2:
	var ppu := pixels_per_unit()
	var cx := screen_size.x * 0.5
	var cy := screen_size.y * 0.5
	var x := -world.x if flip_x else world.x  # local-relative mirror (X only)
	return Vector2(cx + x * ppu, cy - world.y * ppu)


## A screen rect (top-left origin) for a world-space box centred at world_center.
static func world_rect(world_center: Vector2, world_width: float, world_height: float) -> Rect2:
	var ppu := pixels_per_unit()
	var c := world_to_screen(world_center)
	var w := world_width * ppu
	var h := world_height * ppu
	return Rect2(c.x - w * 0.5, c.y - h * 0.5, w, h)


## Convert a pointer Y (screen coordinates: top-left origin, y down) to a world Y.
static func pointer_y_to_world(pointer_y: float) -> float:
	var cy := screen_size.y * 0.5
	return (cy - pointer_y) / pixels_per_unit()


## Pointer Y (screen pixels) → a legal paddle target: world-mapped then clamped
## to the paddle's range. The one place the client input → paddle-target rule
## lives, shared by the online (PaddleInput) and offline (LocalMatch) input paths.
static func pointer_to_paddle_target_y(pointer_y: float) -> float:
	return GameConfig.clamp_paddle_y(pointer_y_to_world(pointer_y))

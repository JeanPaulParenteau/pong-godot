## Pure inset math for keeping interactive controls and HUD text clear of Android
## display cutouts / system bars (the app runs immersive, drawing edge-to-edge).
## All decisions are functions of (safe_rect, window_size); the only DisplayServer/OS
## call lives in current_safe_rect(), made injectable for tests. Mirrors the
## FieldView seam (pure static math, environment injected). No-op off mobile.

# Test/diagnostic override for current_safe_rect(); null = use the real platform value.
static var _safe_rect_override = null


## The usable rect: the safe region clamped to the window, or the whole window when
## there is no inset (desktop + headless, where the safe rect is empty).
static func inset_rect(safe_rect: Rect2, window_size: Vector2) -> Rect2:
	if not safe_rect.has_area():
		return Rect2(Vector2.ZERO, window_size)
	return safe_rect.intersection(Rect2(Vector2.ZERO, window_size))


## Top-right corner-button anchor offsets, measured from the INSET edges so the
## button clears a right/top cutout. With an empty safe rect (desktop/headless) it
## reproduces the legacy offsets exactly, so non-mobile geometry is unchanged.
static func corner_top_right_offsets(safe_rect: Rect2, window_size: Vector2,
		button_w: float, button_h: float, top_pad: float, edge_pad: float) -> Dictionary:
	var right_inset := 0.0
	var top_inset := 0.0
	if safe_rect.has_area():
		right_inset = maxf(0.0, window_size.x - safe_rect.end.x)
		top_inset = maxf(0.0, safe_rect.position.y)
	var right := -(edge_pad + right_inset)
	var top := top_pad + top_inset
	return {"left": right - button_w, "right": right, "top": top, "bottom": top + button_h}


## HUD top baseline (score/rally), pushed below a top inset; unchanged otherwise.
static func hud_top_baseline(safe_rect: Rect2, _window_size: Vector2, default_y: float) -> float:
	if safe_rect.has_area():
		return maxf(default_y, safe_rect.position.y + default_y)
	return default_y


## The current platform safe rect: the injected override, else the real value on
## mobile, else empty (desktop/headless → no inset).
static func current_safe_rect() -> Rect2:
	if _safe_rect_override != null:
		return _safe_rect_override
	if OS.has_feature("mobile"):
		return DisplayServer.get_display_safe_area()
	return Rect2()

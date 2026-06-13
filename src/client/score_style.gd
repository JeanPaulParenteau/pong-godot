## Pure contrast/legibility primitive for HUD text. No nodes, no draw calls — the
## renderer stamps a dark outline under colored glyphs (offsets), and any HUD text
## (score, the result overlay, player names) can check it clears the WCAG AA floor
## against its background instead of re-deriving contrast per screen.

# Dark glyph outline (alpha keeps it a halo, not a hard box) and its thickness.
const OUTLINE := Color(0, 0, 0, 0.85)
const OUTLINE_PX := 2.0


## The 8 stamp offsets (axis + diagonal) for an outline of the given thickness.
## Symmetric, so they sum to Vector2.ZERO and the max component magnitude is px.
static func offsets(px: float) -> Array:
	return [
		Vector2(px, 0), Vector2(-px, 0), Vector2(0, px), Vector2(0, -px),
		Vector2(px, px), Vector2(px, -px), Vector2(-px, px), Vector2(-px, -px),
	]


## WCAG relative-contrast ratio between two colors (order-independent, 1..21).
## Uses Color.get_luminance() (the same luminance trusted by palette_test.gd).
static func wcag_contrast(a: Color, b: Color) -> float:
	var la := a.get_luminance()
	var lb := b.get_luminance()
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)


## True when fg on bg clears the contrast floor (WCAG AA for large text = 4.5).
static func meets_floor(fg: Color, bg: Color, floor := 4.5) -> bool:
	return wcag_contrast(fg, bg) >= floor

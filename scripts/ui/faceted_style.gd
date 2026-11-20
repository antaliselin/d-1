@tool
class_name FacetedStyle
extends RefCounted

const INK := Color("#f5e8c9")
const MUTED := Color("#bfccb9")
const AMBER := Color("#f4b96b")
const RED := Color("#d8927c")


static func slab(canvas: CanvasItem, rect: Rect2, color: Color, inset: Color, depth: float, cut: float) -> void:
	if rect.size.x <= 2 * depth or rect.size.y <= 2 * depth:
		return
	var outer := corners(rect, cut)
	var inner := corners(rect.grow(-depth), cut * 0.67)
	canvas.draw_colored_polygon(outer, color.darkened(0.21))
	for index in 8:
		var next := (index + 1) % 8
		var shades := [0.22, 0.33, 0.05, -0.22, -0.32, -0.39, -0.12, 0.11]
		var shade: float = shades[index]
		var tint := color.lightened(shade) if shade > 0.0 else color.darkened(-shade)
		canvas.draw_colored_polygon(PackedVector2Array([outer[index], outer[next], inner[next], inner[index]]), tint)
	canvas.draw_colored_polygon(inner, inset)


static func corners(rect: Rect2, cut: float) -> PackedVector2Array:
	var x := rect.position.x
	var y := rect.position.y
	var right := rect.end.x
	var bottom := rect.end.y
	var v := minf(cut, rect.size.y * 0.38)
	var h := minf(cut, rect.size.x * 0.29)
	return PackedVector2Array([
		Vector2(x, y + v), Vector2(x + h, y), Vector2(right - h, y), Vector2(right, y + v),
		Vector2(right, bottom - v), Vector2(right - h, bottom), Vector2(x + h, bottom), Vector2(x, bottom - v),
	])

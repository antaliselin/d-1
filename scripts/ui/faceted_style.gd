@tool
class_name FacetedStyle
extends RefCounted

const INK := Color("#f5e8c9")
const MUTED := Color("#bfccb9")
const AMBER := Color("#f4b96b")
const WOOD := Color("#a7683e")
const STEEL := Color("#6c8496")
const MOSS := Color("#424638")
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


static func board(canvas: CanvasItem, size: Vector2, wood: bool) -> void:
	var rect := Rect2(Vector2(2, 2), size - Vector2(5, 7))
	var edge := WOOD if wood else STEEL
	var middle := MOSS if wood else Color("#394951")
	slab(canvas, Rect2(rect.position + Vector2(2, 4), rect.size), Color("#253032"), Color("#182323"), 10, 24)
	slab(canvas, rect, edge, middle, 12, 25)
	var w := size.x
	var h := size.y
	var facets := [
		[Vector2(4, 55), Vector2(17, 18), Vector2(22, h * 0.33), Vector2(10, h * 0.44)],
		[Vector2(w - 14, 26), Vector2(w - 5, 44), Vector2(w - 8, h * 0.55), Vector2(w - 18, h * 0.34)],
		[Vector2(5, h * 0.65), Vector2(16, h * 0.6), Vector2(12, h - 32)],
		[Vector2(w - 7, h * 0.68), Vector2(w - 17, h - 21), Vector2(w - 7, h - 36)],
		[Vector2(30, h - 8), Vector2(w * 0.59, h - 14), Vector2(w * 0.39, h - 20)],
	]
	for index in facets.size():
		var tint := edge.lightened(0.12) if index % 2 == 0 else edge.darkened(0.28)
		canvas.draw_colored_polygon(PackedVector2Array(facets[index]), tint)
	for point in [Vector2(13, 45), Vector2(w - 13, 45), Vector2(13, h - 41), Vector2(w - 13, h - 41)]:
		var bolt := Rect2(point - Vector2(3, 4), Vector2(6, 8))
		canvas.draw_colored_polygon(corners(bolt, 2), edge.darkened(0.39))

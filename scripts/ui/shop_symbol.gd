@tool
class_name ShopSymbol
extends Control

@export_enum("visitor", "clock", "money", "reputation") var symbol: String = "visitor":
	set(value):
		symbol = value
		queue_redraw()
@export var tint := FacetedStyle.AMBER:
	set(value):
		tint = value
		queue_redraw()


func _draw() -> void:
	var origin := size * 0.5
	match symbol:
		"visitor":
			draw_arc(origin + Vector2(0, -5), 4.0, 0, TAU, 20, tint, 1.8, true)
			draw_polyline(PackedVector2Array([
				origin + Vector2(-10, 9), origin + Vector2(-8, 3), origin + Vector2(-4, 1),
				origin + Vector2(4, 1), origin + Vector2(8, 3), origin + Vector2(10, 9),
			]), tint, 1.8, true)
		"clock":
			draw_arc(origin, 9.5, 0, TAU, 30, tint, 1.8, true)
			draw_polyline(PackedVector2Array([
				origin + Vector2(0, -6), origin, origin + Vector2(5, 1),
			]), tint, 1.8, true)
		"money":
			FacetedStyle.slab(self, Rect2(origin - Vector2(12, 13), Vector2(24, 26)), Color("#b98a54"), FacetedStyle.AMBER, 3, 6)
			draw_polyline(PackedVector2Array([
				origin + Vector2(-4, -6), origin + Vector2(4, -6), origin + Vector2(4, 6),
				origin + Vector2(-4, 6),
			]), Color("#785435"), 2, true)
		"reputation":
			draw_colored_polygon(PackedVector2Array([
				origin + Vector2(-11, -11), origin + Vector2(11, -11),
				origin + Vector2(10, 4), origin + Vector2(0, 13), origin + Vector2(-10, 4),
			]), Color("#a4bfc1"))
			var points := PackedVector2Array()
			for index in 10:
				var length := 7.0 if index % 2 == 0 else 3.8
				points.append(origin + Vector2.UP.rotated(index * PI / 5.0) * length)
			draw_colored_polygon(points, Color("#3b5661"))

@tool
class_name ShopSymbol
extends Control

@export_enum("visitor", "clock", "money", "reputation", "notes", "radio", "crate", "empty",
		"rotate", "undo", "done", "medical", "warning", "book", "pin", "trade") var symbol: String = "visitor":
	set(value):
		symbol = value
		queue_redraw()


func _draw() -> void:
	var edge := minf(size.x, size.y)
	var area := Vector2.ONE * edge
	draw_texture_rect(ShopWidgets.ui_icon(symbol), Rect2((size - area) * 0.5, area), false)

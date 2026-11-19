@tool
class_name FacetedPanel
extends PanelContainer

@export_enum("steel", "wood", "bar", "modal", "plain") var finish: String = "steel":
	set(value):
		finish = value
		queue_redraw()


func _ready() -> void:
	resized.connect(queue_redraw)


func _draw() -> void:
	match finish:
		"wood", "steel":
			FacetedStyle.board(self, size, finish == "wood")
		"bar":
			FacetedStyle.slab(self, Rect2(Vector2.ZERO, size), Color("#788d90"), Color("#415254"), 10, 15)
		"modal":
			FacetedStyle.slab(self, Rect2(Vector2.ZERO, size), Color("#628092"), Color("#303f43"), 10, 20)

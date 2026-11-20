@tool
class_name FacetedPanel
extends PanelContainer

const SURFACE = preload("res://assets/ui/low_poly/material_grain.png")
const VARIATIONS := {
	"steel": &"ShopSteel",
	"wood": &"ShopCounter",
	"bar": &"ShopBar",
	"modal": &"ShopModal",
	"inset": &"ShopInset",
	"plain": &"",
}

@export_enum("steel", "wood", "bar", "modal", "plain", "inset") var finish: String = "steel":
	set(value):
		finish = value
		theme_type_variation = VARIATIONS[finish]
		queue_redraw()


func _ready() -> void:
	theme_type_variation = VARIATIONS[finish]
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	resized.connect(queue_redraw)


func _draw() -> void:
	if finish not in ["wood", "steel", "bar", "modal"] or size.x < 80.0 or size.y < 40.0:
		return
	var top := 9.0
	var bottom := size.y - 9.0
	draw_colored_polygon(PackedVector2Array([
		Vector2(16.0, top), Vector2(size.x * 0.69, top),
		Vector2(size.x * 0.42, size.y * 0.57), Vector2(9.0, size.y * 0.77), Vector2(9.0, 16.0),
	]), Color(0.68, 0.79, 0.84, 0.085))
	draw_colored_polygon(PackedVector2Array([
		Vector2(size.x - 9.0, size.y * 0.57), Vector2(size.x - 9.0, size.y - 16.0),
		Vector2(size.x - 16.0, bottom), Vector2(size.x * 0.33, bottom),
	]), Color(0.02, 0.04, 0.07, 0.22))
	draw_texture_rect(SURFACE, Rect2(Vector2(16, 11), size - Vector2(32, 22)), true, Color(1, 1, 1, 0.50))

@tool
class_name ShopDropSurface
extends FacetedPanel

var accepts: Callable
var dropped: Callable
var clicked: Callable


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return accepts.is_valid() and data is Dictionary and data.has("id") and accepts.call(data)


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	dropped.call(data)


func _gui_input(event: InputEvent) -> void:
	if clicked.is_valid() and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		clicked.call()
		accept_event()

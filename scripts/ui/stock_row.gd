@tool
class_name ShopStockRow
extends Button

signal item_pressed(id: String)

@export var editor_preview: Dictionary = {}:
	set(value):
		editor_preview = value
		if Engine.is_editor_hint() and is_node_ready():
			_show_editor_preview()

var item_id := ""
var quantity := 0
var can_interact := false

@onready var item_icon: TextureRect = %Icon
@onready var title: Label = %ItemName
@onready var price: Label = %Price
@onready var amount_label: Label = %Amount


func configure(item: Dictionary, amount: int, chosen: bool, needed: bool, interactive: bool) -> void:
	item_id = item.id
	quantity = amount
	can_interact = interactive and quantity > 0
	theme_type_variation = &"ShopStockSelected" if chosen and can_interact else (&"ShopStockRow" if can_interact else &"ShopStockReadOnly")
	item_icon.texture = ShopWidgets.icon(item_id)
	title.text = item.name
	price.text = str(int(item.value))
	%Needed.visible = needed
	amount_label.text = "%d发" % amount if item.has("rounds") else "×%d" % amount
	tooltip_text = "%s\n%s\n参考价 %d 瓶盖" % [item.name, item.desc, int(item.value)]
	modulate = Color.WHITE if amount > 0 else Color(0.69, 0.73, 0.73)
	focus_mode = Control.FOCUS_ALL if can_interact else Control.FOCUS_NONE
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if can_interact else Control.CURSOR_ARROW


func _ready() -> void:
	if Engine.is_editor_hint():
		_show_editor_preview()
		return
	pressed.connect(func() -> void:
		if can_interact:
			item_pressed.emit(item_id)
	)


func _show_editor_preview() -> void:
	if editor_preview.is_empty():
		return
	item_icon.texture = editor_preview.get("icon", item_icon.texture)
	title.text = editor_preview.get("name", title.text)
	price.text = editor_preview.get("price", price.text)
	amount_label.text = editor_preview.get("amount", amount_label.text)


func _get_drag_data(_at_position: Vector2) -> Variant:
	if not can_interact:
		return null
	set_drag_preview(ShopWidgets.drag_preview(item_id))
	return {"id": item_id, "piece": null, "rotation": 0, "grab": Vector2i.ZERO}

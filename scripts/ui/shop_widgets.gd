class_name ShopWidgets
extends RefCounted

const ACTION_BUTTON = preload("res://scenes/ui/action_button.tscn")
const DRAG_PREVIEW = preload("res://scenes/ui/drag_preview.tscn")

static var item_textures: Dictionary = {}
static var portraits: Dictionary = {}
static var half_portraits: Dictionary = {}


static func action(value: String, callback: Callable, variation: StringName, height: int, font_size: int) -> Button:
	var node: Button = ACTION_BUTTON.instantiate()
	node.text = value
	node.theme_type_variation = variation
	node.custom_minimum_size.y = height
	node.add_theme_font_size_override("font_size", font_size)
	node.pressed.connect(callback)
	return node


static func clear_entries(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()


static func icon(id: String) -> Texture2D:
	if not item_textures.has(id):
		item_textures[id] = load("res://assets/items/%s.png" % id)
	return item_textures[id]


static func portrait(key: String) -> Texture2D:
	if not portraits.has(key):
		portraits[key] = load("res://assets/portraits/%s.webp" % key)
	return portraits[key]


static func half_portrait(key: String) -> Texture2D:
	if not half_portraits.has(key):
		var full := portrait(key)
		var cropped := AtlasTexture.new()
		cropped.atlas = full
		cropped.region = Rect2(0, 0, full.get_width(), floorf(full.get_height() * 0.5))
		cropped.filter_clip = true
		half_portraits[key] = cropped
	return half_portraits[key]


static func drag_preview(id: String) -> TextureRect:
	var preview: TextureRect = DRAG_PREVIEW.instantiate()
	preview.texture = icon(id)
	return preview

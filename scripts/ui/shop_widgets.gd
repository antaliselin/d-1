@tool
class_name ShopWidgets
extends RefCounted

const ACTION_BUTTON = preload("res://scenes/ui/action_button.tscn")
const DRAG_PREVIEW = preload("res://scenes/ui/drag_preview.tscn")
const ITEM_ROW = preload("res://scenes/ui/settlement_line.tscn")
const UI_ATLAS = preload("res://assets/ui/low_poly/interface_icon_atlas.png")
const LOCATION_ATLAS = preload("res://assets/ui/low_poly/location_atlas.png")
const EVENT_PORTRAITS = preload("res://assets/ui/low_poly/event_portrait_atlas.png")
const UI_ICONS := ["money", "reputation", "visitor", "clock", "notes", "radio", "crate", "empty", "rotate", "undo", "done", "medical", "warning", "book", "pin", "trade"]
const LOCATIONS := ["site", "hospital", "market", "apartment", "gasstation", "police", "school", "pharmacy", "hardware", "station", "church", "warehouse", "subway", "relay", "water_tower", "crate"]
const EVENT_KEYS := ["event_child", "event_radio", "event_neighbor", "event_patient", "event_spy", "event_caravan", "event_dog", "event_mechanic", "event_lost"]
const CATEGORY_ITEMS := {
	"firearm": "pistol", "ammo": "ammo_pistol", "melee": "knife", "medical": "bandage",
	"food": "soda", "material": "plank", "tool": "toolbox", "luxury": "goldwatch",
}

static var item_textures: Dictionary = {}
static var location_textures: Dictionary = {}
static var ui_textures: Dictionary = {}
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


static func location_icon(id: String) -> Texture2D:
	if id == "umbrella":
		id = "warehouse"
	if not location_textures.has(id):
		location_textures[id] = _slice(LOCATION_ATLAS, LOCATIONS.find(id), 4, 192)
	return location_textures[id]


static func portrait(key: String) -> Texture2D:
	if not portraits.has(key):
		var index := EVENT_KEYS.find(key)
		portraits[key] = _slice(EVENT_PORTRAITS, index, 3, 256) if index >= 0 else load("res://assets/portraits/%s.webp" % key)
	return portraits[key]


static func half_portrait(key: String) -> Texture2D:
	if key.begins_with("art:"):
		return location_icon(key.trim_prefix("art:"))
	if key.begins_with("icon:"):
		return ui_icon(key.trim_prefix("icon:"))
	if key in EVENT_KEYS:
		return portrait(key)
	if not half_portraits.has(key):
		var full := portrait(key)
		var cropped := AtlasTexture.new()
		cropped.atlas = full
		cropped.region = Rect2(0, 0, full.get_width(), floorf(full.get_height() * 0.5))
		cropped.filter_clip = true
		half_portraits[key] = cropped
	return half_portraits[key]


static func ui_icon(key: String) -> Texture2D:
	if not ui_textures.has(key):
		ui_textures[key] = _slice(UI_ATLAS, UI_ICONS.find(key), 4, 64)
	return ui_textures[key]


static func button_icon(button: Button, texture: Texture2D, max_width: int) -> void:
	button.icon = texture
	button.expand_icon = true
	button.add_theme_constant_override("icon_max_width", max_width)


static func category_icon(category: String) -> Texture2D:
	return icon(CATEGORY_ITEMS[category])


static func item_row(id: String, description: String, value: String) -> PanelContainer:
	var row: PanelContainer = ITEM_ROW.instantiate()
	row.get_node("%ItemIcon").texture = icon(id)
	row.get_node("%Description").text = description
	row.get_node("%Total").text = value
	return row


static func _slice(atlas: Texture2D, index: int, columns: int, tile: int) -> AtlasTexture:
	assert(index >= 0, "Unhandled art key for %s" % atlas.resource_path)
	var texture := AtlasTexture.new()
	texture.atlas = atlas
	@warning_ignore("integer_division")
	texture.region = Rect2((index % columns) * tile, (index / columns) * tile, tile, tile)
	texture.filter_clip = true
	return texture


static func drag_preview(id: String) -> TextureRect:
	var preview: TextureRect = DRAG_PREVIEW.instantiate()
	preview.texture = icon(id)
	return preview

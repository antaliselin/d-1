class_name ShopCatalog
extends RefCounted

const ITEMS = preload("res://resources/content/items.json")
const PEOPLE = preload("res://resources/content/customers.json")
const LOCATIONS = preload("res://resources/content/locations.json")
const STORIES = preload("res://resources/content/stories.json")
const NOTES = preload("res://resources/content/notes.json")
const INTRO = preload("res://resources/content/intro.json")
const RULES = preload("res://resources/content/rules.json")

var items: Dictionary = {}
var locations: Dictionary = {}
var survivors: Dictionary = {}
var _shapes: Dictionary = {}
var opening: Array = PEOPLE.data.opening
var regular: Array = PEOPLE.data.regular
var categories: Dictionary = RULES.data.categories


func _init() -> void:
	for item: Dictionary in ITEMS.data:
		items[item.id] = item
		var rotations: Array[Array] = []
		for rotation in 4:
			rotations.append(_calculate_shape(item.cells, rotation))
		_shapes[item.id] = rotations
	for location: Dictionary in LOCATIONS.data:
		locations[location.id] = location
	for survivor: Dictionary in PEOPLE.data.survivors:
		survivors[survivor.id] = survivor


func shape(id: String, rotation: int) -> Array[Vector2i]:
	return _shapes[id][posmod(rotation, 4)]


func _calculate_shape(cells: Array, rotation: int) -> Array[Vector2i]:
	var points: Array[Vector2i] = []
	var minimum := Vector2i(100, 100)
	for cell: Dictionary in cells:
		var point := Vector2i(int(cell.x), int(cell.y))
		for step in rotation:
			point = Vector2i(-point.y, point.x)
		minimum = minimum.min(point)
		points.append(point)
	for index in points.size():
		points[index] -= minimum
	points.make_read_only()
	return points


func units_per_piece(id: String) -> int:
	return int(items[id].get("rounds", 1))


func unit_price(id: String) -> float:
	return float(items[id].value) / units_per_piece(id)


func amount_text(id: String, amount: int) -> String:
	return "%d 发" % amount if items[id].has("rounds") else "×%d" % amount

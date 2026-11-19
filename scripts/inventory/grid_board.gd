class_name ShopGrid
extends RefCounted

const INVALID := Vector2i(-1, -1)

var size: Vector2i
var blocked: Dictionary = {}
var pieces: Array[ShopPiece] = []
var catalog: ShopCatalog
var _occupied: Dictionary = {}


func _init(data: ShopCatalog, definition: Dictionary) -> void:
	catalog = data
	size = Vector2i(int(definition.cols), int(definition.rows))
	for key: String in definition.blocked:
		var coordinates := key.split(",")
		blocked[Vector2i(int(coordinates[0]), int(coordinates[1]))] = true


func piece_at(cell: Vector2i) -> ShopPiece:
	return _occupied.get(cell)


func can_fit(id: String, anchor: Vector2i, rotation: int, ignore: ShopPiece = null) -> bool:
	for offset in catalog.shape(id, rotation):
		var cell := anchor + offset
		if not Rect2i(Vector2i.ZERO, size).has_point(cell) or blocked.has(cell):
			return false
		var occupied := piece_at(cell)
		if occupied != null and occupied != ignore:
			return false
	return true


func nearest_anchor(id: String, desired: Vector2i, rotation: int, ignore: ShopPiece = null) -> Vector2i:
	var extent := Vector2i.ONE
	for offset in catalog.shape(id, rotation):
		extent = extent.max(offset + Vector2i.ONE)
	if extent.x > size.x or extent.y > size.y:
		return INVALID
	desired = desired.clamp(Vector2i.ZERO, size - extent)
	var best := INVALID
	var distance := 5
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			var score := dx * dx + dy * dy
			var candidate := desired + Vector2i(dx, dy)
			if score < distance and can_fit(id, candidate, rotation, ignore):
				best = candidate
				distance = score
	return best


func place(piece: ShopPiece, anchor: Vector2i, rotation: int) -> bool:
	if not can_fit(piece.id, anchor, rotation, piece):
		return false
	if piece in pieces:
		_clear_cells(piece)
	else:
		pieces.append(piece)
	piece.anchor = anchor
	piece.rotation = posmod(rotation, 4)
	for offset in catalog.shape(piece.id, piece.rotation):
		_occupied[anchor + offset] = piece
	return true


func remove(piece: ShopPiece) -> void:
	if piece in pieces:
		_clear_cells(piece)
		pieces.erase(piece)


func _clear_cells(piece: ShopPiece) -> void:
	for offset in catalog.shape(piece.id, piece.rotation):
		_occupied.erase(piece.anchor + offset)

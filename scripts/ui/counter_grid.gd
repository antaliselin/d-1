@tool
class_name CounterGrid
extends Control

signal cell_pressed(cell: Vector2i)
signal piece_dropped(data: Dictionary, cell: Vector2i)
signal piece_returned(piece: ShopPiece)

var trade: TradeSession
var selected: Dictionary = {}
var pointer := ShopGrid.INVALID
var dragging: Dictionary = {}


func _ready() -> void:
	resized.connect(queue_redraw)
	mouse_exited.connect(_clear_preview)


func _draw() -> void:
	if trade == null or trade.grid == null:
		if Engine.is_editor_hint():
			var sample_size := Vector2i(6, 6)
			_draw_cells(_rect_for(sample_size), sample_size, {Vector2i(5, 5): true})
		return
	var grid := trade.grid
	var rect := board_rect()
	var cell_size := rect.size.x / grid.size.x
	_draw_cells(rect, grid.size, grid.blocked)
	for piece in grid.pieces:
		_draw_piece(piece, rect, cell_size)
	var data := dragging if not dragging.is_empty() else selected
	var preview_cell: Vector2i = pointer if pointer != ShopGrid.INVALID else data.get("pending_cell", ShopGrid.INVALID)
	if preview_cell != ShopGrid.INVALID and not data.is_empty() and trade.can_handle():
		_draw_ghost(data, preview_cell, rect.position, cell_size)


func _draw_cells(rect: Rect2, dimensions: Vector2i, blocked: Dictionary) -> void:
	if rect.size.x <= 0.0:
		return
	var cell_size := rect.size.x / dimensions.x
	FacetedStyle.slab(self, rect.grow(8), Color("#a27049"), Color("#333a32"), 7, 14)
	for y in dimensions.y:
		for x in dimensions.x:
			var point := Vector2i(x, y)
			var tile := Rect2(rect.position + Vector2(point) * cell_size, Vector2.ONE * cell_size).grow(-1.3)
			if blocked.has(point):
				draw_rect(tile, Color("#292d28"))
				draw_line(tile.position + Vector2.ONE * 4, tile.end - Vector2.ONE * 4, Color("#815b43"), 2, true)
				draw_line(Vector2(tile.end.x - 4, tile.position.y + 4), Vector2(tile.position.x + 4, tile.end.y - 4), Color("#815b43"), 2, true)
			else:
				FacetedStyle.slab(self, tile, Color("#5e6050"), Color("#434a3d"), 2, 3)


func board_rect() -> Rect2:
	if trade == null or trade.grid == null:
		return Rect2()
	return _rect_for(trade.grid.size)


func _rect_for(grid_size: Vector2i) -> Rect2:
	var dimensions := Vector2(grid_size)
	var length := minf((size.x - 18) / dimensions.x, (size.y - 18) / dimensions.y)
	var extent := dimensions * length
	return Rect2((size - extent) * 0.5, extent)


func cell_at(position: Vector2) -> Vector2i:
	var rect := board_rect()
	if not rect.has_point(position):
		return ShopGrid.INVALID
	return Vector2i(((position - rect.position) / rect.size * Vector2(trade.grid.size)).floor())


func _draw_piece(piece: ShopPiece, rect: Rect2, length: float) -> void:
	var points := trade.catalog.shape(piece.id, piece.rotation)
	var bounds := Vector2i.ONE
	var color := Color("#738b9c") if piece.customer_owned else Color("#849572")
	if selected.get("piece") == piece:
		color = FacetedStyle.AMBER
	for offset in points:
		var tile := Rect2(rect.position + Vector2(piece.anchor + offset) * length, Vector2.ONE * length).grow(-1.1)
		FacetedStyle.slab(self, tile, color, color.darkened(0.38), 2.0, 2.2)
		bounds = bounds.max(offset + Vector2i.ONE)
	var top_left := rect.position + Vector2(piece.anchor) * length
	var extent := Vector2(bounds) * length
	var icon := ShopWidgets.icon(piece.id)
	var center := top_left + extent * 0.5
	var first := points[0]
	if Vector2i(bounds / 2) not in points:
		center = top_left + (Vector2(first) + Vector2.ONE * 0.5) * length
		extent = Vector2.ONE * length
	# Fit in the texture's local axes before rotating it onto the board.
	var local_extent := Vector2(extent.y, extent.x) if piece.rotation % 2 != 0 else extent
	var texture_size := icon.get_size()
	var icon_size := texture_size * minf(local_extent.x / texture_size.x, local_extent.y / texture_size.y) * 0.92
	var number := ""
	if trade.catalog.items[piece.id].has("rounds"):
		number = str(piece.units)
	elif trade.catalog.items[piece.id].has("magazine"):
		number = str(piece.loaded)
	elif piece.customer_owned:
		number = "客"
	draw_set_transform(center, piece.rotation * PI * 0.5)
	draw_texture_rect(icon, Rect2(-icon_size * 0.5, icon_size), false)
	draw_set_transform(Vector2.ZERO)
	if number != "":
		var last := points[points.size() - 1]
		var badge := rect.position + Vector2(piece.anchor + last) * length + Vector2(4, length - 5)
		draw_string(get_theme_default_font(), badge, number, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, FacetedStyle.INK)


func _draw_ghost(data: Dictionary, cell: Vector2i, origin: Vector2, length: float) -> void:
	var target := trade.grid.piece_at(cell)
	if trade.interact(data.id, data.get("piece"), target) != "":
		for offset in trade.catalog.shape(target.id, target.rotation):
			var tile := Rect2(origin + Vector2(target.anchor + offset) * length, Vector2.ONE * length).grow(-2)
			draw_rect(tile, FacetedStyle.AMBER, false, 2)
		return
	var desired: Vector2i = cell - data.get("grab", Vector2i.ZERO)
	var anchor := trade.snap(data.id, data.get("piece"), desired, int(data.rotation))
	var valid := anchor != ShopGrid.INVALID
	var color := Color(0.76, 0.87, 0.55, 0.56) if valid else Color(0.94, 0.42, 0.30, 0.55)
	for offset in trade.catalog.shape(data.id, int(data.rotation)):
		var ghost_cell := (anchor if valid else desired) + offset
		if Rect2i(Vector2i.ZERO, trade.grid.size).has_point(ghost_cell):
			draw_rect(Rect2(origin + Vector2(ghost_cell) * length, Vector2.ONE * length).grow(-2), color)


func _gui_input(event: InputEvent) -> void:
	if trade == null or not trade.can_handle():
		return
	if event is InputEventMouseMotion:
		pointer = cell_at(event.position)
		queue_redraw()
	if event is InputEventMouseButton:
		var cell := cell_at(event.position)
		if cell == ShopGrid.INVALID:
			return
		if event.button_index == MOUSE_BUTTON_LEFT and not event.pressed and not get_viewport().gui_is_dragging():
			cell_pressed.emit(cell)
			accept_event()
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			var piece := trade.grid.piece_at(cell)
			if piece != null:
				piece_returned.emit(piece)
				accept_event()


func _get_drag_data(at_position: Vector2) -> Variant:
	if trade == null or not trade.can_handle():
		return null
	var cell := cell_at(at_position)
	var piece := trade.grid.piece_at(cell)
	if piece == null:
		return null
	set_drag_preview(ShopWidgets.drag_preview(piece.id))
	return {"id": piece.id, "piece": piece, "rotation": piece.rotation, "grab": cell - piece.anchor}


func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	var cell := cell_at(at_position)
	if cell == ShopGrid.INVALID or not data is Dictionary or not data.has("id") or not trade.can_handle():
		return false
	pointer = cell
	dragging = data
	queue_redraw()
	return true


func _drop_data(at_position: Vector2, data: Variant) -> void:
	piece_dropped.emit(data, cell_at(at_position))
	_clear_preview()


func _get_tooltip(at_position: Vector2) -> String:
	if trade == null or trade.grid == null:
		return ""
	var piece := trade.grid.piece_at(cell_at(at_position))
	if piece == null:
		return ""
	return trade.catalog.items[piece.id].name + (" · 客人自带" if piece.customer_owned else " · 右键收回")


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		_clear_preview()


func _clear_preview() -> void:
	pointer = ShopGrid.INVALID
	dragging = {}
	queue_redraw()

class_name TradeSession
extends RefCounted

var customer: Dictionary
var stock: Stockroom
var catalog: ShopCatalog
var grid: ShopGrid
var healed := 0
var turn_index := 0
var finished := false
var sold: Dictionary = {}


func _init(person: Dictionary, inventory: Stockroom) -> void:
	customer = person.duplicate(true)
	stock = inventory
	catalog = stock.catalog
	if not customer.get("containerHidden", false):
		reveal_grid()


func turn() -> Dictionary:
	var turns: Array = customer.get("dialogue", {}).get("turns", [])
	return turns[turn_index] if turn_index < turns.size() else {}


func advance_dialogue() -> void:
	turn_index += 1
	if turn().get("revealContainer", false):
		reveal_grid()


func dialogue_blocked() -> bool:
	return not turn().get("options", []).is_empty()


func reveal_grid() -> void:
	if grid != null or not customer.has("container"):
		return
	grid = ShopGrid.new(catalog, customer.container)
	for entry: Dictionary in customer.get("startItems", []):
		var piece := ShopPiece.new(entry.itemId, catalog.units_per_piece(entry.itemId), true)
		grid.place(piece, Vector2i(int(entry.x), int(entry.y)), int(entry.get("rot", 0)))


func can_handle() -> bool:
	return not finished and not dialogue_blocked()


func snap(id: String, piece: ShopPiece, cell: Vector2i, rotation: int) -> Vector2i:
	if not can_handle() or grid == null or not source_exists(id, piece):
		return ShopGrid.INVALID
	return grid.nearest_anchor(id, cell, rotation, piece)


func source_exists(id: String, piece: ShopPiece) -> bool:
	if piece != null:
		return grid != null and piece in grid.pieces and piece.id == id
	return stock.count(id) > 0


func interact(id: String, source: ShopPiece, target: ShopPiece) -> String:
	if not can_handle() or target == null or source == target or not source_exists(id, source):
		return ""
	if source != null and source.customer_owned:
		return ""
	var supply: Dictionary = catalog.items[id]
	var recipient: Dictionary = catalog.items[target.id]
	if supply.has("rounds") and recipient.has("magazine") and supply.caliber == recipient.caliber:
		if target.loaded < int(recipient.magazine):
			return "reload"
	if not target.customer_owned and ((id == "herb_red" and target.id == "herb_green") or (id == "herb_green" and target.id == "herb_red")):
		return "mix"
	return ""


func place(id: String, source: ShopPiece, cell: Vector2i, rotation: int, grab: Vector2i = Vector2i.ZERO) -> Dictionary:
	if not can_handle() or grid == null or not source_exists(id, source):
		return {"ok": false, "message": "现在无法移动这件物品"}
	var target := grid.piece_at(cell)
	match interact(id, source, target):
		"reload":
			return {"ok": true, "message": _reload(id, source, target)}
		"mix":
			var mixed := _mix(id, source, target)
			return {"ok": mixed, "message": "合成了混合草药" if mixed else "这里没有足够空间合成"}
	var anchor := snap(id, source, cell - grab, rotation)
	if anchor == ShopGrid.INVALID:
		return {"ok": false, "message": "这里放不下，旋转后再试"}
	var piece := source if source != null else stock.take_piece(id)
	grid.place(piece, anchor, rotation)
	return {"ok": true, "message": "%s已放入箱内" % catalog.items[id].name}


func rotate_piece(piece: ShopPiece, rotation: int) -> bool:
	if not can_handle() or not source_exists(piece.id, piece):
		return false
	var anchor := snap(piece.id, piece, piece.anchor, rotation)
	return anchor != ShopGrid.INVALID and grid.place(piece, anchor, rotation)


func take_back(piece: ShopPiece) -> bool:
	if not can_handle() or piece == null or piece.customer_owned or not source_exists(piece.id, piece):
		return false
	grid.remove(piece)
	stock.refund(piece)
	return true


func return_all() -> void:
	if grid == null:
		return
	for piece in grid.pieces.duplicate():
		take_back(piece)


func heal_amount(id: String, source: ShopPiece) -> int:
	if not can_handle() or not source_exists(id, source) or (source != null and source.customer_owned):
		return 0
	var rule: Dictionary = ShopCatalog.RULES.data.medical.get(id, {})
	var missing := 100 - int(customer.hp)
	match rule.get("kind", ""):
		"full":
			return missing
		"amount":
			return mini(missing, int(rule.amount))
	return 0


func heal_with(id: String, source: ShopPiece) -> String:
	var amount := heal_amount(id, source)
	if amount == 0:
		return "这件物品无法治疗当前客人"
	_consume(id, source, 1)
	customer.hp += amount
	healed += amount
	return "%s恢复了 %d 点生命" % [customer.name, amount]


func quote() -> Dictionary:
	if not sold.is_empty():
		return sold
	return ShopSettlement.quote(catalog, customer, grid, healed) if grid != null else {}


func complete() -> bool:
	if not can_handle() or grid == null:
		return false
	var offer := quote()
	if not offer.can_sell:
		return false
	sold = offer
	finished = true
	return true


func _consume(id: String, source: ShopPiece, amount: int) -> void:
	if source == null:
		stock.take(id, amount)
		return
	source.units -= amount
	if source.units == 0:
		grid.remove(source)


func _reload(id: String, source: ShopPiece, target: ShopPiece) -> String:
	var available := source.units if source != null else mini(stock.count(id), catalog.units_per_piece(id))
	var amount := mini(available, int(catalog.items[target.id].magazine) - target.loaded)
	_consume(id, source, amount)
	target.loaded += amount
	target.ammo_id = id
	return "已装弹 %d 发" % amount


func _mix(id: String, source: ShopPiece, target: ShopPiece) -> bool:
	var anchor := target.anchor
	var rotation := target.rotation
	if not grid.can_fit("herb_mixed", anchor, rotation, target):
		return false
	_consume(id, source, 1)
	grid.remove(target)
	grid.place(ShopPiece.new("herb_mixed"), anchor, rotation)
	return true

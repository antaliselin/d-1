class_name Stockroom
extends RefCounted

var catalog: ShopCatalog
var warehouse: Dictionary = {}


func _init(data: ShopCatalog) -> void:
	catalog = data
	for id: String in catalog.items:
		warehouse[id] = int(catalog.items[id].stock)


func count(id: String) -> int:
	return warehouse.get(id, 0)


func add(id: String, units: int) -> void:
	if warehouse.has(id) and units > 0:
		warehouse[id] += units


func take(id: String, units: int) -> bool:
	if units <= 0 or count(id) < units:
		return false
	warehouse[id] -= units
	return true


func take_piece(id: String) -> ShopPiece:
	if not catalog.items.has(id):
		return null
	var amount := mini(count(id), catalog.units_per_piece(id))
	return ShopPiece.new(id, amount) if take(id, amount) else null


func refund(piece: ShopPiece) -> void:
	if piece.customer_owned:
		return
	add(piece.id, piece.units)
	if piece.loaded > 0:
		add(piece.ammo_id, piece.loaded)


func category_total(category: String) -> int:
	var total := 0
	for id: String in catalog.items:
		if _in_category(id, category):
			total += count(id)
	return total


func has_requirements(requirements: Dictionary) -> bool:
	for category: String in requirements:
		if category_total(category) < int(requirements[category]):
			return false
	return true


func use_requirements(requirements: Dictionary) -> bool:
	if not has_requirements(requirements):
		return false
	for category: String in requirements:
		var remaining := int(requirements[category])
		for id: String in catalog.items:
			if remaining <= 0:
				break
			if _in_category(id, category):
				var units := mini(remaining, count(id))
				take(id, units)
				remaining -= units
	return true


func seize(target: int) -> Array[String]:
	var ids := catalog.items.keys()
	ids.sort_custom(func(a: String, b: String) -> bool: return catalog.unit_price(a) > catalog.unit_price(b))
	var losses: Array[String] = []
	var collected := 0.0
	for id: String in ids:
		if collected >= target:
			break
		var price := catalog.unit_price(id)
		var units := mini(count(id), ceili((target - collected) / price))
		if take(id, units):
			collected += units * price
			losses.append("%s %s" % [catalog.items[id].name, catalog.amount_text(id, units)])
	losses.push_front("搬走物资价值 %d" % roundi(collected))
	return losses


func _in_category(id: String, category: String) -> bool:
	var item: Dictionary = catalog.items[id]
	return item.category == category and (category != "ammo" or item.has("rounds"))

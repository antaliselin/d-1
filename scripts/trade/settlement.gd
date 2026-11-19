class_name ShopSettlement
extends RefCounted


static func quote(catalog: ShopCatalog, customer: Dictionary, grid: ShopGrid, healed: int) -> Dictionary:
	var pieces := grid.pieces.duplicate()
	pieces.sort_custom(func(a: ShopPiece, b: ShopPiece) -> bool:
		return a.anchor.y < b.anchor.y or (a.anchor.y == b.anchor.y and a.anchor.x < b.anchor.x)
	)
	var calibers: Dictionary = {}
	var player_cells := 0
	var customer_cells := 0
	for piece: ShopPiece in pieces:
		var definition: Dictionary = catalog.items[piece.id]
		if definition.category == "firearm":
			calibers[definition.caliber] = true
		if piece.customer_owned:
			customer_cells += definition.cells.size()
		else:
			player_cells += definition.cells.size()

	var left := int(customer.budget)
	var lines: Array[Dictionary] = []
	var relevant := false
	for piece: ShopPiece in pieces:
		if piece.customer_owned and piece.loaded == 0:
			continue
		var id := piece.ammo_id if piece.customer_owned else piece.id
		var definition: Dictionary = catalog.items[id]
		var amount := piece.loaded if piece.customer_owned else piece.units
		var value := roundi(catalog.unit_price(id) * amount)
		if not piece.customer_owned and piece.loaded > 0:
			value += roundi(catalog.unit_price(piece.ammo_id) * piece.loaded)
		var needed := matches(customer, id, definition.category)
		relevant = relevant or needed
		var nominal := value if needed else roundi(value * 0.5)
		var nominal_bonus := roundi(nominal * 0.1) if definition.has("rounds") and calibers.has(definition.caliber) else 0
		var price := mini(nominal, left)
		left -= price
		var bonus := mini(nominal_bonus, left)
		left -= bonus
		lines.append({
			"name": definition.name, "amount": amount, "id": id, "base": price,
			"bonus": bonus, "wanted": needed, "nominal": nominal + nominal_bonus,
		})

	var trade_value := int(customer.budget) - left
	var healing := healed + (50 if healed > 0 and int(customer.hp) == 100 else 0)
	var capacity := grid.size.x * grid.size.y - grid.blocked.size() - customer_cells
	var filled := capacity > 0 and float(player_cells) / capacity >= 0.85
	var reputation := 1 + int(filled) - (2 if not relevant and not lines.is_empty() else 0)
	return {
		"lines": lines, "base": trade_value, "budget": int(customer.budget), "healing": healing,
		"total": trade_value + healing, "reputation": reputation, "used": player_cells,
		"usable": capacity, "can_sell": not lines.is_empty() or healing > 0,
		"capped": lines.any(func(line: Dictionary) -> bool: return line.base + line.bonus < line.nominal),
	}


static func matches(customer: Dictionary, id: String, category: String) -> bool:
	for want: Dictionary in customer.wants:
		if want.get("itemId") == id:
			return true
	for demand: Dictionary in customer.demand:
		if float(demand.weight) > 0.25 and category in demand.categories:
			return true
	return false

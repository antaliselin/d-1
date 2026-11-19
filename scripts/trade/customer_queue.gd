class_name CustomerQueue
extends RefCounted

const TIERS := [
	{"sizes": [Vector2i(6, 6), Vector2i(6, 7), Vector2i(7, 6)], "holes": Vector2i(0, 0), "budget": Vector2i(320, 480)},
	{"sizes": [Vector2i(7, 7), Vector2i(8, 7), Vector2i(7, 8)], "holes": Vector2i(0, 1), "budget": Vector2i(420, 700)},
	{"sizes": [Vector2i(8, 8), Vector2i(9, 8), Vector2i(8, 9)], "holes": Vector2i(0, 2), "budget": Vector2i(560, 820)},
	{"sizes": [Vector2i(10, 10)], "holes": Vector2i(1, 3), "budget": Vector2i(680, 980)},
]
const CARRY_WEIGHT := {"food": 1.0, "material": 1.0, "medical": 1.0, "ammo": 1.0, "tool": 0.8, "melee": 0.6, "luxury": 0.4, "firearm": 0.25}
const ASIDES := ["外面越来越难走了，什么都缺。", "箱子里已经装了点东西，别嫌挤。", "钱不是问题，东西得对路。"]


static func for_day(catalog: ShopCatalog, day: int, reputation: int, seed_value: int) -> Array:
	if day == 1:
		return catalog.opening.duplicate(true)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + day * 19739
	var roster := catalog.regular.duplicate()
	var count := clampi(roundi(2.0 + reputation * 0.04), 2, 6)
	var result: Array[Dictionary] = []
	for index in count:
		var profile: Dictionary = roster.pop_at(rng.randi_range(0, roster.size() - 1))
		result.append(_make_visitor(catalog, profile, rng, index))
	return result


static func _make_visitor(catalog: ShopCatalog, profile: Dictionary, rng: RandomNumberGenerator, order: int) -> Dictionary:
	var person := profile.duplicate(true)
	var tier: Dictionary = TIERS[mini(order, TIERS.size() - 1)]
	var dimensions: Vector2i = tier.sizes[rng.randi_range(0, tier.sizes.size() - 1)]
	var holes: Array[String] = []
	var hole_count := rng.randi_range(tier.holes.x, tier.holes.y)
	while holes.size() < hole_count:
		var key := "%d,%d" % [rng.randi_range(0, dimensions.x - 1), rng.randi_range(0, dimensions.y - 1)]
		if key not in holes:
			holes.append(key)
	person.container = {"cols": dimensions.x, "rows": dimensions.y, "blocked": holes}
	person.budget = roundi(rng.randi_range(tier.budget.x, tier.budget.y) / 10.0) * 10
	person.hp = rng.randi_range(28, 100)

	var board := ShopGrid.new(catalog, person.container)
	person.startItems = _fill_belongings(catalog, board, rng, order > 0 and rng.randf() < 0.45)
	var categories := catalog.categories.keys()
	var main: String = categories.pop_at(rng.randi_range(0, categories.size() - 1))
	var extra: String = categories[rng.randi_range(0, categories.size() - 1)]
	person.demand = [{"categories": [main], "weight": 1.0}, {"categories": [extra], "weight": 0.6}]
	person.wants = _specific_wants(catalog, board, rng, main, extra)
	person.request = "给我找点%s，%s也捎上一些。" % [catalog.categories[main], catalog.categories[extra]]
	person.aside = ASIDES[rng.randi_range(0, ASIDES.size() - 1)] if person.wants.is_empty() else "单子上那几样，有的话优先给我。"
	return person


static func _fill_belongings(catalog: ShopCatalog, board: ShopGrid, rng: RandomNumberGenerator, carry_firearm: bool) -> Array[Dictionary]:
	var ids: Array[String] = []
	var firearms: Array[String] = []
	var weights := PackedFloat32Array()
	for id: String in catalog.items:
		var item: Dictionary = catalog.items[id]
		if not item.get("forSale", true):
			continue
		ids.append(id)
		weights.append(float(CARRY_WEIGHT[item.category]) / item.cells.size())
		if item.category == "firearm":
			firearms.append(id)
	var usable := board.size.x * board.size.y - board.blocked.size()
	var target := roundi(usable * rng.randf_range(0.2, 0.5))
	var limit := floori(usable * 0.6)
	var occupied := 0
	var counts: Dictionary = {}
	for attempt in 200:
		if occupied >= target:
			break
		var id := firearms[rng.randi_range(0, firearms.size() - 1)] if carry_firearm and attempt < 40 else ids[rng.rand_weighted(weights)]
		var definition: Dictionary = catalog.items[id]
		var area: int = definition.cells.size()
		if int(counts.get(id, 0)) >= 3 or occupied + area > limit:
			continue
		var rotation := rng.randi_range(0, 3)
		var anchor := Vector2i(rng.randi_range(0, board.size.x - 1), rng.randi_range(0, board.size.y - 1))
		if board.place(ShopPiece.new(id, catalog.units_per_piece(id), true), anchor, rotation):
			occupied += area
			counts[id] = int(counts.get(id, 0)) + 1
			carry_firearm = false

	var goods: Array[Dictionary] = []
	for piece in board.pieces:
		goods.append({"itemId": piece.id, "x": piece.anchor.x, "y": piece.anchor.y, "rot": piece.rotation})
	return goods


static func _specific_wants(catalog: ShopCatalog, board: ShopGrid, rng: RandomNumberGenerator, main: String, extra: String) -> Array[Dictionary]:
	var wants: Array[Dictionary] = []
	var free := board.size.x * board.size.y - board.blocked.size()
	for piece in board.pieces:
		free -= catalog.shape(piece.id, 0).size()
	var request_space := free / 2
	var named_item := false
	for category: String in [main, extra]:
		var roll := rng.randf()
		if roll < 0.5 or request_space < 2:
			continue
		var candidates: Array[String] = []
		for id: String in catalog.items:
			var item: Dictionary = catalog.items[id]
			if item.category == category and item.get("forSale", true) and item.cells.size() <= request_space and _can_pack(board, id):
				candidates.append(id)
		if candidates.is_empty():
			continue
		var id := candidates[rng.randi_range(0, candidates.size() - 1)]
		var area := catalog.shape(id, 0).size()
		if roll >= 0.8 and not named_item:
			wants.append({"itemId": id, "label": catalog.items[id].name})
			request_space -= area
			named_item = true
		else:
			var amount := mini(rng.randi_range(2, 4), request_space / area)
			wants.append({"category": category, "atLeast": amount, "label": "%d 件%s" % [amount, catalog.categories[category]]})
			request_space -= area * amount
	return wants


static func _can_pack(board: ShopGrid, id: String) -> bool:
	for rotation in 4:
		for row in board.size.y:
			for column in board.size.x:
				if board.can_fit(id, Vector2i(column, row), rotation):
					return true
	return false

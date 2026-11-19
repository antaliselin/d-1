class_name ShopExpeditions
extends RefCounted

const PARTNER := {"id": "partner-eddie", "name": "埃迪", "portrait": "courier", "trait": "合伙人，熟悉附近的街巷"}
const GEAR_TYPES := ["firearm", "ammo", "melee", "medical"]

var roster: Dictionary = {PARTNER.id: PARTNER}
var active: Dictionary = {}
var catalog: ShopCatalog
var seed_value: int


func _init(data: ShopCatalog, world_seed: int) -> void:
	catalog = data
	seed_value = world_seed


func hire() -> String:
	for id: String in catalog.survivors:
		if not roster.has(id):
			roster[id] = catalog.survivors[id]
			return roster[id].name
	return ""


func lose_home_survivor() -> String:
	for id: String in roster:
		if id != PARTNER.id and not active.has(id):
			var survivor_name: String = roster[id].name
			roster.erase(id)
			return survivor_name
	return ""


func destinations(day: int) -> Array:
	var rng := _rng(day, 11)
	var ids := catalog.locations.keys()
	var result: Array = []
	for index in rng.randi_range(4, 6):
		result.append(ids.pop_at(rng.randi_range(0, ids.size() - 1)))
	return result


func scavenge(id: String, day: int, money: int) -> Dictionary:
	var rng := _rng(day, 71 + catalog.locations.keys().find(id))
	var location: Dictionary = catalog.locations[id]
	var found: Dictionary = {}
	var count := 0
	for entry: Dictionary in location.loot:
		if rng.randf() <= float(entry.chance):
			var pieces := rng.randi_range(int(entry.min), int(entry.max))
			found[entry.itemId] = pieces
			count += pieces
	if found.is_empty():
		found[location.loot[0].itemId] = 1
		count = 1
	var target := rng.randi_range(15, 40)
	var keys := found.keys()
	while count < target:
		found[keys[rng.randi_range(0, keys.size() - 1)]] += 1
		count += 1
	for item: String in keys:
		if count <= target:
			break
		var excess := mini(count - target, int(found[item]) - 1)
		found[item] -= excess
		count -= excess
	var loss := 0
	var log: Array[String] = ["抵达%s。" % location.name]
	if rng.randf() < float(location.risk):
		if rng.randf() < 0.55:
			var lost := mini(count - 15, maxi(1, count / 4))
			for key: String in keys:
				if lost <= 0:
					break
				var pieces := mini(lost, int(found[key]))
				found[key] -= pieces
				lost -= pieces
				log.append("撤离时遗失 %s ×%d" % [catalog.items[key].name, pieces])
		else:
			loss = mini(money, rng.randi_range(40, 40 + day * 20))
			log.append("回程损失 %d 瓶盖" % loss)
	for key: String in keys:
		if int(found[key]) <= 0:
			found.erase(key)
			continue
		var units := int(found[key]) * catalog.units_per_piece(key)
		found[key] = units
		log.append("带回 %s %s" % [catalog.items[key].name, catalog.amount_text(key, units)])
	return {"items": found, "money_loss": loss, "log": log}


func gear_allowed(id: String, equipment: Dictionary) -> bool:
	var definition: Dictionary = catalog.items[id]
	var category: String = definition.category
	if category not in GEAR_TYPES or equipment.has(category):
		return false
	if category == "ammo":
		return definition.has("rounds") and equipment.has("firearm") and definition.caliber == catalog.items[equipment.firearm].caliber
	return true


func yield_multiplier(budget: int, equipment: Dictionary) -> float:
	var bonus := 0.0
	if equipment.has("firearm") and equipment.has("ammo"):
		bonus += clampf(float(catalog.items[equipment.firearm].value) / 1100.0, 0.08, 0.25)
	if equipment.has("melee"):
		bonus += clampf(float(catalog.items[equipment.melee].value) / 1200.0, 0.05, 0.2)
	if equipment.has("medical"):
		bonus += clampf(float(catalog.items[equipment.medical].value) / 1800.0, 0.02, 0.12)
	return 1.0 + (budget / 500.0) * 0.25 + minf(bonus, 0.45)


func send(id: String, day: int, budget: int, interests: Array, gear: Dictionary, stock: Stockroom) -> bool:
	if not roster.has(id) or active.has(id) or budget < 50 or budget > 500 or interests.size() > 3:
		return false
	var checked: Dictionary = {}
	for category: String in GEAR_TYPES:
		if not gear.has(category):
			continue
		var item: String = gear[category]
		if not gear_allowed(item, checked) or stock.count(item) < catalog.units_per_piece(item):
			return false
		checked[category] = item
	for item: String in checked.values():
		stock.take(item, catalog.units_per_piece(item))
	active[id] = {"day": day, "budget": budget, "categories": interests.duplicate(), "gear": checked}
	return true


func arrivals(day: int, reputation: int) -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	for id: String in active.keys():
		var trip: Dictionary = active[id]
		if int(trip.day) >= day:
			continue
		active.erase(id)
		results.append(_return_trip(id, day, reputation, trip))
	return results


func _return_trip(id: String, day: int, reputation: int, trip: Dictionary) -> Dictionary:
	var rng := _rng(day, 876 + roster.keys().find(id))
	var count := roundi(rng.randi_range(30, 45) * yield_multiplier(int(trip.budget), trip.gear))
	var mishap := rng.randf() < 0.18
	if mishap:
		count -= maxi(1, roundi((count - 15) * rng.randf_range(0.3, 0.5)))

	var ids: Array[String] = []
	var weights := PackedFloat32Array()
	for item: String in catalog.items:
		var definition: Dictionary = catalog.items[item]
		if not definition.get("forSale", true):
			continue
		var weight := 0.85 if int(definition.value) <= 40 else (0.6 if int(definition.value) <= 150 else 0.4)
		weight *= 4.0 if definition.category in trip.categories else 1.0
		weight *= 0.5 if definition.category == "firearm" else 1.0
		ids.append(item)
		weights.append(weight)
	var gains: Dictionary = {}
	for index in count:
		var item := ids[rng.rand_weighted(weights)]
		gains[item] = gains.get(item, 0) + catalog.units_per_piece(item)
	var survivor: Dictionary = roster[id]
	var log: Array[String] = ["%s从外面回来了。" % survivor.name]
	if mishap:
		log.append("回程遇到麻烦，丢了一部分战利品。")
	for item: String in gains:
		log.append("%s %s" % [catalog.items[item].name, catalog.amount_text(item, gains[item])])
	var returned: Array[String] = []
	var return_chance := 0.55 + reputation * 0.002 - (0.2 if mishap else 0.0)
	for category: String in trip.gear:
		var item: String = trip.gear[category]
		if category in ["firearm", "melee"] and rng.randf() < return_chance:
			returned.append(item)
			log.append("带回装备：%s" % catalog.items[item].name)
		else:
			log.append("未带回：%s" % catalog.items[item].name)
	return {"survivor": survivor, "log": log, "mishap": mishap, "trip": trip, "gains": gains, "returned": returned}


func _rng(day: int, salt: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + day * 64151 + salt * 6967
	return rng

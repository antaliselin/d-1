class_name ShopJournal
extends RefCounted

var met: Dictionary = {}
var visited: Dictionary = {}


func meet(customer: Dictionary, day: int) -> void:
	if customer.get("special", false) and not met.has(customer.id):
		met[customer.id] = {
			"id": "customer:" + customer.id, "title": customer.name, "portrait": customer.get("portrait", ""),
			"detail": ["第 %d 天 · %s" % [day, customer.title], customer.request, customer.aside],
		}


func visit(id: String, day: int) -> void:
	if not visited.has(id):
		visited[id] = day


func entries(kind: String, catalog: ShopCatalog) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if kind == "customer":
		for entry: Dictionary in met.values():
			result.append(entry)
		return result
	for entry: Dictionary in ShopCatalog.NOTES.data:
		if entry.kind == kind:
			result.append(entry)
	if kind == "location":
		for id: String in visited:
			var location: Dictionary = catalog.locations[id]
			result.append({
				"id": "location:" + id, "title": location.name, "locationId": id,
				"detail": ["首次到访 · 第 %d 天" % visited[id], location.blurb],
			})
	return result


func contains(id: String, catalog: ShopCatalog) -> bool:
	for kind: String in ["customer", "clue", "location"]:
		for note: Dictionary in entries(kind, catalog):
			if note.id == id:
				return true
	return false

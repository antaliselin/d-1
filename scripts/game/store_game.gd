class_name StoreGame
extends RefCounted

enum Phase { PREPARE, TRADE, AFTER_TRADE, CLOSED, SCAVENGE_REPORT, EVENT, ENDED }

const UPRISING_GOODS := {"firearm": 12, "ammo": 600, "medical": 30}
const COMMUNITY_GOODS := {"food": 40, "medical": 30}

var catalog := ShopCatalog.new()
var stock := Stockroom.new(catalog)
var journal := ShopJournal.new()
var schedule := StorySchedule.new()
var world_seed: int
var expeditions: ShopExpeditions
var phase := Phase.PREPARE
var day := 1
var money := 800
var reputation := 50
var revenue := 0
var visitors: Array
var visitor_index := 0
var trade: TradeSession
var message := ""
var report: Array[String] = []
var events: Array[Dictionary] = []
var delivered: Array[ShopPiece] = []
var event_result: Array[String] = []
var next_rent := 3
var rent_period := 1
var ownership := "gang"
var water_day := 0
var remnant_day := 0
var water_waves := 0
var defense := 0
var intel := 0
var allies := 0
var ending: Dictionary = {}


func _init(seed_value: int = 41525) -> void:
	world_seed = seed_value
	expeditions = ShopExpeditions.new(catalog, world_seed)
	visitors = CustomerQueue.for_day(catalog, day, reputation, world_seed)


func traffic() -> int:
	var served := visitor_index + int(phase == Phase.AFTER_TRADE)
	return 0 if phase in [Phase.CLOSED, Phase.SCAVENGE_REPORT, Phase.ENDED] else maxi(0, visitors.size() - served)


func open_shop() -> void:
	if phase == Phase.PREPARE:
		_admit()


func current_turn_options() -> Array:
	return trade.turn().get("options", []) if phase == Phase.TRADE else []


func available_clues() -> Array:
	return trade.turn().get("clue", {}).get("accepts", []) if phase == Phase.TRADE else []


func choose_dialogue(option: Dictionary) -> void:
	if option not in current_turn_options() or not can_choose_dialogue(option):
		return
	var effects: Dictionary = option.get("effects", {})
	money += int(effects.get("money", 0))
	for entry: Dictionary in effects.get("stock", []):
		var amount := int(entry.count)
		if amount < 0:
			stock.take(entry.itemId, -amount)
		else:
			stock.add(entry.itemId, amount)
	_finish_turn(option.get("reply", ""))


func can_choose_dialogue(option: Dictionary) -> bool:
	var requirements: Dictionary = option.get("requires", {})
	if money < int(requirements.get("money", 0)):
		return false
	for entry: Dictionary in requirements.get("stock", []):
		if stock.count(entry.itemId) < int(entry.count):
			return false
	return true


func present_note(id: String) -> bool:
	if not journal.contains(id, catalog) or available_clues().is_empty():
		return false
	if id not in available_clues():
		message = "客人看了一眼，这条线索与他的询问无关。"
		return false
	_finish_turn(trade.turn().clue.get("reply", "客人认出了这条线索。"))
	return true


func complete_sale() -> void:
	if phase != Phase.TRADE or not trade.complete():
		return
	var offer := trade.sold
	money += int(offer.total)
	revenue += int(offer.total)
	change_reputation(int(offer.reputation))
	message = trade.customer.thanks
	phase = Phase.AFTER_TRADE


func skip() -> void:
	if phase != Phase.TRADE or trade.dialogue_blocked():
		return
	trade.return_all()
	trade.finished = true
	message = "%s带着箱子离开了。" % trade.customer.name
	phase = Phase.AFTER_TRADE


func next_customer() -> void:
	if phase != Phase.AFTER_TRADE:
		return
	visitor_index += 1
	if visitor_index >= visitors.size():
		trade = null
		phase = Phase.CLOSED
		message = "今日入账 %d 瓶盖。关好卷帘门，明天继续。" % revenue
	else:
		_admit()


func scavenge(location: String) -> void:
	if phase != Phase.PREPARE or location not in expeditions.destinations(day):
		return
	var trip := expeditions.scavenge(location, day, money)
	for id: String in trip.items:
		stock.add(id, trip.items[id])
	money -= int(trip.money_loss)
	journal.visit(location, day)
	phase = Phase.SCAVENGE_REPORT
	report.assign(trip.log)
	message = "天黑前赶回了铺子。今天已结束。"


func dispatch(id: String, budget: int, categories: Array, gear: Dictionary) -> bool:
	if phase != Phase.PREPARE or budget > money or not expeditions.send(id, day, budget, categories, gear, stock):
		return false
	money -= budget
	message = "%s已经出发，明早回来。今天可以照常营业。" % expeditions.roster[id].name
	return true


func next_day() -> void:
	if phase not in [Phase.CLOSED, Phase.SCAVENGE_REPORT]:
		return
	day += 1
	revenue = 0
	report.clear()
	visitor_index = 0
	phase = Phase.PREPARE
	message = ""
	events.clear()
	_queue_morning_events()
	if not events.is_empty():
		phase = Phase.EVENT
	visitors = CustomerQueue.for_day(catalog, day, reputation, world_seed)


func current_event() -> Dictionary:
	return events[0] if phase == Phase.EVENT and not events.is_empty() else {}


func delivery_needed() -> int:
	return int(current_event().get("delivery", {}).get("need", 0))


func can_deliver(id: String) -> bool:
	var delivery: Dictionary = current_event().get("delivery", {})
	return not delivery.is_empty() and event_result.is_empty() and delivered.size() < delivery_needed() and stock.count(id) > 0 and catalog.items[id].category in delivery.accepts


func deliver(id: String) -> void:
	if can_deliver(id):
		delivered.append(stock.take_piece(id))


func take_back_delivery(index: int) -> void:
	if event_result.is_empty() and index >= 0 and index < delivered.size():
		stock.refund(delivered.pop_at(index))


func event_choice_allowed(option: Dictionary) -> bool:
	if money < int(option.get("requiresMoney", 0)) or delivered.size() < int(option.get("requiresDelivery", 0)):
		return false
	if option.get("requiresFreeSurvivor", false) and expeditions.roster.size() >= catalog.survivors.size() + 1:
		return false
	if option.get("requiresHomeScavenger", false):
		var home := expeditions.roster.keys().any(func(id: String) -> bool:
			return id != ShopExpeditions.PARTNER.id and not expeditions.active.has(id)
		)
		if not home:
			return false
	if reputation < int(option.get("reputation", 0)) or allies < int(option.get("allies", 0)) or defense < int(option.get("defense", 0)):
		return false
	return stock.has_requirements(option.get("goods", {}))


func choose_event(option: Dictionary) -> void:
	var event := current_event()
	if event.is_empty() or not event_result.is_empty() or option not in event.choices or not event_choice_allowed(option):
		return
	var accepted := int(option.get("requiresDelivery", 0))
	for index in range(accepted, delivered.size()):
		stock.refund(delivered[index])
	delivered.clear()
	match event.kind:
		"story":
			schedule.advance(event, option.get("ends", false))
			event_result.append(option.outcome)
			_apply_effects(option.get("effects", {}))
		"rent":
			_resolve_rent(option.id)
		"pressure":
			_resolve_pressure(event, option)
		"finale":
			_resolve_finale(option)
		"return":
			_collect_dispatch(event.result, option.id == "resend")
			_close_event()


func confirm_event() -> void:
	if current_event().is_empty():
		return
	if event_result.is_empty() and current_event().kind != "return":
		return
	if current_event().kind == "return":
		_collect_dispatch(current_event().result, false)
	_close_event()


func _close_event() -> void:
	event_result.clear()
	events.pop_front()
	if events.is_empty():
		phase = Phase.PREPARE
		visitors = CustomerQueue.for_day(catalog, day, reputation, world_seed)


func change_reputation(delta: int) -> void:
	reputation = clampi(reputation + delta, 0, 100)


func requirement_text(goods: Dictionary) -> String:
	var entries: Array[String] = []
	for category: String in goods:
		var units := "发" if category == "ammo" else "件"
		entries.append("%s %d%s" % [catalog.categories[category], int(goods[category]), units])
	return " / ".join(entries)


func _admit() -> void:
	trade = TradeSession.new(visitors[visitor_index], stock)
	journal.meet(trade.customer, day)
	message = trade.customer.aside
	phase = Phase.TRADE


func _finish_turn(reply: String) -> void:
	trade.advance_dialogue()
	message = reply
	if trade.customer.get("dialogue", {}).get("leaveAfter", false) and trade.turn().is_empty():
		trade.finished = true
		phase = Phase.AFTER_TRADE


func _queue_morning_events() -> void:
	if ownership == "gang" and day >= next_rent:
		events.append(_rent_event())
	elif ownership != "gang":
		if water_waves >= 3 and day >= water_day:
			events.append(_finale_event())
		elif water_waves < 3 and day >= water_day:
			events.append(_pressure_event(false))
		if ownership == "conquered" and day >= remnant_day:
			events.append(_pressure_event(true))
	for result: Dictionary in expeditions.arrivals(day, reputation):
		events.append({
			"kind": "return", "heading": "派遣归来", "speaker": result.survivor,
			"lines": result.log, "result": result,
			"choices": [
				{"id": "continue", "label": "确认入库"},
				{"id": "resend", "label": "入库并再次派遣", "requiresMoney": int(result.trip.budget)},
			],
		})
	if day >= 2:
		var story := schedule.next_story(day, ownership, world_seed)
		if not story.is_empty():
			events.append(story)


func _collect_dispatch(result: Dictionary, resend: bool) -> void:
	for id: String in result.gains:
		stock.add(id, int(result.gains[id]))
	for id: String in result.returned:
		stock.add(id, 1)
	change_reputation(-2 if result.mishap else 1)
	if not resend:
		return
	var trip: Dictionary = result.trip
	var gear: Dictionary = {}
	var missing: Array[String] = []
	for category: String in ShopExpeditions.GEAR_TYPES:
		if not trip.gear.has(category):
			continue
		var id: String = trip.gear[category]
		if stock.count(id) >= catalog.units_per_piece(id) and expeditions.gear_allowed(id, gear):
			gear[category] = id
		else:
			missing.append(catalog.items[id].name)
	var budget := int(trip.budget)
	if expeditions.send(result.survivor.id, day, budget, trip.categories, gear, stock):
		money -= budget
		message = "%s再次出发，明天回来。" % result.survivor.name
		if not missing.is_empty():
			message += "未带上：" + "、".join(missing)


func _rent_event() -> Dictionary:
	var amount := _rent_amount()
	var definition: Dictionary = ShopCatalog.RULES.data.rent
	return {
		"kind": "rent", "heading": "黑鸦帮收租",
		"speaker": {"name": definition.name, "title": definition.title, "portrait": "collectors"},
		"lines": definition.firstRentLines if rent_period == 1 else ["这次的租金是 %d 瓶盖。交不上，就拿货抵。" % amount],
		"choices": [
			{"id": "pay", "label": "交租 · %d" % amount, "requiresMoney": amount},
			{"id": "refuse", "label": "用库存抵租"},
			{"id": "purchase", "label": "买下产权 · 20000", "requiresMoney": 20000},
			{"id": "uprising", "label": "摊牌", "goods": UPRISING_GOODS},
		],
	}


func _resolve_rent(choice: String) -> void:
	match choice:
		"pay":
			money -= _rent_amount()
			change_reputation(1)
			event_result.append("付掉了 %d 瓶盖。黑鸦帮三天后再来。" % _rent_amount())
		"refuse":
			event_result.append("黑鸦帮按双倍租金从库存搬走物资。")
			event_result.append_array(stock.seize(_rent_amount() * 2))
			change_reputation(-3)
		"purchase":
			money -= 20000
			_take_ownership("purchased")
		"uprising":
			stock.use_requirements(UPRISING_GOODS)
			_take_ownership("conquered")
	rent_period += 1
	next_rent = day + 3


func _take_ownership(method: String) -> void:
	ownership = method
	water_day = day + 2
	remnant_day = day + 6
	event_result.append("铺子现在归你。两天后，水塔议会的人会来。")


func _pressure_event(remnants: bool) -> Dictionary:
	var caps := [2500, 4000, 6000][mini(water_waves, 2)] as int
	var goods := {"food": 8 + water_waves * 4, "medical": 4 + water_waves * 2}
	if remnants:
		caps = 1500 + (day / 6) * 500
		goods = {"firearm": 2, "ammo": 80}
	elif water_waves == 2:
		goods.ammo = 150
	for category: String in goods:
		goods[category] = maxi(1, ceili(int(goods[category]) * (1.0 - defense * 0.2)))
	var name := "黑鸦帮残部" if remnants else "水塔议会"
	var choices: Array[Dictionary] = [
		{"id": "pay", "label": "交瓶盖 · %d" % caps, "requiresMoney": caps},
		{"id": "goods", "label": "交物资", "goods": goods},
		{"id": "hard", "label": "硬扛"},
	]
	if defense < 3:
		choices.insert(2, {"id": "fortify", "label": "加固防线", "goods": {"material": 4 + 2 * defense, "tool": 2 + 2 * defense}})
	return {
		"kind": "pressure", "heading": name, "remnants": remnants,
		"speaker": {"name": name, "portrait": "collectors"},
		"lines": ["他们带来了一张单子，要求缴纳 %d 瓶盖，或交出相应物资。" % caps],
		"choices": choices,
	}


func _resolve_pressure(event: Dictionary, option: Dictionary) -> void:
	match option.id:
		"pay":
			money -= int(option.requiresMoney)
			event_result.append("支付了 %d 瓶盖。" % int(option.requiresMoney))
		"goods":
			stock.use_requirements(option.goods)
			event_result.append("交出了这批物资。")
		"fortify":
			stock.use_requirements(option.goods)
			defense += 1
			event_result.append("街坊加固了防线。当前防线等级 %d。" % defense)
		"hard":
			if stock.use_requirements({"ammo": 120, "medical": 5}):
				change_reputation(3)
				event_result.append("你守住了铺子，消耗了 120 发弹药和 5 件医疗物资。")
			else:
				change_reputation(-6)
				event_result.append("有人闯进了仓库。")
				event_result.append_array(stock.seize(1500))
	if event.remnants:
		remnant_day = day + 6
	else:
		water_waves += 1
		water_day = day + (1 if water_waves == 3 else 4)


func _finale_event() -> Dictionary:
	return {
		"kind": "finale", "heading": "水塔之夜",
		"speaker": {"name": "水塔议会", "title": "最后的水税单", "portrait": "collectors"},
		"lines": ["你可以买下水权，可以打开泵房，也可以把街坊们叫来。今夜，由你决定。"],
		"choices": [
			{"id": "merchant", "label": "买下水权 · 30000", "requiresMoney": 30000},
			{"id": "liberator", "label": "夺回泵房", "defense": maxi(0, 2 - intel), "goods": {"firearm": 12 - intel, "ammo": 600 - 50 * intel, "medical": 30 - 2 * intel}},
			{"id": "community", "label": "交给街坊", "reputation": 80, "allies": 3, "goods": COMMUNITY_GOODS},
			{"id": "later", "label": "再等等"},
			{"id": "walkaway", "label": "把钥匙留下"},
		],
	}


func _resolve_finale(option: Dictionary) -> void:
	if option.id == "later":
		water_day = day + 1
		event_result.append("你暂时收起水税单。等准备好了，再去水塔。")
		return
	money -= int(option.get("requiresMoney", 0))
	stock.use_requirements(option.get("goods", {}))
	ending = ShopCatalog.RULES.data.endings[option.id]
	events.clear()
	phase = Phase.ENDED


func _rent_amount() -> int:
	return 1900 + (rent_period - 1) * 100


func _apply_effects(effects: Dictionary) -> void:
	var delta := int(effects.get("money", 0))
	if delta != 0:
		var before := money
		money = maxi(0, money + delta)
		event_result.append("瓶盖 %+d" % (money - before))
	var old_reputation := reputation
	change_reputation(int(effects.get("reputation", 0)))
	if old_reputation != reputation:
		event_result.append("声望 %+d" % (reputation - old_reputation))
	intel = mini(3, intel + int(effects.get("intel", 0)))
	allies = mini(3, allies + int(effects.get("ally", 0)))
	for entry: Dictionary in effects.get("gainItems", []):
		stock.add(entry.itemId, int(entry.count))
		event_result.append("获得 %s %s" % [catalog.items[entry.itemId].name, catalog.amount_text(entry.itemId, int(entry.count))])
	for entry: Dictionary in effects.get("loseItems", []):
		var amount := mini(stock.count(entry.itemId), int(entry.count))
		if stock.take(entry.itemId, amount):
			event_result.append("失去 %s %s" % [catalog.items[entry.itemId].name, catalog.amount_text(entry.itemId, amount)])
	if effects.has("hireScavenger"):
		var hired := expeditions.hire()
		if not hired.is_empty():
			event_result.append("%s愿意留下，加入了拾荒队。" % hired)
	if effects.get("loseScavenger", false):
		var lost := expeditions.lose_home_survivor()
		if not lost.is_empty():
			event_result.append("%s离开了拾荒队。" % lost)
	if ownership == "gang" and effects.has("rentShift"):
		next_rent = day + 1 if effects.rentShift.kind == "advance" else next_rent + int(effects.rentShift.days)

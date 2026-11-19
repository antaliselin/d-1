class_name ShopOverlays
extends Control

signal changed

const SCOUT_ROW = preload("res://scenes/ui/scout_row.tscn")
const NOTE_ENTRY = preload("res://scenes/ui/note_entry.tscn")

var game: StoreGame
var mode := ""
var note_tab := "customer"
var expanded_note := ""
var map_target := ""
var scout_id := ""
var dispatch_budget := 50
var interests: Array[String] = []
var gear: Dictionary = {}
var chapter_index := 0
var site_buttons: Dictionary = {}
var note_entries: Dictionary = {}
var scout_entries: Dictionary = {}

@onready var heading: Label = %HeadingLabel
@onready var subtitle: Label = %Subtitle
@onready var scroll: ScrollContainer = %Scroll
@onready var map_view: VBoxContainer = %MapView
@onready var notes_view: VBoxContainer = %NotesView
@onready var dispatch_view: VBoxContainer = %DispatchView
@onready var settlement_view: VBoxContainer = %SettlementView
@onready var intro_view: VBoxContainer = %IntroView
@onready var note_tabs: Dictionary = {
	"customer": notes_view.get_node("%Customers"),
	"clue": notes_view.get_node("%Clues"),
	"location": notes_view.get_node("%Places"),
}
@onready var interest_buttons: Dictionary = {
	"firearm": dispatch_view.get_node("%Firearm"), "ammo": dispatch_view.get_node("%Ammo"),
	"melee": dispatch_view.get_node("%Melee"), "medical": dispatch_view.get_node("%Medical"),
	"food": dispatch_view.get_node("%Food"), "material": dispatch_view.get_node("%Material"),
	"tool": dispatch_view.get_node("%Tool"), "luxury": dispatch_view.get_node("%Luxury"),
}
@onready var gear_selectors: Dictionary = {
	"firearm": dispatch_view.get_node("%GearFirearm"), "ammo": dispatch_view.get_node("%GearAmmo"),
	"melee": dispatch_view.get_node("%GearMelee"), "medical": dispatch_view.get_node("%GearMedical"),
}


func _ready() -> void:
	hide()
	%Close.pressed.connect(close)
	map_view.get_node("%Confirm").pressed.connect(_confirm_scavenge)
	notes_view.get_node("%OpenIntro").pressed.connect(_show_intro.bind(0))
	intro_view.get_node("%Next").pressed.connect(_next_chapter)
	dispatch_view.get_node("%Decrease").pressed.connect(_step_budget.bind(-50))
	dispatch_view.get_node("%Increase").pressed.connect(_step_budget.bind(50))
	dispatch_view.get_node("%Send").pressed.connect(_send)
	for tab: String in note_tabs:
		note_tabs[tab].pressed.connect(show_notes.bind(tab))
	for category: String in interest_buttons:
		interest_buttons[category].pressed.connect(_toggle_interest.bind(category))
	for category: String in gear_selectors:
		gear_selectors[category].item_selected.connect(_select_gear.bind(category))


func close() -> void:
	mode = ""
	hide()
	changed.emit()


func show_map() -> void:
	_open("map", "外出搜刮", "选一个地点。带回的物资直接入库，出门当天停止营业。")
	var sites := map_view.get_node("%Sites")
	ShopWidgets.clear_entries(sites)
	site_buttons.clear()
	for id: String in game.expeditions.destinations(game.day):
		var place: Dictionary = game.catalog.locations[id]
		var button := ShopWidgets.action(place.name, _select_location.bind(id), &"ShopQuiet", 64, 16)
		button.icon = load("res://assets/locations/%s.png" % id)
		button.expand_icon = true
		button.add_theme_constant_override("icon_max_width", 38)
		site_buttons[id] = button
		sites.add_child(button)
	_select_location("")


func show_notes(tab: String = "customer") -> void:
	note_tab = tab
	expanded_note = ""
	_open("notes", "柜台笔记", "记录见过的特殊客人、传闻和到访过的地点。")
	for key: String in note_tabs:
		note_tabs[key].theme_type_variation = &"ShopPrimary" if key == note_tab else &"ShopQuiet"
	notes_view.get_node("%OpenIntro").visible = note_tab == "clue"
	var list := notes_view.get_node("%Entries")
	ShopWidgets.clear_entries(list)
	note_entries.clear()
	var entries := game.journal.entries(note_tab, game.catalog)
	notes_view.get_node("%Empty").visible = entries.is_empty()
	for entry: Dictionary in entries:
		var note := NOTE_ENTRY.instantiate()
		var button: Button = note.get_node("Title")
		button.text = entry.title
		button.pressed.connect(_toggle_note.bind(entry.id))
		note.get_node("Detail").text = "\n\n".join(entry.detail)
		note.get_node("Present").pressed.connect(_present.bind(entry.id))
		list.add_child(note)
		note_entries[entry.id] = note


func show_settlement() -> void:
	var offer: Dictionary = game.trade.sold
	_open("settlement", "交易明细", "入账 %d 瓶盖    ·    声望 %+d" % [int(offer.total), int(offer.reputation)])
	var details: Array[String] = []
	for line: Dictionary in offer.lines:
		var amount := int(line.base) + int(line.bonus)
		var suffix := "，含协同 +%d" % int(line.bonus) if int(line.bonus) > 0 else ""
		details.append("%s %s    +%d%s" % [line.name, game.catalog.amount_text(line.id, int(line.amount)), amount, suffix])
	settlement_view.get_node("%Lines").text = "\n\n".join(details)
	settlement_view.get_node("%Lines").visible = not details.is_empty()
	settlement_view.get_node("%Healing").text = "治疗酬谢    +%d" % int(offer.healing)
	settlement_view.get_node("%Healing").visible = int(offer.healing) > 0
	settlement_view.get_node("%BudgetWarning").visible = offer.capped


func show_dispatch() -> void:
	scout_id = ""
	dispatch_budget = 50
	interests.clear()
	gear.clear()
	_open("dispatch", "派遣拾荒者", "拾荒者次日返回。派遣当天仍可照常营业。")
	var list := dispatch_view.get_node("%Survivors")
	ShopWidgets.clear_entries(list)
	scout_entries.clear()
	for id: String in game.expeditions.roster:
		var member: Dictionary = game.expeditions.roster[id]
		var traveling := game.expeditions.active.has(id)
		if scout_id == "" and not traveling:
			scout_id = id
		var entry := SCOUT_ROW.instantiate()
		entry.get_node("Portrait").texture = ShopWidgets.portrait(member.portrait)
		var button: Button = entry.get_node("Select")
		button.pressed.connect(_select_scout.bind(id))
		button.disabled = traveling
		list.add_child(entry)
		scout_entries[id] = button
	_refresh_dispatch()


func _open(key: String, title: String, description: String) -> void:
	mode = key
	heading.text = title
	subtitle.text = description
	map_view.visible = key == "map"
	notes_view.visible = key == "notes"
	dispatch_view.visible = key == "dispatch"
	settlement_view.visible = key == "settlement"
	intro_view.visible = key == "intro"
	scroll.set_deferred("scroll_vertical", 0)
	show()
	%Close.grab_focus()


func _select_location(id: String) -> void:
	map_target = id
	for key: String in site_buttons:
		site_buttons[key].theme_type_variation = &"ShopPrimary" if key == map_target else &"ShopQuiet"
	map_view.get_node("%Details").visible = map_target != ""
	map_view.get_node("%Confirm").disabled = map_target == ""
	if map_target == "":
		return
	var place: Dictionary = game.catalog.locations[map_target]
	map_view.get_node("%LocationName").text = "%s    风险 %d%%" % [place.name, roundi(place.risk * 100.0)]
	map_view.get_node("%LocationDescription").text = place.blurb
	var materials: Array[String] = []
	for entry: Dictionary in place.loot:
		var name_text: String = game.catalog.categories[game.catalog.items[entry.itemId].category]
		if name_text not in materials:
			materials.append(name_text)
	map_view.get_node("%Materials").text = "有机会找到：%s" % "、".join(materials)


func _confirm_scavenge() -> void:
	if map_target != "":
		game.scavenge(map_target)
		close()


func _show_intro(index: int) -> void:
	chapter_index = index
	var chapters: Array = ShopCatalog.INTRO.data
	var chapter: Dictionary = chapters[index]
	_open("intro", chapter.title, "开张往事    %d / %d" % [index + 1, chapters.size()])
	intro_view.get_node("%StoryText").text = "\n\n".join(chapter.lines)
	intro_view.get_node("%Next").text = chapter.action.label


func _next_chapter() -> void:
	if chapter_index + 1 < ShopCatalog.INTRO.data.size():
		_show_intro(chapter_index + 1)
	else:
		show_notes("clue")


func _toggle_note(id: String) -> void:
	expanded_note = "" if expanded_note == id else id
	var can_present := not game.available_clues().is_empty()
	for key: String in note_entries:
		var note: Control = note_entries[key]
		var expanded := key == expanded_note
		note.get_node("Detail").visible = expanded
		note.get_node("Present").visible = expanded and can_present


func _present(id: String) -> void:
	if game.present_note(id):
		close()
	else:
		subtitle.text = game.message


func _select_scout(id: String) -> void:
	scout_id = id
	_refresh_dispatch()


func _step_budget(amount: int) -> void:
	dispatch_budget = clampi(dispatch_budget + amount, 50, maxi(50, mini(500, game.money)))
	_refresh_dispatch()


func _toggle_interest(category: String) -> void:
	if category in interests:
		interests.erase(category)
	elif interests.size() < 3:
		interests.append(category)
	_refresh_dispatch()


func _select_gear(index: int, category: String) -> void:
	var item: String = gear_selectors[category].get_item_metadata(index)
	if item == "":
		gear.erase(category)
	else:
		gear[category] = item
	if category == "firearm":
		gear.erase("ammo")
	_refresh_dispatch()


func _update_gear_selector(category: String) -> void:
	var selector: OptionButton = gear_selectors[category]
	selector.clear()
	selector.add_item("%s · 不携带" % game.catalog.categories[category])
	selector.set_item_metadata(0, "")
	var other := gear.duplicate()
	other.erase(category)
	for id: String in game.catalog.items:
		if game.catalog.items[id].category != category or not game.expeditions.gear_allowed(id, other):
			continue
		if game.stock.count(id) < game.catalog.units_per_piece(id):
			continue
		selector.add_item(game.catalog.items[id].name)
		var index := selector.item_count - 1
		selector.set_item_metadata(index, id)
		if gear.get(category, "") == id:
			selector.select(index)


func _refresh_dispatch() -> void:
	for id: String in scout_entries:
		var member: Dictionary = game.expeditions.roster[id]
		var status := " · 途中" if game.expeditions.active.has(id) else (" · 已选" if id == scout_id else "")
		scout_entries[id].text = member.name + status + "    " + member.trait
	dispatch_view.get_node("%Decrease").disabled = dispatch_budget <= 50
	dispatch_view.get_node("%Increase").disabled = dispatch_budget >= mini(500, game.money)
	dispatch_view.get_node("%BudgetValue").text = "预算 %d / %d" % [dispatch_budget, mini(500, game.money)]
	dispatch_view.get_node("%InterestCount").text = "搜刮重点  %d / 3" % interests.size()
	for category: String in interest_buttons:
		var button: Button = interest_buttons[category]
		var selected := category in interests
		button.theme_type_variation = &"ShopPrimary" if selected else &"ShopQuiet"
		button.disabled = not selected and interests.size() >= 3
	dispatch_view.get_node("%EquipmentTitle").text = "装备    ·    预计产量 ×%.2f" % game.expeditions.yield_multiplier(dispatch_budget, gear)
	for category: String in gear_selectors:
		_update_gear_selector(category)
	dispatch_view.get_node("%Send").disabled = scout_id == "" or game.money < dispatch_budget


func _send() -> void:
	if game.dispatch(scout_id, dispatch_budget, interests, gear):
		close()
	else:
		subtitle.text = "无法出发，请检查人员、装备和预算。"

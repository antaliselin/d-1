extends Control

const STOCK_ROW = preload("res://scenes/ui/stock_row.tscn")
const EVENT_CHOICE = preload("res://scenes/ui/event_choice.tscn")
const DELIVERY_SLOT = preload("res://scenes/ui/delivery_slot.tscn")
const CLOSED_ART = preload("res://assets/ui/low_poly/closed_shop.webp")
const DEPARTED_ART = preload("res://assets/ui/low_poly/departed_shop.webp")
const ENDING_ART := {
	"merchant": preload("res://assets/ui/low_poly/ending_contract.webp"),
	"liberator": preload("res://assets/ui/low_poly/ending_water.webp"),
	"community": preload("res://assets/ui/low_poly/ending_ledger.webp"),
	"walkaway": preload("res://assets/ui/low_poly/ending_key.webp"),
}
const PHASE_LABELS := ["准备营业", "营业中", "营业中", "闭店", "搜刮归来", "柜台来客", "终章"]

var game := StoreGame.new()
var filters := "all"
var show_empty := false
var selection: Dictionary = {}
var refresh_pending := false
var stock_entries: Dictionary = {}
var backpack_session: TradeSession
var focus_before_overlay: Control

@onready var header: PanelContainer = %Header
@onready var inventory: PanelContainer = %Inventory
@onready var footer: PanelContainer = %Footer
@onready var shop_content: Control = $Insets
@onready var prepare_view: VBoxContainer = %PrepareView
@onready var trade_view: Control = %TradeView
@onready var event_view: Control = %EventView
@onready var report_view: VBoxContainer = %ReportView
@onready var overlays: ShopOverlays = %Overlays
@onready var board: CounterGrid = trade_view.get_node("%Grid")
@onready var portrait_stage: ShopDropSurface = %PortraitStage
@onready var visitor_portrait: TextureRect = %VisitorPortrait
@onready var inventory_hint: Label = inventory.get_node("%InventoryHint")
@onready var stock_scroll: StockDropScroll = inventory.get_node("%StockScroll")
@onready var rows: VBoxContainer = inventory.get_node("%Rows")
@onready var catalog_toggle: Button = inventory.get_node("%CatalogToggle")
@onready var filter_buttons: Dictionary = {
	"all": inventory.get_node("%All"), "firearm": inventory.get_node("%Firearms"),
	"ammo": inventory.get_node("%Ammo"), "other": inventory.get_node("%Other"),
}
@onready var return_all_button: Button = footer.get_node("%ReturnAll")
@onready var sell_button: Button = footer.get_node("%Sell")
@onready var dialogue_options: VBoxContainer = trade_view.get_node("%DialogueOptions")
@onready var health_bar: ProgressBar = trade_view.get_node("%HealthBar")


func _ready() -> void:
	inventory.get_node("%StockPreview").hide()
	overlays.game = game
	overlays.changed.connect(_queue_refresh)
	overlays.visibility_changed.connect(_sync_overlay_input)
	stock_scroll.piece_returned.connect(_return_piece)
	for key: String in filter_buttons:
		filter_buttons[key].pressed.connect(_filter_stock.bind(key))
	catalog_toggle.pressed.connect(_toggle_empty)
	footer.get_node("%NotesButton").pressed.connect(overlays.show_notes)
	ShopWidgets.button_icon(footer.get_node("%NotesButton"), ShopWidgets.ui_icon("notes"), 18)
	ShopWidgets.button_icon(return_all_button, ShopWidgets.ui_icon("undo"), 18)
	ShopWidgets.button_icon(sell_button, ShopWidgets.ui_icon("trade"), 20)
	return_all_button.pressed.connect(_return_all)
	sell_button.pressed.connect(_do.bind(game.complete_sale))
	prepare_view.get_node("%OpenShop").pressed.connect(_do.bind(game.open_shop))
	prepare_view.get_node("%Scavenge").pressed.connect(overlays.show_map)
	prepare_view.get_node("%Dispatch").pressed.connect(overlays.show_dispatch)
	board.cell_pressed.connect(_pick_cell)
	board.piece_dropped.connect(_place)
	board.piece_returned.connect(_return_piece)
	trade_view.get_node("%Rotate").pressed.connect(_rotate)
	trade_view.get_node("%ReturnPiece").pressed.connect(_return_selected)
	ShopWidgets.button_icon(trade_view.get_node("%Rotate"), ShopWidgets.ui_icon("rotate"), 17)
	ShopWidgets.button_icon(trade_view.get_node("%ReturnPiece"), ShopWidgets.ui_icon("undo"), 17)
	trade_view.get_node("%ShowClues").pressed.connect(_open_clues)
	trade_view.get_node("%OpenBackpack").pressed.connect(_open_backpack)
	trade_view.get_node("%Settlement").pressed.connect(overlays.show_settlement)
	trade_view.get_node("%NextVisitor").pressed.connect(_do.bind(game.next_customer))
	trade_view.get_node("%Skip").pressed.connect(_do.bind(game.skip))
	event_view.get_node("%Confirm").pressed.connect(_do.bind(game.confirm_event))
	report_view.get_node("%NextDay").pressed.connect(_do.bind(game.next_day))
	portrait_stage.accepts = _can_heal
	portrait_stage.dropped = _heal
	portrait_stage.clicked = _heal_selection
	var delivery: ShopDropSurface = event_view.get_node("%Delivery")
	delivery.accepts = _can_deliver
	delivery.dropped = func(data: Dictionary) -> void: _pick_stock(data.id)
	_refresh()


func _sync_overlay_input() -> void:
	if overlays.visible:
		focus_before_overlay = get_viewport().gui_get_focus_owner()
		if get_viewport().gui_is_dragging():
			get_viewport().gui_cancel_drag()
		shop_content.mouse_behavior_recursive = Control.MOUSE_BEHAVIOR_DISABLED
		shop_content.focus_behavior_recursive = Control.FOCUS_BEHAVIOR_DISABLED
	else:
		shop_content.mouse_behavior_recursive = Control.MOUSE_BEHAVIOR_INHERITED
		shop_content.focus_behavior_recursive = Control.FOCUS_BEHAVIOR_INHERITED
		if is_instance_valid(focus_before_overlay) and focus_before_overlay.is_visible_in_tree():
			focus_before_overlay.grab_focus()
		focus_before_overlay = null


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.keycode == KEY_ESCAPE:
		if overlays.visible:
			overlays.close()
		else:
			selection = {}
			_queue_refresh()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_R and not overlays.visible and _shows_backpack():
		_rotate()
		get_viewport().set_input_as_handled()


func _queue_refresh() -> void:
	if not refresh_pending:
		refresh_pending = true
		_refresh.call_deferred()


func _refresh() -> void:
	refresh_pending = false
	var previous_scroll := stock_scroll.scroll_vertical
	_render_header()
	_render_counter()
	_render_portrait()
	_render_stock()
	_render_footer()
	stock_scroll.set_deferred("scroll_vertical", previous_scroll)


func _render_header() -> void:
	header.get_node("%DayAndPhase").text = "第 %02d 天   /   %s" % [game.day, PHASE_LABELS[game.phase]]
	header.get_node("%Traffic").text = "客流    %d 人" % game.traffic()
	var rent := "距缴租  %d 天" % maxi(0, game.next_rent - game.day) if game.ownership == "gang" else "产权    已取得"
	header.get_node("%RentCountdown").text = "今日缴租" if game.ownership == "gang" and game.next_rent <= game.day else rent


func _render_counter() -> void:
	if game.phase != StoreGame.Phase.TRADE or backpack_session != game.trade:
		backpack_session = null
		board.trade = null
	prepare_view.visible = game.phase == StoreGame.Phase.PREPARE
	trade_view.visible = game.phase in [StoreGame.Phase.TRADE, StoreGame.Phase.AFTER_TRADE]
	event_view.visible = game.phase == StoreGame.Phase.EVENT
	report_view.visible = not (prepare_view.visible or trade_view.visible or event_view.visible)
	match game.phase:
		StoreGame.Phase.PREPARE:
			var message: Label = prepare_view.get_node("%Message")
			message.text = game.message
			message.visible = not game.message.is_empty()
		StoreGame.Phase.TRADE, StoreGame.Phase.AFTER_TRADE:
			_render_trade()
		StoreGame.Phase.EVENT:
			_render_event()
		StoreGame.Phase.CLOSED:
			_render_report("今日打烊", [game.message], true, CLOSED_ART)
		StoreGame.Phase.SCAVENGE_REPORT:
			_render_report("搜刮归来", game.report, true, ShopWidgets.location_icon(game.report_location))
		StoreGame.Phase.ENDED:
			_render_report(game.ending.title, [game.ending.text], false, ENDING_ART.get(game.ending.get("id", "")))


func _render_portrait() -> void:
	var key := ""
	if trade_view.visible:
		key = game.trade.customer.portrait
		portrait_stage.anchor_top = 0.20
		portrait_stage.anchor_bottom = 0.50
	elif event_view.visible:
		key = game.current_event().speaker.get("portrait", "")
		portrait_stage.anchor_top = 0.28
		portrait_stage.anchor_bottom = 0.55
		var split := 0.6
		event_view.get_node("Upper").anchor_bottom = split if key.is_empty() else portrait_stage.anchor_top
		event_view.get_node("Lower").anchor_top = split if key.is_empty() else portrait_stage.anchor_bottom
	portrait_stage.visible = not key.is_empty()
	visitor_portrait.texture = ShopWidgets.half_portrait(key) if portrait_stage.visible else null
	portrait_stage.mouse_filter = Control.MOUSE_FILTER_STOP if _shows_backpack() else Control.MOUSE_FILTER_IGNORE


func _render_trade() -> void:
	var trade := game.trade
	var person := trade.customer
	var after := game.phase == StoreGame.Phase.AFTER_TRADE
	var blocked := not after and trade.dialogue_blocked()
	var show_backpack := _shows_backpack()
	var can_open_backpack := not after and not blocked and trade.grid != null
	trade_view.get_node("%VisitorIndex").text = "%d / %d" % [game.visitor_index + 1, game.visitors.size()]
	trade_view.get_node("%VisitorName").text = "%s · %s" % [person.name, person.title]
	var conversation: ScrollContainer = trade_view.get_node("%Conversation")
	var dialogue_line: Label = trade_view.get_node("%DialogueLine")
	var line: String = game.message if after else trade.turn().get("line", person.request)
	if dialogue_line.text != line:
		dialogue_line.text = line
		conversation.scroll_vertical = 0
	var status_art: TextureRect = trade_view.get_node("%TradeStatusArt")
	status_art.visible = after
	if after:
		status_art.texture = DEPARTED_ART if trade.sold.is_empty() else ShopWidgets.ui_icon("done")
	trade_view.get_node("%Health").visible = not after
	conversation.visible = not show_backpack
	trade_view.get_node("%DialogueOptions").visible = blocked
	trade_view.get_node("%ShowClues").visible = blocked and not game.available_clues().is_empty()
	trade_view.get_node("%OpenBackpack").visible = can_open_backpack and not show_backpack
	trade_view.get_node("%TradeBoard").visible = show_backpack
	trade_view.get_node("%BoardActions").visible = show_backpack
	trade_view.get_node("%Settlement").visible = after and not trade.sold.is_empty()
	trade_view.get_node("%Skip").visible = not after and not blocked
	var next_button: Button = trade_view.get_node("%NextVisitor")
	next_button.visible = after
	next_button.text = "关门打烊" if game.visitor_index + 1 == game.visitors.size() else "下一位客人"
	var feedback: Label = trade_view.get_node("%Feedback")
	feedback.visible = not after and game.message != "" and game.message != line
	feedback.text = game.message

	if not after:
		_render_health(int(person.hp))
	if blocked:
		ShopWidgets.clear_entries(dialogue_options)
		for option: Dictionary in game.current_turn_options():
			var button := ShopWidgets.action(option.label, _do.bind(game.choose_dialogue.bind(option)), &"ShopQuiet", 40, 15)
			button.disabled = not game.can_choose_dialogue(option)
			dialogue_options.add_child(button)
	elif show_backpack:
		_render_board(trade)


func _render_health(health: int) -> void:
	trade_view.get_node("%HealthLabel").text = "生命   %d / 100" % health
	health_bar.value = health
	var fill: StyleBoxFlat = health_bar.get_theme_stylebox("fill")
	fill.bg_color = Color("#8fab76") if health >= 70 else (FacetedStyle.AMBER if health >= 35 else FacetedStyle.RED)


func _render_board(trade: TradeSession) -> void:
	var fill := trade.quote()
	trade_view.get_node("%Fill").text = "背包 %d/%d" % [int(fill.used), int(fill.usable)]
	trade_view.get_node("%Budget").text = "预算 %d" % int(fill.budget)
	var wants: Label = trade_view.get_node("%Wants")
	wants.visible = not trade.customer.wants.is_empty()
	if wants.visible:
		var labels: Array[String] = []
		for want: Dictionary in trade.customer.wants:
			labels.append(want.label)
		wants.text = "点名需求  " + "、".join(labels)
	board.trade = trade
	board.selected = selection
	board.queue_redraw()
	trade_view.get_node("%Rotate").disabled = selection.is_empty()
	var piece := selection.get("piece") as ShopPiece
	trade_view.get_node("%ReturnPiece").disabled = piece == null or piece.customer_owned
	var hint: Label = trade_view.get_node("%BoardHint")
	trade_view.get_node("%WarningIcon").visible = fill.capped or selection.has("pending_cell")
	if fill.capped:
		hint.text = "已达预算上限，成交将交付整箱。"
		hint.add_theme_color_override("font_color", FacetedStyle.RED)
	elif selection.is_empty():
		hint.text = "拖动或点选物品放入背包 · R 旋转"
		hint.add_theme_color_override("font_color", FacetedStyle.MUTED)
	else:
		hint.text = "选中  %s" % game.catalog.items[selection.id].name
		if trade.heal_amount(selection.id, piece) > 0:
			hint.text += " · 点击客人治疗"
		hint.add_theme_color_override("font_color", FacetedStyle.RED if selection.has("pending_cell") else FacetedStyle.AMBER)
	if not game.message.is_empty():
		hint.text += "\n" + game.message


func _render_event() -> void:
	var event := game.current_event()
	event_view.get_node("%EventTitle").text = event.heading
	event_view.get_node("%Speaker").text = event.speaker.name
	var resolved := not game.event_result.is_empty()
	event_view.get_node("%Narrative").text = "\n\n".join(game.event_result if resolved else event.lines)
	event_view.get_node("%Confirm").visible = resolved
	var delivery_visible := not resolved and game.delivery_needed() > 0
	event_view.get_node("%Delivery").visible = delivery_visible
	var given := event_view.get_node("%GivenItems")
	var choices := event_view.get_node("%Choices")
	var loot: VBoxContainer = event_view.get_node("%EventLoot")
	_render_loot(loot, event.result.gains if not resolved and event.get("kind", "") == "return" else {})
	ShopWidgets.clear_entries(given)
	ShopWidgets.clear_entries(choices)
	if resolved:
		return
	if delivery_visible:
		var names: Array[String] = []
		for category: String in event.delivery.accepts:
			names.append(game.catalog.categories[category])
		event_view.get_node("%DeliveryCount").text = "交付 %d/%d    %s" % [game.delivered.size(), game.delivery_needed(), " / ".join(names)]
		for index in game.delivery_needed():
			var slot: Button = DELIVERY_SLOT.instantiate()
			if index < game.delivered.size():
				var item: Dictionary = game.catalog.items[game.delivered[index].id]
				slot.text = ""
				slot.icon = ShopWidgets.icon(item.id)
				slot.tooltip_text = "取回 " + item.name
				slot.mouse_filter = Control.MOUSE_FILTER_PASS
				slot.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
				slot.disabled = false
				slot.pressed.connect(_do.bind(game.take_back_delivery.bind(index)))
			given.add_child(slot)

	for option: Dictionary in event.choices:
		var entry := EVENT_CHOICE.instantiate()
		var button: Button = entry.get_node("Select")
		button.text = option.label
		button.disabled = not game.event_choice_allowed(option)
		button.pressed.connect(_do.bind(game.choose_event.bind(option)))
		if option.has("requiresMoney"):
			ShopWidgets.button_icon(button, ShopWidgets.ui_icon("money"), 21)
		elif event.get("kind", "") == "return":
			ShopWidgets.button_icon(button, ShopWidgets.ui_icon("undo" if option.id == "resend" else "crate"), 21)
		if option.has("goods"):
			var requirements: Label = entry.get_node("Requirements")
			requirements.text = game.requirement_text(option.goods)
			requirements.show()
			button.tooltip_text = requirements.text
			if not option.goods.is_empty() and not option.has("requiresMoney"):
				ShopWidgets.button_icon(button, ShopWidgets.category_icon(option.goods.keys()[0]), 21)
		choices.add_child(entry)


func _render_report(title: String, lines: Array, allow_next: bool = true, artwork: Texture2D = null) -> void:
	report_view.get_node("%ReportTitle").text = title
	report_view.get_node("%ReportText").text = "\n\n".join(lines)
	report_view.get_node("%NextDay").visible = allow_next
	var illustration: TextureRect = report_view.get_node("%ReportArt")
	illustration.texture = artwork
	illustration.visible = artwork != null
	_render_loot(report_view.get_node("%ReportLoot"), game.report_loot if game.phase == StoreGame.Phase.SCAVENGE_REPORT else {})


func _render_loot(container: VBoxContainer, loot: Dictionary) -> void:
	ShopWidgets.clear_entries(container)
	for id: String in loot:
		var item: Dictionary = game.catalog.items[id]
		container.add_child(ShopWidgets.item_row(id, item.name, game.catalog.amount_text(id, int(loot[id]))))
	container.visible = not loot.is_empty()


func _render_stock() -> void:
	catalog_toggle.text = "仅现货" if show_empty else "全目录"
	match game.phase:
		StoreGame.Phase.TRADE:
			inventory_hint.text = "◆ 表示客人需要的物品"
		StoreGame.Phase.EVENT:
			inventory_hint.text = "◆ 表示可交付物资"
		_:
			inventory_hint.text = "按分类查看现有物资"
	for key: String in filter_buttons:
		filter_buttons[key].theme_type_variation = &"ShopPrimary" if key == filters else &"ShopQuiet"

	var trading := game.phase == StoreGame.Phase.TRADE
	var can_trade := _shows_backpack()
	var displayed := 0
	for id: String in game.catalog.items:
		var definition: Dictionary = game.catalog.items[id]
		var amount := game.stock.count(id)
		var can_show: bool = _matches_filter(definition.category) and (amount > 0 or (show_empty and definition.get("forSale", true)))
		var entry: ShopStockRow = stock_entries.get(id)
		if not can_show:
			if entry != null:
				entry.hide()
			continue
		if entry == null:
			entry = STOCK_ROW.instantiate()
			entry.item_pressed.connect(_pick_stock)
			rows.add_child(entry)
			stock_entries[id] = entry
		if entry.get_index() != displayed:
			rows.move_child(entry, displayed)
		var can_deliver := game.phase == StoreGame.Phase.EVENT and game.can_deliver(id)
		var needed := can_deliver
		if trading:
			needed = ShopSettlement.matches(game.trade.customer, id, definition.category)
		entry.configure(definition, amount, selection.get("id") == id and selection.get("piece") == null, needed, can_trade or can_deliver)
		entry.show()
		displayed += 1
	inventory.get_node("%EmptyStock").visible = displayed == 0


func _matches_filter(category: String) -> bool:
	if filters == "other":
		return category not in ["firearm", "ammo"]
	return filters == "all" or filters == category


func _render_footer() -> void:
	footer.get_node("%MoneyValue").text = str(game.money)
	footer.get_node("%ReputationValue").text = str(game.reputation)
	var show_backpack := _shows_backpack()
	return_all_button.disabled = not show_backpack
	var offer: Dictionary = game.trade.quote() if show_backpack else {}
	var amount := int(offer.get("total", 0))
	sell_button.text = "成交" if amount == 0 else "成交 +%d" % amount
	sell_button.disabled = not offer.get("can_sell", false)


func _open_clues() -> void:
	overlays.show_notes("location" if game.visitor_index == 0 else "customer")


func _open_backpack() -> void:
	if game.phase != StoreGame.Phase.TRADE or not game.trade.can_handle() or game.trade.grid == null:
		return
	backpack_session = game.trade
	game.message = ""
	_queue_refresh()


func _shows_backpack() -> bool:
	return game.phase == StoreGame.Phase.TRADE and backpack_session == game.trade and game.trade.grid != null and game.trade.can_handle()


func _can_heal(data: Dictionary) -> bool:
	return _shows_backpack() and game.trade.heal_amount(data.id, data.get("piece")) > 0


func _heal_selection() -> void:
	if not selection.is_empty() and _can_heal(selection):
		_heal(selection)


func _can_deliver(data: Dictionary) -> bool:
	return data.get("piece") == null and game.can_deliver(data.id)


func _filter_stock(key: String) -> void:
	filters = key
	stock_scroll.scroll_vertical = 0
	_queue_refresh()


func _toggle_empty() -> void:
	show_empty = not show_empty
	stock_scroll.scroll_vertical = 0
	_queue_refresh()


func _pick_stock(id: String) -> void:
	match game.phase:
		StoreGame.Phase.TRADE:
			if _shows_backpack():
				var same: bool = selection.get("id") == id and selection.get("piece") == null
				selection = {} if same else {"id": id, "piece": null, "rotation": 0, "grab": Vector2i.ZERO}
				_queue_refresh()
		StoreGame.Phase.EVENT:
			if game.can_deliver(id):
				game.deliver(id)
				_queue_refresh()


func _pick_cell(cell: Vector2i) -> void:
	var piece := game.trade.grid.piece_at(cell)
	if not selection.is_empty() and (piece == null or piece != selection.get("piece") or int(selection.rotation) != piece.rotation):
		_place(selection, cell)
	elif piece != null:
		selection = {"id": piece.id, "piece": piece, "rotation": piece.rotation, "grab": cell - piece.anchor}
		_queue_refresh()


func _place(data: Dictionary, cell: Vector2i) -> void:
	var result := game.trade.place(data.id, data.get("piece"), cell, int(data.rotation), data.get("grab", Vector2i.ZERO))
	game.message = result.message
	selection = {} if result.ok else data.duplicate()
	if not selection.is_empty():
		selection.pending_cell = cell
	_queue_refresh()


func _heal(data: Dictionary) -> void:
	game.message = game.trade.heal_with(data.id, data.get("piece"))
	selection = {}
	_queue_refresh()


func _rotate() -> void:
	var data: Variant = get_viewport().gui_get_drag_data()
	if data is Dictionary and data.has("rotation"):
		data.rotation = posmod(int(data.rotation) + 1, 4)
		data.grab = Vector2i.ZERO
		if board != null:
			board.queue_redraw()
		return
	if selection.is_empty():
		return
	selection.rotation = posmod(int(selection.rotation) + 1, 4)
	selection.grab = Vector2i.ZERO
	if selection.has("pending_cell"):
		_place(selection, selection.pending_cell)
		return
	var piece := selection.get("piece") as ShopPiece
	if piece != null:
		if not game.trade.rotate_piece(piece, int(selection.rotation)):
			game.message = "没有足够空间旋转，物品还在原格。"
			selection.rotation = piece.rotation
		else:
			game.message = "物品已旋转。"
	_queue_refresh()


func _return_selected() -> void:
	var piece := selection.get("piece") as ShopPiece
	if piece != null:
		_return_piece(piece)


func _return_piece(piece: ShopPiece) -> void:
	if game.phase != StoreGame.Phase.TRADE:
		return
	if game.trade.take_back(piece):
		game.message = "%s已收回库存。" % game.catalog.items[piece.id].name
	else:
		game.message = "客人的物品只能放在箱子里。"
	selection = {}
	_queue_refresh()


func _return_all() -> void:
	if not _shows_backpack():
		return
	game.trade.return_all()
	game.message = "已把自己的物资收回库存。"
	selection = {}
	_queue_refresh()


func _do(action: Callable) -> void:
	action.call()
	selection = {}
	_queue_refresh()

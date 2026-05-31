class_name GameMenuPanel
extends PanelContainer

signal close_requested()

@onready var close_button: Button = $MarginContainer/VBoxContainer/HeaderRow/CloseButton
@onready var inventory_list: VBoxContainer = $MarginContainer/VBoxContainer/Tabs/Inventory/InventoryMargin/InventoryScroll/InventoryList
@onready var craft_list: VBoxContainer = $MarginContainer/VBoxContainer/Tabs/Craft/CraftMargin/CraftScroll/CraftList
@onready var business_list: VBoxContainer = $MarginContainer/VBoxContainer/Tabs/Business/BusinessMargin/BusinessScroll/BusinessList
@onready var quest_list: VBoxContainer = $MarginContainer/VBoxContainer/Tabs/Quests/QuestMargin/QuestScroll/QuestList
@onready var character_list: VBoxContainer = $MarginContainer/VBoxContainer/Tabs/Character/CharacterMargin/CharacterScroll/CharacterList
@onready var resume_button: Button = $MarginContainer/VBoxContainer/Tabs/System/SystemMargin/SystemBox/ActionRow/ResumeButton
@onready var save_button: Button = $MarginContainer/VBoxContainer/Tabs/System/SystemMargin/SystemBox/ActionRow/SaveButton
@onready var load_button: Button = $MarginContainer/VBoxContainer/Tabs/System/SystemMargin/SystemBox/ActionRow/LoadButton
@onready var save_status_label: Label = $MarginContainer/VBoxContainer/Tabs/System/SystemMargin/SystemBox/SaveStatusLabel
@onready var controls_label: Label = $MarginContainer/VBoxContainer/Tabs/System/SystemMargin/SystemBox/ControlsLabel

var _scene_loader: Node
var _quest_system: Node


func _ready() -> void:
	visible = false
	close_button.pressed.connect(_on_close_pressed)
	resume_button.pressed.connect(_on_close_pressed)
	save_button.pressed.connect(_on_save_pressed)
	load_button.pressed.connect(_on_load_pressed)
	SaveManager.game_saved.connect(_on_game_saved)
	SaveManager.game_loaded.connect(_on_game_loaded)
	SaveManager.save_failed.connect(_on_save_failed)
	SaveManager.load_failed.connect(_on_load_failed)


func bind_context(scene_loader: Node, quest_system: Node) -> void:
	_scene_loader = scene_loader
	_quest_system = quest_system


func open_menu() -> void:
	refresh()
	visible = true


func close_menu() -> void:
	visible = false


func refresh() -> void:
	var location_summary = _get_location_summary()
	_refresh_inventory(location_summary)
	_refresh_craft()
	_refresh_business()
	_refresh_quests()
	_refresh_character(location_summary)
	_refresh_system()


func _refresh_inventory(location_summary: Dictionary) -> void:
	_clear_children(inventory_list)

	var inventory = location_summary.get("controlled_inventory", []) as Array
	if inventory.is_empty():
		inventory_list.add_child(_make_empty_label("Inventory is empty."))
		return

	for stack_value in inventory:
		var stack = stack_value as Dictionary
		var title = "%s x%d" % [
			str(stack.get("display_name", stack.get("item_id", "Unknown Item"))),
			int(stack.get("quantity", 0)),
		]
		var tags = PackedStringArray()
		tags.append(str(stack.get("item_type", "misc")).capitalize())
		if bool(stack.get("is_usable", false)):
			tags.append("Usable")

		var detail = "%s\n%s" % [
			_join_strings(tags, " / "),
			str(stack.get("description", "")),
		]
		inventory_list.add_child(_make_section(title, detail))


func _refresh_craft() -> void:
	_clear_children(craft_list)

	var actor = _get_controlled_character()
	if actor == null:
		craft_list.add_child(_make_empty_label("No controlled character."))
		return

	var recipes = CraftSystem.get_recipe_summaries(actor) as Array
	if recipes.is_empty():
		craft_list.add_child(_make_empty_label("No recipes known."))
		return

	for recipe_value in recipes:
		var recipe = recipe_value as Dictionary
		craft_list.add_child(_make_recipe_section(recipe))


func _refresh_business() -> void:
	_clear_children(business_list)

	var actor = _get_controlled_character()
	if actor == null:
		business_list.add_child(_make_empty_label("No controlled character."))
		return

	var location_summary: Dictionary = _get_location_summary()
	var shop_id: String = _get_active_shop_id(location_summary)
	if shop_id.is_empty():
		business_list.add_child(_make_section("Business", "Coins: %d" % BusinessSystem.get_currency(actor.character_id)))
		business_list.add_child(_make_empty_label("There is no market in this location."))
		return

	var market: Dictionary = BusinessSystem.get_market_summary(actor, shop_id)
	business_list.add_child(_make_section(
		str(market.get("display_name", "Market")),
		"Coins: %d\n%s" % [
			int(market.get("currency", 0)),
			str(market.get("description", "")),
		]
	))

	var sell_offers: Array = market.get("sell_offers", []) as Array
	if sell_offers.is_empty():
		business_list.add_child(_make_empty_label("Nothing in your bag can be sold here."))
	else:
		business_list.add_child(_make_label("Sell"))
		for offer_value in sell_offers:
			var offer: Dictionary = offer_value as Dictionary
			business_list.add_child(_make_sell_section(offer, str(market.get("shop_id", ""))))

	var buy_offers: Array = market.get("buy_offers", []) as Array
	if buy_offers.is_empty():
		business_list.add_child(_make_empty_label("This market has nothing for sale."))
	else:
		business_list.add_child(_make_label("Buy"))
		for buy_value in buy_offers:
			var buy_offer: Dictionary = buy_value as Dictionary
			business_list.add_child(_make_buy_section(buy_offer, str(market.get("shop_id", ""))))


func _get_active_shop_id(location_summary: Dictionary) -> String:
	var shops: Array = location_summary.get("shops", []) as Array
	for shop_value in shops:
		var shop: Dictionary = shop_value as Dictionary
		var shop_id: String = str(shop.get("id", ""))
		if not shop_id.is_empty():
			return shop_id

	return ""


func _refresh_quests() -> void:
	_clear_children(quest_list)

	if _quest_system == null:
		quest_list.add_child(_make_empty_label("Quest system unavailable."))
		return

	var quests = _quest_system.get_summary() as Array
	if quests.is_empty():
		quest_list.add_child(_make_empty_label("No quests yet."))
		return

	for quest_value in quests:
		var quest = quest_value as Dictionary
		var title = "%s  [%s]  %d/%d" % [
			str(quest.get("display_name", quest.get("quest_id", "Unknown Quest"))),
			str(quest.get("status", "unknown")).capitalize(),
			int(quest.get("completed_count", 0)),
			int(quest.get("total_count", 0)),
		]

		var details = PackedStringArray()
		var objectives = quest.get("objectives", {}) as Dictionary
		for objective_value in objectives.values():
			var objective = objective_value as Dictionary
			var marker = "Open"
			if bool(objective.get("completed", false)):
				marker = "Done"
			details.append("%s - %s" % [
				marker,
				str(objective.get("description", objective.get("id", ""))),
			])

		if not str(quest.get("failed_reason", "")).is_empty():
			details.append("Failed: %s" % str(quest.get("failed_reason", "")))

		quest_list.add_child(_make_section(title, _join_strings(details, "\n")))


func _refresh_character(location_summary: Dictionary) -> void:
	_clear_children(character_list)

	var character = location_summary.get("controlled_character", {}) as Dictionary
	if character.is_empty():
		character_list.add_child(_make_empty_label("No controlled character."))
		return

	var attributes = character.get("attributes", {}) as Dictionary
	var equipment = character.get("equipment_slots", {}) as Dictionary
	character_list.add_child(_make_section(
		str(character.get("display_name", character.get("id", "Unknown"))),
		"Kind: %s\nFaction: %s\nHP: %d / %d\nPosition: %s facing %s" % [
			str(character.get("kind", "unknown")).capitalize(),
			str(character.get("faction_id", "none")),
			int(character.get("hp", attributes.get("hp", 0))),
			int(character.get("max_hp", attributes.get("max_hp", 0))),
			str(character.get("grid_position", Vector2i.ZERO)),
			str(character.get("facing", "unknown")),
		]
	))

	var attribute_lines = PackedStringArray()
	for key in ["level", "strength", "agility", "intellect", "vitality"]:
		attribute_lines.append("%s: %s" % [key.capitalize(), str(attributes.get(key, 0))])
	character_list.add_child(_make_section("Attributes", _join_strings(attribute_lines, "\n")))

	var equipment_lines = PackedStringArray()
	for slot_id in equipment.keys():
		var item_id = str(equipment.get(slot_id, ""))
		var item_label = "-"
		if not item_id.is_empty():
			item_label = item_id
		equipment_lines.append("%s: %s" % [str(slot_id).capitalize(), item_label])
	character_list.add_child(_make_section("Equipment", _join_strings(equipment_lines, "\n")))


func _refresh_system() -> void:
	var save_state = "No save file yet."
	if SaveManager.has_save():
		save_state = "Save file ready."
	if not SaveManager.last_message.is_empty():
		save_state = SaveManager.last_message
	save_status_label.text = save_state
	controls_label.text = "Move: WASD / Arrow Keys\nInteract: E / Enter\nRest or wait: R\nMenu: Tab / I\nDebug: F3\nSave: F5\nLoad: F9"


func _get_location_summary() -> Dictionary:
	if _scene_loader == null or _scene_loader.current_scene == null:
		return {}

	if not is_instance_valid(_scene_loader.current_scene):
		return {}

	if not _scene_loader.current_scene.has_method("get_location_summary"):
		return {}

	return _scene_loader.current_scene.get_location_summary() as Dictionary


func _get_controlled_character() -> CharacterEntity:
	if _scene_loader == null or _scene_loader.current_scene == null:
		return null

	if not is_instance_valid(_scene_loader.current_scene):
		return null

	if not _scene_loader.current_scene.has_method("get_controlled_character"):
		return null

	return _scene_loader.current_scene.get_controlled_character() as CharacterEntity


func _clear_children(parent: Node) -> void:
	for child in parent.get_children():
		child.queue_free()


func _make_label(text: String) -> Label:
	var label = Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label


func _make_empty_label(text: String) -> Label:
	var label = _make_label(text)
	label.modulate = Color(0.78, 0.78, 0.78)
	return label


func _make_section(title: String, detail: String) -> VBoxContainer:
	var section = VBoxContainer.new()
	section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	section.custom_minimum_size = Vector2(0.0, 64.0)
	section.add_theme_constant_override("separation", 3)

	var title_label = _make_label(title)
	title_label.add_theme_font_size_override("font_size", 16)
	section.add_child(title_label)

	if not detail.is_empty():
		var detail_label = _make_label(detail)
		detail_label.modulate = Color(0.82, 0.82, 0.82)
		section.add_child(detail_label)

	var separator = HSeparator.new()
	section.add_child(separator)
	return section


func _make_recipe_section(recipe: Dictionary) -> VBoxContainer:
	var failure_text = ""
	if not bool(recipe.get("can_craft", false)):
		failure_text = "\n%s" % str(recipe.get("failure_reason", ""))

	var section = _make_section(
		str(recipe.get("display_name", recipe.get("id", "Unknown Recipe"))),
		"%s\nIngredients: %s\nCreates: %s%s" % [
			str(recipe.get("description", "")),
			str(recipe.get("ingredient_text", "")),
			str(recipe.get("output_text", "")),
			failure_text,
		]
	)

	var button = Button.new()
	button.text = "Craft"
	button.custom_minimum_size = Vector2(120.0, 34.0)
	button.disabled = not bool(recipe.get("can_craft", false))
	button.pressed.connect(_on_craft_pressed.bind(str(recipe.get("id", ""))))
	section.add_child(button)
	return section


func _make_sell_section(offer: Dictionary, shop_id: String) -> VBoxContainer:
	var section = _make_section(
		"%s x%d" % [
			str(offer.get("display_name", offer.get("item_id", "Unknown Item"))),
			int(offer.get("quantity", 0)),
		],
		"Sell price: %d coins each\nStack value: %d coins" % [
			int(offer.get("price", 0)),
			int(offer.get("total_value", 0)),
		]
	)

	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var sell_one_button = Button.new()
	sell_one_button.text = "Sell 1"
	sell_one_button.custom_minimum_size = Vector2(120.0, 34.0)
	sell_one_button.disabled = not bool(offer.get("can_sell", false))
	sell_one_button.pressed.connect(_on_trade_pressed.bind(shop_id, "sell", str(offer.get("item_id", "")), 1))
	row.add_child(sell_one_button)

	var sell_stack_button = Button.new()
	sell_stack_button.text = "Sell Stack"
	sell_stack_button.custom_minimum_size = Vector2(140.0, 34.0)
	sell_stack_button.disabled = not bool(offer.get("can_sell", false))
	sell_stack_button.pressed.connect(_on_trade_pressed.bind(shop_id, "sell", str(offer.get("item_id", "")), int(offer.get("quantity", 1))))
	row.add_child(sell_stack_button)

	section.add_child(row)
	return section


func _make_buy_section(offer: Dictionary, shop_id: String) -> VBoxContainer:
	var detail = "Buy price: %d coins\n%s" % [
		int(offer.get("price", 0)),
		str(offer.get("description", "")),
	]
	if not bool(offer.get("can_buy", false)):
		detail += "\n%s" % str(offer.get("failure_reason", ""))

	var section = _make_section(
		str(offer.get("display_name", offer.get("item_id", "Unknown Item"))),
		detail
	)

	var button = Button.new()
	button.text = "Buy 1"
	button.custom_minimum_size = Vector2(120.0, 34.0)
	button.disabled = not bool(offer.get("can_buy", false))
	button.pressed.connect(_on_trade_pressed.bind(shop_id, "buy", str(offer.get("item_id", "")), 1))
	section.add_child(button)
	return section


func _join_strings(values: PackedStringArray, separator: String) -> String:
	var result = ""
	for index in range(values.size()):
		if index > 0:
			result += separator
		result += values[index]

	return result


func _on_close_pressed() -> void:
	close_requested.emit()


func _on_save_pressed() -> void:
	SaveManager.save_game()
	_refresh_system()


func _on_load_pressed() -> void:
	SaveManager.load_game()
	_refresh_system()


func _on_craft_pressed(recipe_id: String) -> void:
	var actor = _get_controlled_character()
	if actor == null:
		return

	var action: GameAction = ActionSystem.create_action("CraftAction", actor, {
		"recipe_id": recipe_id,
	}, {
		"source": "menu",
	})
	ActionSystem.submit(action)
	refresh()


func _on_trade_pressed(shop_id: String, trade_type: String, item_id: String, quantity: int) -> void:
	var actor = _get_controlled_character()
	if actor == null:
		return

	var action: GameAction = ActionSystem.create_action("TradeAction", actor, {
		"shop_id": shop_id,
		"trade_type": trade_type,
		"item_id": item_id,
		"quantity": quantity,
	}, {
		"source": "menu",
	})
	ActionSystem.submit(action)
	refresh()


func _on_game_saved(_save_path: String) -> void:
	_refresh_system()


func _on_game_loaded(_save_path: String) -> void:
	refresh()


func _on_save_failed(_save_path: String, _reason: String) -> void:
	_refresh_system()


func _on_load_failed(_save_path: String, _reason: String) -> void:
	_refresh_system()

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
@onready var tabs: TabContainer = $MarginContainer/VBoxContainer/Tabs

var _scene_loader: Node
var _quest_system: Node


func _ready() -> void:
	visible = false
	_apply_tab_titles()
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
		inventory_list.add_child(_make_empty_label("背包是空的。"))
		return

	for stack_value in inventory:
		var stack = stack_value as Dictionary
		var title = "%s x%d" % [
			str(stack.get("display_name", stack.get("item_id", "Unknown Item"))),
			int(stack.get("quantity", 0)),
		]
		var tags = PackedStringArray()
		tags.append(_item_type_label(str(stack.get("item_type", "misc"))))
		if bool(stack.get("is_usable", false)):
			tags.append("可使用")

		var detail = "%s\n%s" % [
			_join_strings(tags, " / "),
			str(stack.get("description", "")),
		]
		var section: VBoxContainer = _make_section(title, detail)
		if bool(stack.get("equippable", false)):
			var equip_button: Button = Button.new()
			equip_button.text = "装备"
			equip_button.custom_minimum_size = Vector2(120.0, 34.0)
			equip_button.pressed.connect(_on_equip_pressed.bind(str(stack.get("item_id", ""))))
			section.add_child(equip_button)
		inventory_list.add_child(section)


func _refresh_craft() -> void:
	_clear_children(craft_list)

	var actor = _get_controlled_character()
	if actor == null:
		craft_list.add_child(_make_empty_label("没有可控制角色。"))
		return

	var recipes = CraftSystem.get_recipe_summaries(actor) as Array
	if recipes.is_empty():
		craft_list.add_child(_make_empty_label("还没有已知配方。"))
		return

	for recipe_value in recipes:
		var recipe = recipe_value as Dictionary
		craft_list.add_child(_make_recipe_section(recipe))


func _refresh_business() -> void:
	_clear_children(business_list)

	var actor = _get_controlled_character()
	if actor == null:
		business_list.add_child(_make_empty_label("没有可控制角色。"))
		return

	var location_summary: Dictionary = _get_location_summary()
	var shop_id: String = _get_active_shop_id(location_summary)
	if shop_id.is_empty():
		business_list.add_child(_make_section("经营", "金币：%d" % BusinessSystem.get_currency(actor.character_id)))
		business_list.add_child(_make_empty_label("这里没有可用的市场。"))
		return

	var market: Dictionary = BusinessSystem.get_market_summary(actor, shop_id)
	business_list.add_child(_make_section(
		str(market.get("display_name", "Market")),
		"金币：%d\n%s" % [
			int(market.get("currency", 0)),
			str(market.get("description", "")),
		]
	))

	var sell_offers: Array = market.get("sell_offers", []) as Array
	if sell_offers.is_empty():
		business_list.add_child(_make_empty_label("背包里没有这里收购的物品。"))
	else:
		business_list.add_child(_make_label("出售"))
		for offer_value in sell_offers:
			var offer: Dictionary = offer_value as Dictionary
			business_list.add_child(_make_sell_section(offer, str(market.get("shop_id", ""))))

	var buy_offers: Array = market.get("buy_offers", []) as Array
	if buy_offers.is_empty():
		business_list.add_child(_make_empty_label("这个市场暂时没有可购买的物品。"))
	else:
		business_list.add_child(_make_label("购买"))
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
		quest_list.add_child(_make_empty_label("任务系统不可用。"))
		return

	var quests = _quest_system.get_summary() as Array
	if quests.is_empty():
		quest_list.add_child(_make_empty_label("还没有任务。"))
		return

	for quest_value in quests:
		var quest = quest_value as Dictionary
		var title = "%s  [%s]  %d/%d" % [
			str(quest.get("display_name", quest.get("quest_id", "Unknown Quest"))),
			_quest_status_label(str(quest.get("status", "unknown"))),
			int(quest.get("completed_count", 0)),
			int(quest.get("total_count", 0)),
		]

		var details = PackedStringArray()
		var objectives = quest.get("objectives", {}) as Dictionary
		for objective_value in objectives.values():
			var objective = objective_value as Dictionary
			var marker = "Open"
			if bool(objective.get("completed", false)):
				marker = "完成"
			else:
				marker = "进行中"
			details.append("%s - %s" % [
				marker,
				str(objective.get("description", objective.get("id", ""))),
			])

		if not str(quest.get("failed_reason", "")).is_empty():
			details.append("失败原因：%s" % str(quest.get("failed_reason", "")))

		quest_list.add_child(_make_section(title, _join_strings(details, "\n")))


func _refresh_character(location_summary: Dictionary) -> void:
	_clear_children(character_list)

	var character = location_summary.get("controlled_character", {}) as Dictionary
	if character.is_empty():
		character_list.add_child(_make_empty_label("没有可控制角色。"))
		return

	var attributes = character.get("attributes", {}) as Dictionary
	var effective_attributes = character.get("effective_attributes", attributes) as Dictionary
	var equipment = character.get("equipment_slots", {}) as Dictionary
	character_list.add_child(_make_section(
		str(character.get("display_name", character.get("id", "Unknown"))),
		"类型：%s\n阵营：%s\n生命：%d / %d\n位置：%s  朝向：%s" % [
			_character_kind_label(str(character.get("kind", "unknown"))),
			str(character.get("faction_id", "none")),
			int(character.get("hp", attributes.get("hp", 0))),
			int(effective_attributes.get("max_hp", character.get("max_hp", attributes.get("max_hp", 0)))),
			str(character.get("grid_position", Vector2i.ZERO)),
			_facing_label(str(character.get("facing", "unknown"))),
		]
	))

	var attribute_lines = PackedStringArray()
	for key in ["level", "strength", "agility", "intellect", "vitality", "max_hp"]:
		attribute_lines.append("%s：%s" % [_attribute_label(key), _format_effective_attribute(attributes, effective_attributes, key)])
	character_list.add_child(_make_section("属性", _join_strings(attribute_lines, "\n")))

	var equipment_lines = PackedStringArray()
	for slot_id in equipment.keys():
		var slot_data: Dictionary = equipment.get(slot_id, {}) as Dictionary
		var item_label = str(slot_data.get("display_name", ""))
		if item_label.is_empty():
			item_label = "-"
		var bonus_text: String = _format_attribute_bonuses(slot_data.get("attribute_bonuses", {}) as Dictionary)
		if not bonus_text.is_empty():
			item_label += "  " + bonus_text
		equipment_lines.append("%s：%s" % [_equipment_slot_label(str(slot_id)), item_label])
	character_list.add_child(_make_section("装备", _join_strings(equipment_lines, "\n")))

	for slot_id in equipment.keys():
		var slot_data: Dictionary = equipment.get(slot_id, {}) as Dictionary
		if str(slot_data.get("item_id", "")).is_empty():
			continue
		var button: Button = Button.new()
		button.text = "卸下%s" % _equipment_slot_label(str(slot_id))
		button.custom_minimum_size = Vector2(140.0, 34.0)
		button.pressed.connect(_on_unequip_pressed.bind(str(slot_id)))
		character_list.add_child(button)


func _refresh_system() -> void:
	var save_state = "还没有存档。"
	if SaveManager.has_save():
		save_state = "已有可读取的存档。"
	if not SaveManager.last_message.is_empty():
		save_state = SaveManager.last_message
	save_status_label.text = save_state
	controls_label.text = "移动：WASD / 方向键\n互动：E / Enter\n休息或等待：R\n菜单：Tab / I\n调试：F3\n保存：F5\n读取：F9"


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
		"%s\n材料：%s\n产出：%s%s" % [
			str(recipe.get("description", "")),
			str(recipe.get("ingredient_text", "")),
			str(recipe.get("output_text", "")),
			failure_text,
		]
	)

	var button = Button.new()
	button.text = "制作"
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
		"出售单价：%d 金币\n整组价值：%d 金币" % [
			int(offer.get("price", 0)),
			int(offer.get("total_value", 0)),
		]
	)

	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var sell_one_button = Button.new()
	sell_one_button.text = "出售 1 个"
	sell_one_button.custom_minimum_size = Vector2(120.0, 34.0)
	sell_one_button.disabled = not bool(offer.get("can_sell", false))
	sell_one_button.pressed.connect(_on_trade_pressed.bind(shop_id, "sell", str(offer.get("item_id", "")), 1))
	row.add_child(sell_one_button)

	var sell_stack_button = Button.new()
	sell_stack_button.text = "出售整组"
	sell_stack_button.custom_minimum_size = Vector2(140.0, 34.0)
	sell_stack_button.disabled = not bool(offer.get("can_sell", false))
	sell_stack_button.pressed.connect(_on_trade_pressed.bind(shop_id, "sell", str(offer.get("item_id", "")), int(offer.get("quantity", 1))))
	row.add_child(sell_stack_button)

	section.add_child(row)
	return section


func _make_buy_section(offer: Dictionary, shop_id: String) -> VBoxContainer:
	var detail = "购买价格：%d 金币\n%s" % [
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
	button.text = "购买 1 个"
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


func _apply_tab_titles() -> void:
	for index in range(tabs.get_tab_count()):
		var tab_control: Control = tabs.get_tab_control(index)
		if tab_control == null:
			continue
		if tab_control.has_meta("_tab_title"):
			tabs.set_tab_title(index, str(tab_control.get_meta("_tab_title")))


func _item_type_label(item_type: String) -> String:
	match item_type:
		"consumable":
			return "消耗品"
		"seed":
			return "种子"
		"material":
			return "材料"
		"tool":
			return "工具"
		"equipment":
			return "装备"
		"key":
			return "关键物品"
		_:
			return "杂物"


func _quest_status_label(status: String) -> String:
	match status:
		"active":
			return "进行中"
		"completed":
			return "已完成"
		"failed":
			return "失败"
		_:
			return "未知"


func _character_kind_label(kind: String) -> String:
	match kind:
		"player":
			return "玩家"
		"npc":
			return "NPC"
		"enemy":
			return "敌人"
		"companion":
			return "同伴"
		_:
			return kind


func _facing_label(facing: String) -> String:
	match facing:
		"up":
			return "上"
		"down":
			return "下"
		"left":
			return "左"
		"right":
			return "右"
		_:
			return facing


func _attribute_label(attribute_id: String) -> String:
	match attribute_id:
		"level":
			return "等级"
		"strength":
			return "力量"
		"agility":
			return "敏捷"
		"intellect":
			return "智力"
		"vitality":
			return "体质"
		"max_hp":
			return "生命上限"
		_:
			return attribute_id


func _equipment_slot_label(slot_id: String) -> String:
	match slot_id:
		"weapon":
			return "武器"
		"offhand":
			return "副手"
		"head":
			return "头部"
		"body":
			return "身体"
		"armor":
			return "护甲"
		"accessory":
			return "饰品"
		"tool":
			return "工具"
		_:
			return slot_id


func _format_attribute_bonuses(bonuses: Dictionary) -> String:
	if bonuses.is_empty():
		return ""

	var parts: PackedStringArray = PackedStringArray()
	for key in bonuses.keys():
		var amount: int = int(bonuses[key])
		if amount == 0:
			continue
		var prefix: String = "+" if amount > 0 else ""
		parts.append("%s%s%s" % [prefix, amount, _attribute_label(str(key))])

	return _join_strings(parts, " ")


func _format_effective_attribute(base_attributes: Dictionary, effective_attributes: Dictionary, attribute_id: String) -> String:
	var base_value: int = int(base_attributes.get(attribute_id, 0))
	var effective_value: int = int(effective_attributes.get(attribute_id, base_value))
	if effective_value == base_value:
		return str(base_value)

	var delta: int = effective_value - base_value
	var prefix: String = "+" if delta > 0 else ""
	return "%d -> %d (%s%d)" % [base_value, effective_value, prefix, delta]


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


func _on_equip_pressed(item_id: String) -> void:
	var actor = _get_controlled_character()
	if actor == null:
		return

	var action: GameAction = ActionSystem.create_action("EquipItemAction", actor, {
		"item_id": item_id,
	}, {
		"source": "menu",
	})
	ActionSystem.submit(action)
	refresh()


func _on_unequip_pressed(slot_id: String) -> void:
	var actor = _get_controlled_character()
	if actor == null:
		return

	var action: GameAction = ActionSystem.create_action("UnequipItemAction", actor, {
		"slot_id": slot_id,
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

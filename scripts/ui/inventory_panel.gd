class_name InventoryPanel
extends Control

signal close_requested()
signal inventory_action_requested(action_type: String, target: Dictionary)

const CATEGORY_ALL := "all"
const CATEGORY_EQUIPMENT := "equipment"
const CATEGORY_FOOD := "food"
const CATEGORY_MATERIAL := "material"
const CATEGORY_SEED := "seed"
const CATEGORY_QUEST := "quest"
const CATEGORY_OTHER := "other"

const SORT_DEFAULT := "default"
const SORT_NAME := "name"
const SORT_QUANTITY := "quantity"
const SORT_CATEGORY := "category"

var _actor: CharacterEntity
var _stacks: Array[Dictionary] = []
var _visible_stacks: Array[Dictionary] = []
var _category: String = CATEGORY_ALL
var _sort_mode: String = SORT_DEFAULT
var _selected_item_id: String = ""
var _hovered_item_id: String = ""
var _target_character_id: String = ""
var _category_buttons: Dictionary = {}

var _panel: PanelContainer
var _gold_label: Label
var _grid: GridContainer
var _target_button: OptionButton
var _detail_title: Label
var _detail_meta: Label
var _detail_description: Label
var _detail_effects: Label
var _action_row: HBoxContainer
var _empty_label: Label
var _sort_button: OptionButton


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_ui()


func open_for_actor(actor: CharacterEntity) -> void:
	var previous_target_id: String = _target_character_id
	_actor = actor
	visible = true
	_selected_item_id = ""
	_hovered_item_id = ""
	if previous_target_id.is_empty():
		_target_character_id = actor.character_id if actor != null and is_instance_valid(actor) else ""
	else:
		_target_character_id = previous_target_id
	refresh()


func close_panel() -> void:
	visible = false


func is_open() -> bool:
	return visible


func refresh() -> void:
	_stacks = _get_actor_inventory()
	_visible_stacks = _build_visible_stacks()
	_clear_missing_focus()
	_refresh_category_buttons()
	_refresh_target_button()
	_refresh_grid()
	_refresh_details(_get_display_stack())
	_update_header()


func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.name = "InventoryWindow"
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.custom_minimum_size = Vector2(880.0, 560.0)
	_panel.offset_left = -440.0
	_panel.offset_top = -280.0
	_panel.offset_right = 440.0
	_panel.offset_bottom = 280.0
	_panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.06, 0.07, 0.065, 0.94), Color(0.68, 0.72, 0.64, 0.42), 8))
	add_child(_panel)

	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	_panel.add_child(margin)

	var root: VBoxContainer = VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)

	root.add_child(_make_header())
	root.add_child(_make_filter_row())

	var body: HBoxContainer = HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 12)
	root.add_child(body)

	body.add_child(_make_grid_area())
	body.add_child(_make_detail_area())


func _make_header() -> Control:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)

	var title: Label = Label.new()
	title.text = "背包"
	title.add_theme_font_size_override("font_size", 22)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title)

	_gold_label = Label.new()
	_gold_label.text = "金币 0"
	_gold_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_gold_label)

	var close_button: Button = Button.new()
	close_button.text = "关闭"
	close_button.custom_minimum_size = Vector2(86.0, 34.0)
	close_button.pressed.connect(_request_close)
	row.add_child(close_button)
	return row


func _make_filter_row() -> Control:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var categories: Array[Dictionary] = [
		{ "id": CATEGORY_ALL, "label": "全部" },
		{ "id": CATEGORY_EQUIPMENT, "label": "装备" },
		{ "id": CATEGORY_FOOD, "label": "食物" },
		{ "id": CATEGORY_MATERIAL, "label": "材料" },
		{ "id": CATEGORY_SEED, "label": "种子" },
		{ "id": CATEGORY_QUEST, "label": "任务" },
		{ "id": CATEGORY_OTHER, "label": "其他" },
	]
	for category_value in categories:
		var category_data: Dictionary = category_value as Dictionary
		var button: Button = Button.new()
		button.text = str(category_data.get("label", ""))
		button.toggle_mode = true
		button.custom_minimum_size = Vector2(72.0, 32.0)
		var category_id: String = str(category_data.get("id", ""))
		button.pressed.connect(_on_category_pressed.bind(category_id))
		row.add_child(button)
		_category_buttons[category_id] = button

	var spacer: Control = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	var sort_label: Label = Label.new()
	sort_label.text = "整理"
	sort_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(sort_label)

	_sort_button = OptionButton.new()
	_sort_button.custom_minimum_size = Vector2(132.0, 32.0)
	_sort_button.add_item("默认顺序")
	_sort_button.set_item_metadata(0, SORT_DEFAULT)
	_sort_button.add_item("名称")
	_sort_button.set_item_metadata(1, SORT_NAME)
	_sort_button.add_item("数量")
	_sort_button.set_item_metadata(2, SORT_QUANTITY)
	_sort_button.add_item("分类")
	_sort_button.set_item_metadata(3, SORT_CATEGORY)
	_sort_button.item_selected.connect(_on_sort_selected)
	row.add_child(_sort_button)
	return row


func _make_grid_area() -> Control:
	var panel: PanelContainer = PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.02, 0.025, 0.022, 0.35), Color(0.8, 0.86, 0.75, 0.18), 6))

	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(margin)

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(scroll)

	_grid = GridContainer.new()
	_grid.columns = 7
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", 8)
	_grid.add_theme_constant_override("v_separation", 8)
	scroll.add_child(_grid)

	_empty_label = Label.new()
	_empty_label.text = "背包里还没有这一类物品。"
	_empty_label.visible = false
	_empty_label.modulate = Color(0.8, 0.8, 0.76)
	_empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_grid.add_child(_empty_label)
	return panel


func _make_detail_area() -> Control:
	var panel: PanelContainer = PanelContainer.new()
	panel.custom_minimum_size = Vector2(260.0, 0.0)
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.025, 0.03, 0.027, 0.72), Color(0.8, 0.86, 0.75, 0.24), 6))

	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(margin)

	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	margin.add_child(box)

	var target_row: HBoxContainer = HBoxContainer.new()
	target_row.add_theme_constant_override("separation", 8)
	box.add_child(target_row)

	var target_label: Label = Label.new()
	target_label.text = "对象"
	target_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	target_row.add_child(target_label)

	_target_button = OptionButton.new()
	_target_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_target_button.custom_minimum_size = Vector2(0.0, 32.0)
	_target_button.item_selected.connect(_on_target_selected)
	target_row.add_child(_target_button)

	_detail_title = Label.new()
	_detail_title.text = "选择一个物品"
	_detail_title.add_theme_font_size_override("font_size", 20)
	_detail_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_detail_title)

	_detail_meta = Label.new()
	_detail_meta.modulate = Color(0.74, 0.78, 0.72)
	_detail_meta.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_detail_meta)

	var separator: HSeparator = HSeparator.new()
	box.add_child(separator)

	_detail_description = Label.new()
	_detail_description.custom_minimum_size = Vector2(0.0, 70.0)
	_detail_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_detail_description)

	_detail_effects = Label.new()
	_detail_effects.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_detail_effects)

	_action_row = HBoxContainer.new()
	_action_row.add_theme_constant_override("separation", 8)
	_action_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(_action_row)
	return panel


func _refresh_grid() -> void:
	_clear_children(_grid)
	if _visible_stacks.is_empty():
		_empty_label = Label.new()
		_empty_label.text = "背包里还没有这一类物品。"
		_empty_label.modulate = Color(0.8, 0.8, 0.76)
		_grid.add_child(_empty_label)
		return

	for stack_value in _visible_stacks:
		var stack: Dictionary = stack_value as Dictionary
		_grid.add_child(_make_item_cell(stack))


func _make_item_cell(stack: Dictionary) -> Control:
	var cell: Control = Control.new()
	cell.custom_minimum_size = Vector2(66.0, 66.0)
	cell.mouse_filter = Control.MOUSE_FILTER_STOP
	var selected: bool = str(stack.get("item_id", "")) == _selected_item_id
	var hovered: bool = str(stack.get("item_id", "")) == _hovered_item_id

	var background: Panel = Panel.new()
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.add_theme_stylebox_override("panel", _make_panel_style(
		Color(0.12, 0.13, 0.115, 0.95),
		_get_cell_border_color(selected, hovered),
		5,
		2 if selected or hovered else 1
	))
	cell.add_child(background)

	cell.mouse_entered.connect(_on_stack_hovered.bind(stack, background))
	cell.mouse_exited.connect(_on_stack_unhovered.bind(str(stack.get("item_id", "")), background, selected))
	cell.gui_input.connect(_on_stack_gui_input.bind(stack))

	var icon_label: Label = Label.new()
	icon_label.text = _get_item_icon_text(stack)
	icon_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	icon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	icon_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_label.add_theme_font_size_override("font_size", 28)
	cell.add_child(icon_label)

	var quantity: int = int(stack.get("quantity", 0))
	if quantity > 1:
		var count_label: Label = Label.new()
		count_label.text = str(quantity)
		count_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		count_label.offset_left = -42.0
		count_label.offset_top = 4.0
		count_label.offset_right = -6.0
		count_label.offset_bottom = 26.0
		count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		count_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		count_label.add_theme_font_size_override("font_size", 20)
		count_label.add_theme_color_override("font_color", Color(0.96, 0.96, 0.88, 1.0))
		count_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.8))
		count_label.add_theme_constant_override("shadow_offset_x", 1)
		count_label.add_theme_constant_override("shadow_offset_y", 1)
		cell.add_child(count_label)

	var equipped_label_text: String = _get_equipped_badge_text(stack)
	if not equipped_label_text.is_empty():
		var equipped_label: Label = Label.new()
		equipped_label.text = equipped_label_text
		equipped_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		equipped_label.offset_left = -48.0
		equipped_label.offset_top = -22.0
		equipped_label.offset_right = -5.0
		equipped_label.offset_bottom = -4.0
		equipped_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		equipped_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		equipped_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		equipped_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		equipped_label.add_theme_font_size_override("font_size", 13)
		equipped_label.add_theme_color_override("font_color", Color(0.45, 0.86, 1.0, 1.0))
		equipped_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.85))
		equipped_label.add_theme_constant_override("shadow_offset_x", 1)
		equipped_label.add_theme_constant_override("shadow_offset_y", 1)
		cell.add_child(equipped_label)

	return cell


func _refresh_details(stack: Dictionary) -> void:
	_clear_children(_action_row)
	if stack.is_empty():
		_detail_title.text = "选择一个物品"
		_detail_meta.text = ""
		_detail_description.text = "从左侧背包格子中选择物品查看详情。"
		_detail_effects.text = ""
		return

	_detail_title.text = str(stack.get("display_name", stack.get("item_id", "未知物品")))
	_detail_meta.text = "%s / 数量 %d" % [
		_get_category_label(_get_stack_category(stack)),
		int(stack.get("quantity", 0)),
	]
	_detail_description.text = str(stack.get("description", ""))
	_detail_effects.text = _build_effect_text(stack)

	if bool(stack.get("is_usable", false)):
		_action_row.add_child(_make_action_button("使用", "UseItemAction", {
			"item_id": str(stack.get("item_id", "")),
			"target_character_id": _target_character_id,
		}))
	if bool(stack.get("equippable", false)):
		_action_row.add_child(_make_action_button("装备", "EquipItemAction", {
			"item_id": str(stack.get("item_id", "")),
			"slot_id": str(stack.get("equipment_slot", "")),
			"target_character_id": _target_character_id,
		}))

	if _action_row.get_child_count() == 0:
		var label: Label = Label.new()
		label.text = "暂无可直接执行的操作。"
		label.modulate = Color(0.72, 0.74, 0.7)
		_action_row.add_child(label)


func _make_action_button(label_text: String, action_type: String, target: Dictionary) -> Button:
	var button: Button = Button.new()
	button.text = label_text
	button.custom_minimum_size = Vector2(88.0, 34.0)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(_on_action_pressed.bind(action_type, target))
	return button


func _build_visible_stacks() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for stack_value in _stacks:
		var stack: Dictionary = stack_value as Dictionary
		if _category != CATEGORY_ALL and _get_stack_category(stack) != _category:
			continue
		result.append(stack)

	match _sort_mode:
		SORT_NAME:
			result.sort_custom(Callable(self, "_sort_by_name"))
		SORT_QUANTITY:
			result.sort_custom(Callable(self, "_sort_by_quantity"))
		SORT_CATEGORY:
			result.sort_custom(Callable(self, "_sort_by_category"))
		_:
			pass
	return result


func _get_actor_inventory() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if _actor == null or not is_instance_valid(_actor) or _actor.inventory == null:
		return result

	var assignment_map: Dictionary = _get_equipment_assignment_map()
	for stack_value in _actor.inventory.get_summary():
		var stack: Dictionary = stack_value as Dictionary
		var copied_stack: Dictionary = stack.duplicate(true)
		var item_id: String = str(copied_stack.get("item_id", ""))
		if assignment_map.has(item_id):
			copied_stack.merge(assignment_map[item_id] as Dictionary, true)
		result.append(copied_stack)
	return result


func _get_party_target_summaries() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for summary_value in PartySystem.get_party_summary():
		var summary: Dictionary = summary_value as Dictionary
		result.append(summary.duplicate(true))
	return result


func _get_equipment_assignment_map() -> Dictionary:
	var result: Dictionary = {}
	for summary_value in _get_party_target_summaries():
		var summary: Dictionary = summary_value as Dictionary
		var equipment: Dictionary = summary.get("equipment_slots", {}) as Dictionary
		for slot_data_value in equipment.values():
			var slot_data: Dictionary = slot_data_value as Dictionary
			if not bool(slot_data.get("is_player_override", false)):
				continue
			var item_id: String = str(slot_data.get("item_id", ""))
			if item_id.is_empty():
				continue
			result[item_id] = {
				"equipped_character_id": _member_id_from_summary(summary),
				"equipped_display_name": str(summary.get("display_name", item_id)),
			}
	return result


func _get_selected_stack() -> Dictionary:
	for stack_value in _visible_stacks:
		var stack: Dictionary = stack_value as Dictionary
		if str(stack.get("item_id", "")) == _selected_item_id:
			return stack
	return {}


func _get_hovered_stack() -> Dictionary:
	for stack_value in _visible_stacks:
		var stack: Dictionary = stack_value as Dictionary
		if str(stack.get("item_id", "")) == _hovered_item_id:
			return stack
	return {}


func _get_display_stack() -> Dictionary:
	var hovered_stack: Dictionary = _get_hovered_stack()
	if not hovered_stack.is_empty():
		return hovered_stack
	return _get_selected_stack()


func _clear_missing_focus() -> void:
	if not _selected_item_id.is_empty() and _get_selected_stack().is_empty():
		_selected_item_id = ""
	if not _hovered_item_id.is_empty() and _get_hovered_stack().is_empty():
		_hovered_item_id = ""


func _update_header() -> void:
	if _actor == null or not is_instance_valid(_actor):
		_gold_label.text = "金币 0"
		return
	_gold_label.text = "金币 %d" % BusinessSystem.get_currency(_actor.character_id)


func _refresh_category_buttons() -> void:
	for category_id_value in _category_buttons.keys():
		var category_id: String = str(category_id_value)
		var button: Button = _category_buttons[category_id] as Button
		if button != null:
			button.button_pressed = category_id == _category


func _refresh_target_button() -> void:
	if _target_button == null:
		return

	var members: Array[Dictionary] = _get_party_target_summaries()
	if members.is_empty() and _actor != null and is_instance_valid(_actor):
		members.append(_actor.get_summary())

	var has_selected_target: bool = false
	for member in members:
		if _member_id_from_summary(member) == _target_character_id:
			has_selected_target = true
			break
	if not has_selected_target and not members.is_empty():
		var first_member: Dictionary = members[0] as Dictionary
		_target_character_id = _member_id_from_summary(first_member)

	_target_button.clear()
	for member_value in members:
		var member: Dictionary = member_value as Dictionary
		var member_id: String = _member_id_from_summary(member)
		_target_button.add_item(str(member.get("display_name", member_id)))
		var index: int = _target_button.item_count - 1
		_target_button.set_item_metadata(index, member_id)
		if member_id == _target_character_id:
			_target_button.select(index)


func _member_id_from_summary(summary: Dictionary) -> String:
	return str(summary.get("party_member_id", summary.get("id", "")))


func _build_effect_text(stack: Dictionary) -> String:
	var lines: PackedStringArray = PackedStringArray()
	var bonuses: Dictionary = stack.get("attribute_bonuses", {}) as Dictionary
	if not bonuses.is_empty():
		lines.append("属性：%s" % _format_bonuses(bonuses))
	var slot_id: String = str(stack.get("equipment_slot", ""))
	if not slot_id.is_empty():
		lines.append("装备槽：%s" % _slot_label(slot_id))
	if bool(stack.get("is_usable", false)):
		lines.append("可使用")
	if bool(stack.get("is_usable", false)) and _get_stack_category(stack) == CATEGORY_FOOD:
		lines.append("默认恢复生命")
	var equipped_display_name: String = str(stack.get("equipped_display_name", ""))
	if not equipped_display_name.is_empty():
		lines.append("装备于：%s" % equipped_display_name)
	if lines.is_empty():
		return ""
	return "\n".join(lines)


func _format_bonuses(bonuses: Dictionary) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for key in bonuses.keys():
		var amount: int = int(bonuses[key])
		var prefix: String = "+" if amount >= 0 else ""
		parts.append("%s %s%d" % [_attribute_label(str(key)), prefix, amount])
	return "，".join(parts)


func _get_stack_category(stack: Dictionary) -> String:
	var item_type: String = str(stack.get("item_type", "misc"))
	if bool(stack.get("equippable", false)) or item_type == "equipment":
		return CATEGORY_EQUIPMENT
	match item_type:
		"consumable", "food":
			return CATEGORY_FOOD
		"material":
			return CATEGORY_MATERIAL
		"seed":
			return CATEGORY_SEED
		"quest", "key":
			return CATEGORY_QUEST
		_:
			return CATEGORY_OTHER


func _get_item_icon_text(stack: Dictionary) -> String:
	match _get_stack_category(stack):
		CATEGORY_EQUIPMENT:
			return "剑"
		CATEGORY_FOOD:
			return "食"
		CATEGORY_MATERIAL:
			return "材"
		CATEGORY_SEED:
			return "种"
		CATEGORY_QUEST:
			return "钥"
		_:
			var name: String = str(stack.get("display_name", stack.get("item_id", "?")))
			return name.substr(0, 1)


func _get_equipped_badge_text(stack: Dictionary) -> String:
	var display_name: String = str(stack.get("equipped_display_name", ""))
	if display_name.is_empty():
		return ""
	if display_name.length() > 4:
		return display_name.substr(0, 4)
	return display_name


func _get_category_label(category_id: String) -> String:
	match category_id:
		CATEGORY_ALL:
			return "全部"
		CATEGORY_EQUIPMENT:
			return "装备"
		CATEGORY_FOOD:
			return "食物"
		CATEGORY_MATERIAL:
			return "材料"
		CATEGORY_SEED:
			return "种子"
		CATEGORY_QUEST:
			return "任务"
		_:
			return "其他"


func _get_cell_border_color(selected: bool, hovered: bool) -> Color:
	if hovered:
		return Color(0.92, 0.95, 0.72, 0.9)
	if selected:
		return Color(0.42, 0.8, 1.0, 0.85)
	return Color(0.78, 0.82, 0.72, 0.28)


func _attribute_label(attribute_id: String) -> String:
	match attribute_id:
		"strength":
			return "力量"
		"agility":
			return "敏捷"
		"intellect":
			return "智力"
		"vitality":
			return "体质"
		"max_hp":
			return "生命"
		"action_points":
			return "行动点"
		_:
			return attribute_id


func _slot_label(slot_id: String) -> String:
	match slot_id:
		"weapon":
			return "武器"
		"offhand":
			return "副手"
		"head":
			return "头部"
		"body":
			return "身体"
		"accessory":
			return "饰品"
		"tool":
			return "工具"
		_:
			return slot_id


func _sort_by_name(a: Dictionary, b: Dictionary) -> bool:
	return str(a.get("display_name", a.get("item_id", ""))) < str(b.get("display_name", b.get("item_id", "")))


func _sort_by_quantity(a: Dictionary, b: Dictionary) -> bool:
	var left: int = int(a.get("quantity", 0))
	var right: int = int(b.get("quantity", 0))
	if left == right:
		return _sort_by_name(a, b)
	return left > right


func _sort_by_category(a: Dictionary, b: Dictionary) -> bool:
	var left_category: String = _get_stack_category(a)
	var right_category: String = _get_stack_category(b)
	if left_category == right_category:
		return _sort_by_name(a, b)
	return _category_order(left_category) < _category_order(right_category)


func _category_order(category_id: String) -> int:
	match category_id:
		CATEGORY_EQUIPMENT:
			return 0
		CATEGORY_FOOD:
			return 1
		CATEGORY_MATERIAL:
			return 2
		CATEGORY_SEED:
			return 3
		CATEGORY_QUEST:
			return 4
		_:
			return 5


func _on_category_pressed(category_id: String) -> void:
	_category = category_id
	_selected_item_id = ""
	_hovered_item_id = ""
	refresh()


func _on_sort_selected(index: int) -> void:
	_sort_mode = str(_sort_button.get_item_metadata(index))
	refresh()


func _on_target_selected(index: int) -> void:
	_target_character_id = str(_target_button.get_item_metadata(index))
	_refresh_details(_get_display_stack())


func _on_stack_hovered(stack: Dictionary, background: Panel) -> void:
	_hovered_item_id = str(stack.get("item_id", ""))
	if background != null and is_instance_valid(background):
		background.add_theme_stylebox_override("panel", _make_panel_style(
			Color(0.12, 0.13, 0.115, 0.95),
			_get_cell_border_color(false, true),
			5,
			2
		))
	_refresh_details(_get_display_stack())


func _on_stack_unhovered(item_id: String, background: Panel, selected: bool) -> void:
	if _hovered_item_id != item_id:
		return
	_hovered_item_id = ""
	if background != null and is_instance_valid(background):
		background.add_theme_stylebox_override("panel", _make_panel_style(
			Color(0.12, 0.13, 0.115, 0.95),
			_get_cell_border_color(selected, false),
			5,
			2 if selected else 1
		))
	_refresh_details(_get_display_stack())


func _on_stack_gui_input(event: InputEvent, stack: Dictionary) -> void:
	if event is InputEventMouseButton:
		var mouse_event: InputEventMouseButton = event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
			_selected_item_id = str(stack.get("item_id", ""))
			_refresh_grid()
			_refresh_details(_get_display_stack())
			get_viewport().set_input_as_handled()


func _on_action_pressed(action_type: String, target: Dictionary) -> void:
	var action_target: Dictionary = target.duplicate(true)
	match action_type:
		"UseItemAction", "EquipItemAction":
			action_target["target_character_id"] = _target_character_id
	inventory_action_requested.emit(action_type, action_target)


func _request_close() -> void:
	close_requested.emit()


func _make_panel_style(bg_color: Color, border_color: Color, radius: int, border_width: int = 1) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = bg_color
	style.border_color = border_color
	style.border_width_left = border_width
	style.border_width_top = border_width
	style.border_width_right = border_width
	style.border_width_bottom = border_width
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	return style


func _clear_children(parent: Node) -> void:
	for child in parent.get_children():
		child.queue_free()

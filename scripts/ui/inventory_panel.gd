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
const ITEM_CELL_SCENE := preload("res://scenes/ui/components/inventory_item_cell.tscn")
const ACTION_BUTTON_SCENE := preload("res://scenes/ui/components/action_button.tscn")
const UI_LABEL_SCENE := preload("res://scenes/ui/components/ui_label.tscn")

var _actor: CharacterEntity
var _stacks: Array[Dictionary] = []
var _visible_stacks: Array[Dictionary] = []
var _category: String = CATEGORY_ALL
var _sort_mode: String = SORT_DEFAULT
var _selected_item_id: String = ""
var _hovered_item_id: String = ""
var _target_character_id: String = ""
var _category_buttons: Dictionary = {}

@onready var _panel: PanelContainer = $InventoryWindow
@onready var _gold_label: Label = $InventoryWindow/Margin/Root/Header/GoldLabel
@onready var _grid: GridContainer = $InventoryWindow/Margin/Root/Body/GridPanel/Margin/Scroll/Grid
@onready var _target_button: OptionButton = $InventoryWindow/Margin/Root/Body/DetailPanel/Margin/Box/TargetRow/TargetButton
@onready var _detail_title: Label = $InventoryWindow/Margin/Root/Body/DetailPanel/Margin/Box/DetailTitle
@onready var _detail_meta: Label = $InventoryWindow/Margin/Root/Body/DetailPanel/Margin/Box/DetailMeta
@onready var _detail_description: Label = $InventoryWindow/Margin/Root/Body/DetailPanel/Margin/Box/DetailDescription
@onready var _detail_effects: Label = $InventoryWindow/Margin/Root/Body/DetailPanel/Margin/Box/DetailEffects
@onready var _action_row: HBoxContainer = $InventoryWindow/Margin/Root/Body/DetailPanel/Margin/Box/ActionRow
@onready var _sort_button: OptionButton = $InventoryWindow/Margin/Root/FilterRow/SortButton
var _empty_label: Label


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	$InventoryWindow/Margin/Root/Header/CloseButton.pressed.connect(_request_close)
	_target_button.item_selected.connect(_on_target_selected)
	_sort_button.item_selected.connect(_on_sort_selected)
	var category_nodes := {
		CATEGORY_ALL: $InventoryWindow/Margin/Root/FilterRow/AllButton,
		CATEGORY_EQUIPMENT: $InventoryWindow/Margin/Root/FilterRow/EquipmentButton,
		CATEGORY_FOOD: $InventoryWindow/Margin/Root/FilterRow/FoodButton,
		CATEGORY_MATERIAL: $InventoryWindow/Margin/Root/FilterRow/MaterialButton,
		CATEGORY_SEED: $InventoryWindow/Margin/Root/FilterRow/SeedButton,
		CATEGORY_QUEST: $InventoryWindow/Margin/Root/FilterRow/QuestButton,
		CATEGORY_OTHER: $InventoryWindow/Margin/Root/FilterRow/OtherButton,
	}
	for category_id in category_nodes:
		var button: Button = category_nodes[category_id] as Button
		button.pressed.connect(_on_category_pressed.bind(str(category_id)))
		_category_buttons[category_id] = button
	for index in range(_sort_button.item_count):
		_sort_button.set_item_metadata(index, [SORT_DEFAULT, SORT_NAME, SORT_QUANTITY, SORT_CATEGORY][index])


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


func _refresh_grid() -> void:
	_clear_children(_grid)
	if _visible_stacks.is_empty():
		_empty_label = UI_LABEL_SCENE.instantiate() as Label
		_empty_label.text = "背包里还没有这一类物品。"
		_empty_label.modulate = Color(0.8, 0.8, 0.76)
		_grid.add_child(_empty_label)
		return

	for stack_value in _visible_stacks:
		var stack: Dictionary = stack_value as Dictionary
		_grid.add_child(_make_item_cell(stack))


func _make_item_cell(stack: Dictionary) -> Control:
	var cell: Control = ITEM_CELL_SCENE.instantiate() as Control
	var selected: bool = str(stack.get("item_id", "")) == _selected_item_id
	var hovered: bool = str(stack.get("item_id", "")) == _hovered_item_id

	var background: Panel = cell.get_node("Background") as Panel
	background.add_theme_stylebox_override("panel", _make_panel_style(
		Color(0.12, 0.13, 0.115, 0.95),
		_get_cell_border_color(selected, hovered),
		5,
		2 if selected or hovered else 1
	))
	cell.mouse_entered.connect(_on_stack_hovered.bind(stack, background))
	cell.mouse_exited.connect(_on_stack_unhovered.bind(str(stack.get("item_id", "")), background, selected))
	cell.gui_input.connect(_on_stack_gui_input.bind(stack))

	var icon_label: Label = cell.get_node("Icon") as Label
	icon_label.text = _get_item_icon_text(stack)

	var quantity: int = int(stack.get("quantity", 0))
	var count_label: Label = cell.get_node("Count") as Label
	count_label.visible = quantity > 1
	count_label.text = str(quantity)

	var equipped_label_text: String = _get_equipped_badge_text(stack)
	var equipped_label: Label = cell.get_node("Equipped") as Label
	equipped_label.visible = not equipped_label_text.is_empty()
	equipped_label.text = equipped_label_text

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
		var label: Label = UI_LABEL_SCENE.instantiate() as Label
		label.text = "暂无可直接执行的操作。"
		label.modulate = Color(0.72, 0.74, 0.7)
		_action_row.add_child(label)


func _make_action_button(label_text: String, action_type: String, target: Dictionary) -> Button:
	var button: Button = ACTION_BUTTON_SCENE.instantiate() as Button
	button.text = label_text
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

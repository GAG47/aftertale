class_name BattleHudPanel
extends Control

signal wait_requested()
signal flee_requested()
signal skill_selected(skill_id: String)
signal move_selected()
signal turn_unit_selected(character_id: String)

enum MenuMode { COMMANDS, SKILLS, STATUS }

@onready var unit_panel: PanelContainer = $UnitPanel
@onready var turn_order_panel: PanelContainer = $TurnOrderPanel
@onready var turn_order_list: VBoxContainer = $TurnOrderPanel/TurnOrderMargin/TurnOrderBox/TurnOrderScroll/TurnOrderList
@onready var title_label: Label = $UnitPanel/UnitMargin/UnitBox/TitleLabel
@onready var current_label: Label = $UnitPanel/UnitMargin/UnitBox/CurrentLabel
@onready var current_hp_bar: ProgressBar = $UnitPanel/UnitMargin/UnitBox/CurrentVitals/HPBar
@onready var current_ap_bar: ProgressBar = $UnitPanel/UnitMargin/UnitBox/CurrentVitals/APBar
@onready var unit_status_label: Label = $UnitPanel/UnitMargin/UnitBox/UnitStatusLabel
@onready var command_panel: PanelContainer = $CommandPanel
@onready var command_hint_label: Label = $CommandPanel/CommandMargin/CommandBox/CommandHintLabel
@onready var move_button: Button = $CommandPanel/CommandMargin/CommandBox/MoveButton
@onready var skills_button: Button = $CommandPanel/CommandMargin/CommandBox/SkillsButton
@onready var wait_button: Button = $CommandPanel/CommandMargin/CommandBox/WaitButton
@onready var status_button: Button = $CommandPanel/CommandMargin/CommandBox/StatusButton
@onready var flee_button: Button = $CommandPanel/CommandMargin/CommandBox/FleeButton
@onready var skill_panel: PanelContainer = $SkillPanel
@onready var skill_title_label: Label = $SkillPanel/SkillMargin/SkillBox/SkillTitleLabel
@onready var skill_detail_label: Label = $SkillPanel/SkillMargin/SkillBox/SkillDetailLabel
@onready var skill_list: VBoxContainer = $SkillPanel/SkillMargin/SkillBox/SkillScroll/SkillList
@onready var skill_back_button: Button = $SkillPanel/SkillMargin/SkillBox/SkillBackButton
@onready var status_panel: PanelContainer = $StatusPanel
@onready var status_detail_label: Label = $StatusPanel/StatusMargin/StatusBox/StatusDetailLabel
@onready var status_back_button: Button = $StatusPanel/StatusMargin/StatusBox/StatusBackButton

var _menu_mode: int = MenuMode.COMMANDS
var _current_summary: Dictionary = {}
var _skill_summaries: Array = []
var _selected_skill_id: String = ""
var _tactical_mode: String = "move"
var _can_control: bool = false
var _selectable_turn_unit_ids: Array[String] = []


func _ready() -> void:
	visible = false
	move_button.pressed.connect(_on_move_pressed)
	skills_button.pressed.connect(_on_skills_pressed)
	wait_button.pressed.connect(_on_wait_pressed)
	status_button.pressed.connect(_on_status_pressed)
	flee_button.pressed.connect(_on_flee_pressed)
	skill_back_button.pressed.connect(_on_back_to_commands_pressed)
	status_back_button.pressed.connect(_on_back_to_commands_pressed)


func show_battle_summary(summary: Dictionary, can_control: bool, skill_summaries: Array, selected_skill_id: String, tactical_mode: String = "move", reopen_skill_menu: bool = false) -> void:
	if summary.is_empty() or not bool(summary.get("active", false)):
		hide_panel()
		return

	visible = true
	_current_summary = summary.duplicate(true)
	_skill_summaries = skill_summaries.duplicate(true)
	_selected_skill_id = selected_skill_id
	_tactical_mode = tactical_mode
	_can_control = can_control
	if not can_control:
		_menu_mode = MenuMode.COMMANDS
	elif reopen_skill_menu:
		_menu_mode = MenuMode.SKILLS

	_refresh_unit_card()
	_refresh_turn_order()
	_refresh_command_menu()
	_refresh_skill_menu()
	_refresh_status_menu()
	_sync_menu_visibility()


func hide_panel() -> void:
	visible = false
	_menu_mode = MenuMode.COMMANDS
	_selectable_turn_unit_ids.clear()


func _input(event: InputEvent) -> void:
	if not visible or not _can_control:
		return
	if _menu_mode == MenuMode.COMMANDS:
		return
	if not (event is InputEventMouseButton):
		return

	var mouse_event: InputEventMouseButton = event as InputEventMouseButton
	if mouse_event.button_index != MOUSE_BUTTON_RIGHT or not mouse_event.pressed:
		return

	get_viewport().set_input_as_handled()
	_return_to_commands()


func _refresh_unit_card() -> void:
	var round_number: int = int(_current_summary.get("round", 1))
	title_label.text = "战斗 第 %d 回合" % round_number

	var current_unit: Dictionary = _current_summary.get("current_unit", {}) as Dictionary
	if current_unit.is_empty():
		current_label.text = "当前单位：无"
		unit_status_label.text = ""
		_set_bar(current_hp_bar, 0, 1, "HP 0/0")
		_set_bar(current_ap_bar, 0, 1, "AP 0/0")
		return

	var unit_name: String = str(current_unit.get("display_name", current_unit.get("character_id", "未知")))
	current_label.text = "%s\n%s行动" % [unit_name, "玩家" if _can_control else "敌方"]
	unit_status_label.text = "HP %d/%d   AP %d/%d   SPD %d%s" % [
		int(current_unit.get("hp", 0)),
		int(current_unit.get("max_hp", 0)),
		int(current_unit.get("action_points", 0)),
		int(current_unit.get("max_action_points", 0)),
		int(current_unit.get("speed", 0)),
		_get_status_suffix(current_unit),
	]
	if int(current_unit.get("max_mp", 0)) > 0:
		unit_status_label.text = "HP %d/%d   MP %d/%d   AP %d/%d   SPD %d%s" % [
			int(current_unit.get("hp", 0)),
			int(current_unit.get("max_hp", 0)),
			int(current_unit.get("mp", 0)),
			int(current_unit.get("max_mp", 0)),
			int(current_unit.get("action_points", 0)),
			int(current_unit.get("max_action_points", 0)),
			int(current_unit.get("speed", 0)),
			_get_status_suffix(current_unit),
		]
	_set_bar(
		current_hp_bar,
		int(current_unit.get("hp", 0)),
		max(1, int(current_unit.get("max_hp", 1))),
		"HP %d/%d" % [int(current_unit.get("hp", 0)), int(current_unit.get("max_hp", 0))]
	)
	_set_bar(
		current_ap_bar,
		int(current_unit.get("action_points", 0)),
		max(1, int(current_unit.get("max_action_points", 1))),
		"AP %d/%d" % [int(current_unit.get("action_points", 0)), int(current_unit.get("max_action_points", 0))]
	)


func _refresh_command_menu() -> void:
	var is_busy: bool = bool(_current_summary.get("presentation_pending", false))
	command_hint_label.text = "行动演出中" if is_busy else ("选择行动" if _can_control else "敌方行动中")
	move_button.disabled = not _can_control or is_busy
	skills_button.disabled = not _can_control or is_busy
	wait_button.disabled = not _can_control or is_busy
	status_button.disabled = _current_summary.is_empty()
	flee_button.disabled = not _can_control or is_busy


func _refresh_turn_order() -> void:
	_clear_children(turn_order_list)
	_selectable_turn_unit_ids.clear()

	var selectable_units: Array = _current_summary.get("selectable_player_units", []) as Array
	for unit_value in selectable_units:
		var unit: Dictionary = unit_value as Dictionary
		var unit_id: String = str(unit.get("character_id", ""))
		if not unit_id.is_empty():
			_selectable_turn_unit_ids.append(unit_id)

	var turn_order: Array = _current_summary.get("turn_order", []) as Array
	if turn_order.is_empty():
		var empty_label: Label = Label.new()
		empty_label.text = "暂无顺序"
		empty_label.modulate = Color(0.75, 0.75, 0.75)
		turn_order_list.add_child(empty_label)
		return

	for order_value in turn_order:
		var unit: Dictionary = order_value as Dictionary
		var unit_id: String = str(unit.get("character_id", ""))
		var can_select_unit: bool = _selectable_turn_unit_ids.has(unit_id) and not bool(_current_summary.get("presentation_pending", false))
		if can_select_unit:
			var button: Button = Button.new()
			button.custom_minimum_size = Vector2(0.0, 34.0)
			button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			button.text = _build_turn_order_text(unit)
			button.tooltip_text = "选择该角色先行动"
			button.disabled = bool(unit.get("is_current", false))
			button.pressed.connect(_on_turn_unit_pressed.bind(unit_id))
			turn_order_list.add_child(button)
		else:
			var label: Label = Label.new()
			label.custom_minimum_size = Vector2(0.0, 30.0)
			label.text = _build_turn_order_text(unit)
			label.modulate = _get_turn_order_color(str(unit.get("team", "")), bool(unit.get("is_current", false)))
			label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			turn_order_list.add_child(label)


func _refresh_skill_menu() -> void:
	_clear_children(skill_list)
	skill_title_label.text = "技能"
	skill_detail_label.text = _build_selected_skill_detail()
	if _skill_summaries.is_empty():
		var label: Label = Label.new()
		label.text = "没有可用技能"
		label.modulate = Color(0.78, 0.78, 0.78)
		skill_list.add_child(label)
		return

	for skill_value in _skill_summaries:
		var skill: Dictionary = skill_value as Dictionary
		var skill_id: String = str(skill.get("id", ""))
		var button: Button = Button.new()
		button.custom_minimum_size = Vector2(0.0, 38.0)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.text = "%s%s     AP %d" % [
			"◆ " if skill_id == _selected_skill_id else "",
			str(skill.get("display_name", skill_id)),
			int(skill.get("ap_cost", 0)),
		]
		var mp_cost: int = int(skill.get("mp_cost", 0))
		if mp_cost > 0:
			button.text += "   MP %d" % mp_cost
		var cooldown: int = int(skill.get("cooldown_remaining", 0))
		if cooldown > 0:
			button.text += "   CD %d" % cooldown
		button.disabled = not _can_control or not bool(skill.get("can_use", false))
		button.tooltip_text = _build_skill_detail(skill)
		button.pressed.connect(_on_skill_pressed.bind(skill_id))
		skill_list.add_child(button)


func _refresh_status_menu() -> void:
	var current_unit: Dictionary = _current_summary.get("current_unit", {}) as Dictionary
	if current_unit.is_empty():
		status_detail_label.text = "没有当前单位。"
		return

	status_detail_label.text = "%s\n%s\nHP %d/%d\nAP %d/%d\nSPD %d\n状态：%s" % [
		str(current_unit.get("display_name", current_unit.get("character_id", "未知"))),
		_translate_team(str(current_unit.get("team", ""))),
		int(current_unit.get("hp", 0)),
		int(current_unit.get("max_hp", 0)),
		int(current_unit.get("action_points", 0)),
		int(current_unit.get("max_action_points", 0)),
		int(current_unit.get("speed", 0)),
		_get_status_text(current_unit),
	]
	if int(current_unit.get("max_mp", 0)) > 0:
		status_detail_label.text += "\nMP %d/%d" % [
			int(current_unit.get("mp", 0)),
			int(current_unit.get("max_mp", 0)),
		]


func _sync_menu_visibility() -> void:
	var is_skill_aiming: bool = _can_control and _tactical_mode == "skill"
	command_panel.visible = not is_skill_aiming and _menu_mode == MenuMode.COMMANDS
	skill_panel.visible = not is_skill_aiming and _menu_mode == MenuMode.SKILLS
	status_panel.visible = not is_skill_aiming and _menu_mode == MenuMode.STATUS


func _on_move_pressed() -> void:
	command_hint_label.text = "蓝色格可移动。用方向键移动，或点击蓝色格。"
	move_selected.emit()


func _on_skills_pressed() -> void:
	_menu_mode = MenuMode.SKILLS
	_sync_menu_visibility()


func _on_status_pressed() -> void:
	_menu_mode = MenuMode.STATUS
	_sync_menu_visibility()


func _on_back_to_commands_pressed() -> void:
	_return_to_commands()


func _return_to_commands() -> void:
	_menu_mode = MenuMode.COMMANDS
	_sync_menu_visibility()
	move_selected.emit()


func _on_wait_pressed() -> void:
	wait_requested.emit()


func _on_flee_pressed() -> void:
	flee_requested.emit()


func _on_skill_pressed(skill_id: String) -> void:
	_menu_mode = MenuMode.COMMANDS
	_sync_menu_visibility()
	skill_selected.emit(skill_id)


func _on_turn_unit_pressed(character_id: String) -> void:
	if character_id.is_empty():
		return
	turn_unit_selected.emit(character_id)


func _build_turn_order_text(unit: Dictionary) -> String:
	var prefix: String = "▶ " if bool(unit.get("is_current", false)) else "   "
	var team_label: String = "我" if str(unit.get("team", "")) == "player" else "敌"
	return "%s%s｜%s  SPD %d  AP %d" % [
		prefix,
		team_label,
		str(unit.get("display_name", unit.get("character_id", "未知"))),
		int(unit.get("speed", 0)),
		int(unit.get("action_points", 0)),
	]


func _get_turn_order_color(team: String, is_current: bool) -> Color:
	if is_current:
		return Color(1.0, 0.88, 0.32)
	if team == "player":
		return Color(0.70, 0.86, 1.0)
	return Color(1.0, 0.70, 0.66)


func _set_bar(bar: ProgressBar, value: int, max_value: int, label_text: String) -> void:
	bar.min_value = 0
	bar.max_value = max(1, max_value)
	bar.value = clampi(value, 0, max(1, max_value))
	bar.show_percentage = false
	bar.tooltip_text = label_text


func _build_selected_skill_detail() -> String:
	for skill_value in _skill_summaries:
		var skill: Dictionary = skill_value as Dictionary
		if str(skill.get("id", "")) == _selected_skill_id:
			return _build_skill_detail(skill)

	return "选择技能后，地图会显示可用目标范围。"


func _build_skill_detail(skill: Dictionary) -> String:
	if skill.is_empty():
		return ""

	var description: String = str(skill.get("description", ""))
	var details: String = "%s / 范围 %d / %s" % [
		_target_type_label(str(skill.get("target_type", "enemy"))),
		int(skill.get("range", 0)),
		_area_label(skill),
	]
	var mp_cost: int = int(skill.get("mp_cost", 0))
	if mp_cost > 0:
		details += " / MP %d" % mp_cost
	var failure_reason: String = str(skill.get("failure_reason", ""))
	if not failure_reason.is_empty():
		details += "\n暂不可用：%s" % failure_reason
	if description.is_empty():
		return details
	return "%s\n%s" % [description, details]


func _target_type_label(target_type: String) -> String:
	match target_type:
		"self":
			return "自身"
		"enemy":
			return "敌方"
		"ally":
			return "友方"
		"ally_or_self":
			return "友方/自身"
		_:
			return target_type


func _area_label(skill: Dictionary) -> String:
	var area: String = str(skill.get("area", "single"))
	if area == "radius":
		return "半径%d" % int(skill.get("radius", 0))
	return "单体"


func _get_status_text(unit: Dictionary) -> String:
	var status_text: String = str(unit.get("status_text", ""))
	if status_text.is_empty():
		return "无"
	return status_text


func _get_status_suffix(unit: Dictionary) -> String:
	var status_text: String = _get_status_text(unit)
	if status_text == "无":
		return ""
	return "   %s" % status_text


func _clear_children(parent: Node) -> void:
	for child in parent.get_children():
		child.queue_free()


func _translate_team(team: String) -> String:
	match team:
		"player":
			return "我方"
		"enemy":
			return "敌方"
		_:
			return team

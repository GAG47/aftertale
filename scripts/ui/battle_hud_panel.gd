class_name BattleHudPanel
extends PanelContainer

signal wait_requested()
signal flee_requested()
signal skill_selected(skill_id: String)

@onready var title_label: Label = $MarginContainer/RootRow/UnitPanel/UnitMargin/UnitBox/TitleLabel
@onready var current_label: Label = $MarginContainer/RootRow/UnitPanel/UnitMargin/UnitBox/CurrentLabel
@onready var current_hp_bar: ProgressBar = $MarginContainer/RootRow/UnitPanel/UnitMargin/UnitBox/CurrentVitals/HPBar
@onready var current_ap_bar: ProgressBar = $MarginContainer/RootRow/UnitPanel/UnitMargin/UnitBox/CurrentVitals/APBar
@onready var units_label: Label = $MarginContainer/RootRow/UnitPanel/UnitMargin/UnitBox/UnitsLabel
@onready var hint_label: Label = $MarginContainer/RootRow/SkillPanel/SkillMargin/SkillBox/HintLabel
@onready var skill_detail_label: Label = $MarginContainer/RootRow/SkillPanel/SkillMargin/SkillBox/SkillDetailLabel
@onready var skill_list: HBoxContainer = $MarginContainer/RootRow/SkillPanel/SkillMargin/SkillBox/SkillScroll/SkillList
@onready var wait_button: Button = $MarginContainer/RootRow/CommandPanel/CommandMargin/CommandBox/WaitButton
@onready var flee_button: Button = $MarginContainer/RootRow/CommandPanel/CommandMargin/CommandBox/FleeButton


func _ready() -> void:
	visible = false
	wait_button.pressed.connect(_on_wait_pressed)
	flee_button.pressed.connect(_on_flee_pressed)


func show_battle_summary(summary: Dictionary, can_control: bool, skill_summaries: Array, selected_skill_id: String) -> void:
	if summary.is_empty() or not bool(summary.get("active", false)):
		hide_panel()
		return

	visible = true
	var round_number: int = int(summary.get("round", 1))
	title_label.text = "战斗 第 %d 回合" % round_number

	var current_unit: Dictionary = summary.get("current_unit", {}) as Dictionary
	if current_unit.is_empty():
		current_label.text = "当前单位：无"
		_set_bar(current_hp_bar, 0, 1, "HP 0/0")
		_set_bar(current_ap_bar, 0, 1, "AP 0/0")
	else:
		current_label.text = "%s行动\n%s\nHP %d/%d  AP %d/%d" % [
			"玩家" if can_control else "敌方",
			str(current_unit.get("display_name", current_unit.get("character_id", "未知"))),
			int(current_unit.get("hp", 0)),
			int(current_unit.get("max_hp", 0)),
			int(current_unit.get("action_points", 0)),
			int(current_unit.get("max_action_points", 0)),
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

	hint_label.text = _build_action_hint(can_control, _get_selected_skill_name(skill_summaries, selected_skill_id))

	var unit_lines: PackedStringArray = PackedStringArray()
	var units: Array = summary.get("units", []) as Array
	for unit_value in units:
		var unit: Dictionary = unit_value as Dictionary
		var marker: String = " "
		if str(unit.get("character_id", "")) == str(current_unit.get("character_id", "")):
			marker = ">"
		var status_text: String = str(unit.get("status_text", ""))
		var status_suffix: String = ""
		if not status_text.is_empty():
			status_suffix = "  " + status_text
		var defeated_suffix: String = ""
		if bool(unit.get("defeated", false)):
			defeated_suffix = "  已倒下"
		elif bool(unit.get("fled", false)):
			defeated_suffix = "  已逃离"
		unit_lines.append("%s%s [%s] HP %d/%d AP %d/%d%s%s" % [
			marker,
			str(unit.get("display_name", unit.get("character_id", "未知"))),
			_translate_team(str(unit.get("team", "?"))),
			int(unit.get("hp", 0)),
			int(unit.get("max_hp", 0)),
			int(unit.get("action_points", 0)),
			int(unit.get("max_action_points", 0)),
			status_suffix,
			defeated_suffix,
		])

	units_label.text = _join_strings(unit_lines, "\n")
	_refresh_skill_buttons(skill_summaries, selected_skill_id, can_control)
	wait_button.disabled = not can_control
	flee_button.disabled = not can_control


func hide_panel() -> void:
	visible = false


func _on_wait_pressed() -> void:
	wait_requested.emit()


func _on_flee_pressed() -> void:
	flee_requested.emit()


func _refresh_skill_buttons(skill_summaries: Array, selected_skill_id: String, can_control: bool) -> void:
	_clear_children(skill_list)
	skill_detail_label.text = ""
	if skill_summaries.is_empty():
		var label: Label = Label.new()
		label.text = "没有技能"
		label.modulate = Color(0.78, 0.78, 0.78)
		skill_list.add_child(label)
		return

	for skill_value in skill_summaries:
		var skill: Dictionary = skill_value as Dictionary
		var skill_id: String = str(skill.get("id", ""))
		var button: Button = Button.new()
		button.custom_minimum_size = Vector2(126.0, 58.0)
		var selected: bool = skill_id == selected_skill_id
		var target_text: String = _target_type_label(str(skill.get("target_type", "enemy")))
		button.text = "%s%s\nAP %d  RNG %d\n%s%s" % [
			"◆ " if selected else "",
			str(skill.get("display_name", skill_id)),
			int(skill.get("ap_cost", 0)),
			int(skill.get("range", 0)),
			target_text,
			_area_label(skill).strip_edges(),
		]
		var cooldown: int = int(skill.get("cooldown_remaining", 0))
		if cooldown > 0:
			button.text += "  CD %d" % cooldown
		button.disabled = not can_control or not bool(skill.get("can_use", false))
		button.tooltip_text = _build_skill_tooltip(skill)
		button.pressed.connect(_on_skill_pressed.bind(skill_id))
		skill_list.add_child(button)

		if selected:
			skill_detail_label.text = _build_skill_detail(skill)


func _clear_children(parent: Node) -> void:
	for child in parent.get_children():
		child.queue_free()


func _on_skill_pressed(skill_id: String) -> void:
	skill_selected.emit(skill_id)


func _set_bar(bar: ProgressBar, value: int, max_value: int, label_text: String) -> void:
	bar.min_value = 0
	bar.max_value = max(1, max_value)
	bar.value = clampi(value, 0, max(1, max_value))
	bar.show_percentage = false
	bar.tooltip_text = label_text


func _build_action_hint(can_control: bool, selected_skill_name: String) -> String:
	if not can_control:
		return "敌方行动中"
	if selected_skill_name.is_empty():
		return "选择技能后点击目标格。蓝色移动，红色技能。"
	return "当前技能：%s    蓝色移动 / 红色使用技能" % selected_skill_name


func _get_selected_skill_name(skill_summaries: Array, selected_skill_id: String) -> String:
	for skill_value in skill_summaries:
		var skill: Dictionary = skill_value as Dictionary
		if str(skill.get("id", "")) == selected_skill_id:
			return str(skill.get("display_name", selected_skill_id))

	return selected_skill_id


func _build_skill_detail(skill: Dictionary) -> String:
	if skill.is_empty():
		return ""

	var pieces: PackedStringArray = PackedStringArray()
	pieces.append(str(skill.get("description", "")))
	pieces.append("目标：%s  范围：%d  区域：%s" % [
		_target_type_label(str(skill.get("target_type", "enemy"))),
		int(skill.get("range", 0)),
		_area_label(skill).strip_edges(),
	])
	var failure_reason: String = str(skill.get("failure_reason", ""))
	if not failure_reason.is_empty():
		pieces.append("暂不可用：%s" % failure_reason)
	return _join_strings(pieces, "\n")


func _build_skill_tooltip(skill: Dictionary) -> String:
	var text: String = _build_skill_detail(skill)
	if text.is_empty():
		return str(skill.get("display_name", skill.get("id", "")))
	return text


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
		return "  半径%d" % int(skill.get("radius", 0))
	return "  单体"


func _join_strings(values: PackedStringArray, separator: String) -> String:
	var result: String = ""
	for index in range(values.size()):
		if index > 0:
			result += separator
		result += values[index]

	return result


func _translate_team(team: String) -> String:
	match team:
		"player":
			return "我方"
		"enemy":
			return "敌方"
		_:
			return team

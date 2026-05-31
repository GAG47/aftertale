class_name BattleHudPanel
extends PanelContainer

signal wait_requested()
signal flee_requested()
signal skill_selected(skill_id: String)

@onready var title_label: Label = $MarginContainer/VBoxContainer/TitleLabel
@onready var current_label: Label = $MarginContainer/VBoxContainer/CurrentLabel
@onready var skill_list: VBoxContainer = $MarginContainer/VBoxContainer/SkillList
@onready var units_label: Label = $MarginContainer/VBoxContainer/UnitsLabel
@onready var wait_button: Button = $MarginContainer/VBoxContainer/ButtonRow/WaitButton
@onready var flee_button: Button = $MarginContainer/VBoxContainer/ButtonRow/FleeButton


func _ready() -> void:
	visible = false
	wait_button.pressed.connect(_on_wait_pressed)
	flee_button.pressed.connect(_on_flee_pressed)


func show_battle_summary(summary: Dictionary, can_control: bool, skill_summaries: Array, selected_skill_id: String) -> void:
	if summary.is_empty() or not bool(summary.get("active", false)):
		hide_panel()
		return

	visible = true
	title_label.text = "战斗  第 %d 回合" % int(summary.get("round", 1))

	var current_unit: Dictionary = summary.get("current_unit", {}) as Dictionary
	if current_unit.is_empty():
		current_label.text = "当前单位：无"
	else:
		current_label.text = "当前单位：%s  行动点 %d/%d  生命 %d/%d" % [
			str(current_unit.get("display_name", current_unit.get("character_id", "未知"))),
			int(current_unit.get("action_points", 0)),
			int(current_unit.get("max_action_points", 0)),
			int(current_unit.get("hp", 0)),
			int(current_unit.get("max_hp", 0)),
		]

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
		unit_lines.append("%s %s [%s] 生命 %d/%d 行动点 %d 速度 %d%s" % [
			marker,
			str(unit.get("display_name", unit.get("character_id", "未知"))),
			_translate_team(str(unit.get("team", "?"))),
			int(unit.get("hp", 0)),
			int(unit.get("max_hp", 0)),
			int(unit.get("action_points", 0)),
			int(unit.get("speed", 0)),
			status_suffix,
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
		button.custom_minimum_size = Vector2(0.0, 34.0)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.text = "%s（%d行动点）" % [
			str(skill.get("display_name", skill_id)),
			int(skill.get("ap_cost", 0)),
		]
		var cooldown: int = int(skill.get("cooldown_remaining", 0))
		if cooldown > 0:
			button.text += " 冷却%d" % cooldown
		if skill_id == selected_skill_id:
			button.text = "> " + button.text
		button.disabled = not can_control or not bool(skill.get("can_use", false))
		button.pressed.connect(_on_skill_pressed.bind(skill_id))
		skill_list.add_child(button)


func _clear_children(parent: Node) -> void:
	for child in parent.get_children():
		child.queue_free()


func _on_skill_pressed(skill_id: String) -> void:
	skill_selected.emit(skill_id)


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

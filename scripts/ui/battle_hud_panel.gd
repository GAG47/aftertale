class_name BattleHudPanel
extends Control

signal wait_requested()
signal flee_requested()
signal skill_selected(skill_id: String)
signal move_selected()
signal turn_unit_selected(character_id: String)

const MAX_SKILL_SLOTS := 4
const PORTRAIT_SIZE := 48.0
const TURN_ITEM_SCENE := preload("res://scenes/ui/components/battle_turn_item.tscn")
const STATUS_ICON_SCENE := preload("res://scenes/ui/components/status_icon.tscn")

@onready var turn_order_panel: PanelContainer = $TurnOrderPanel
@onready var turn_order_title: Label = $TurnOrderPanel/Margin/Box/Title
@onready var turn_order_list: VBoxContainer = $TurnOrderPanel/Margin/Box/Scroll/List
@onready var ai_debug_panel: PanelContainer = $AiDebugPanel
@onready var ai_debug_title_label: Label = $AiDebugPanel/Margin/Box/Title
@onready var ai_debug_detail_label: Label = $AiDebugPanel/Margin/Box/Scroll/Detail
@onready var _character_dock: Control = $CharacterDock
@onready var _portrait_texture_rect: TextureRect = $CharacterDock/PortraitFrame/Portrait
@onready var _portrait_fallback_label: Label = $CharacterDock/PortraitFrame/Fallback
@onready var _name_label: Label = $CharacterDock/NameLabel
@onready var _level_label: Label = $CharacterDock/LevelLabel
@onready var _status_icons: Control = $CharacterDock/StatusIcons
@onready var _hp_label: Label = $CharacterDock/HpLabel
@onready var _hp_bar: ProgressBar = $CharacterDock/HpBar
@onready var _attack_label: Label = $CharacterDock/AttackLabel
@onready var _defense_label: Label = $CharacterDock/DefenseLabel
@onready var _speed_label: Label = $CharacterDock/SpeedLabel
@onready var _skill_buttons: Array[Button] = [
	$SkillDock/Skill1,
	$SkillDock/Skill2,
	$SkillDock/Skill3,
	$SkillDock/Skill4,
]
@onready var _mp_label: Label = $SkillDock/MpLabel
@onready var _mp_bar: ProgressBar = $SkillDock/MpBar
@onready var _ap_label: Label = $SkillDock/ApLabel
@onready var _round_label: Label = $SkillDock/RoundLabel
@onready var _end_turn_button: Button = $SkillDock/EndTurnButton
@onready var _ai_debug_button: Button = $SkillDock/AiDebugButton

var _current_summary: Dictionary = {}
var _skill_summaries: Array = []
var _selected_skill_id: String = ""
var _tactical_mode: String = "move"
var _can_control: bool = false
var _selectable_turn_unit_ids: Array[String] = []
var _portrait_texture_cache: Dictionary = {}


func _ready() -> void:
	visible = false
	for slot_index in range(_skill_buttons.size()):
		_skill_buttons[slot_index].pressed.connect(_on_skill_slot_pressed.bind(slot_index))
	_ai_debug_button.pressed.connect(toggle_ai_debug)
	_end_turn_button.pressed.connect(_on_end_turn_pressed)
	_style_turn_order()


func show_battle_summary(
	summary: Dictionary,
	can_control: bool,
	skill_summaries: Array,
	selected_skill_id: String,
	tactical_mode: String = "move",
	_reopen_skill_menu: bool = false
) -> void:
	if summary.is_empty() or not bool(summary.get("active", false)):
		hide_panel()
		return
	visible = true
	_current_summary = summary.duplicate(true)
	_skill_summaries.clear()
	for skill_index in range(mini(MAX_SKILL_SLOTS, skill_summaries.size())):
		_skill_summaries.append((skill_summaries[skill_index] as Dictionary).duplicate(true))
	_selected_skill_id = selected_skill_id
	_tactical_mode = tactical_mode
	_can_control = can_control
	_refresh_character_dock()
	_refresh_skill_dock()
	_refresh_turn_order()
	_refresh_ai_debug()


func hide_panel() -> void:
	visible = false
	_selectable_turn_unit_ids.clear()
	ai_debug_panel.visible = false


func toggle_ai_debug() -> void:
	ai_debug_panel.visible = not ai_debug_panel.visible
	_ai_debug_button.button_pressed = ai_debug_panel.visible
	if ai_debug_panel.visible:
		_refresh_ai_debug()


func _input(event: InputEvent) -> void:
	if not visible or not (event is InputEventKey):
		return
	var key_event := event as InputEventKey
	if key_event.pressed and not key_event.echo and key_event.keycode == KEY_F4:
		get_viewport().set_input_as_handled()
		toggle_ai_debug()


func _refresh_character_dock() -> void:
	var unit: Dictionary = _current_summary.get("current_unit", {}) as Dictionary
	_character_dock.visible = not unit.is_empty()
	if unit.is_empty():
		return
	_name_label.text = str(unit.get("display_name", unit.get("character_id", "未知")))
	_level_label.text = "LV.%d" % int(unit.get("level", 1))
	_refresh_status_icons(unit)
	_hp_label.text = "HP %d / %d" % [int(unit.get("hp", 0)), int(unit.get("max_hp", 0))]
	_hp_bar.max_value = max(1, int(unit.get("max_hp", 1)))
	_hp_bar.value = clampi(int(unit.get("hp", 0)), 0, int(_hp_bar.max_value))
	_attack_label.text = "攻击 %d" % int(unit.get("attack", 0))
	_defense_label.text = "防御 %d" % int(unit.get("defense", 0))
	_speed_label.text = "速度 %d" % int(unit.get("speed", 0))
	var texture := _get_full_portrait_texture(unit)
	_portrait_texture_rect.texture = texture
	_portrait_fallback_label.visible = texture == null
	_portrait_fallback_label.text = _portrait_fallback_text(unit)


func _refresh_skill_dock() -> void:
	var unit: Dictionary = _current_summary.get("current_unit", {}) as Dictionary
	var busy: bool = bool(_current_summary.get("presentation_pending", false))
	for slot_index in range(MAX_SKILL_SLOTS):
		var button: Button = _skill_buttons[slot_index]
		if slot_index >= _skill_summaries.size():
			button.text = "%d\n-" % (slot_index + 1)
			button.disabled = true
			button.tooltip_text = "空技能槽"
			continue
		var skill: Dictionary = _skill_summaries[slot_index] as Dictionary
		var skill_id: String = str(skill.get("id", ""))
		button.text = "%d\n%s" % [slot_index + 1, str(skill.get("display_name", skill_id))]
		button.disabled = not _can_control or busy or not bool(skill.get("can_use", false))
		button.tooltip_text = _build_skill_detail(skill)
		button.button_pressed = skill_id == _selected_skill_id and _tactical_mode == "skill"
	var mp: int = int(unit.get("mp", 0))
	var max_mp: int = max(1, int(unit.get("max_mp", 1)))
	_mp_label.text = "MP %d/%d" % [mp, int(unit.get("max_mp", 0))]
	_mp_bar.max_value = max_mp
	_mp_bar.value = clampi(mp, 0, max_mp)
	_ap_label.text = "AP %d/%d" % [int(unit.get("action_points", 0)), int(unit.get("max_action_points", 0))]
	_round_label.text = "TURN %d" % int(_current_summary.get("round", 1))
	_end_turn_button.disabled = not _can_control or busy


func _refresh_turn_order() -> void:
	_clear_children(turn_order_list)
	_selectable_turn_unit_ids.clear()
	for unit_value in _current_summary.get("selectable_player_units", []) as Array:
		var unit: Dictionary = unit_value as Dictionary
		var unit_id: String = str(unit.get("character_id", ""))
		if not unit_id.is_empty():
			_selectable_turn_unit_ids.append(unit_id)
	for order_value in _current_summary.get("turn_order", []) as Array:
		turn_order_list.add_child(_make_turn_portrait(order_value as Dictionary))


func _make_turn_portrait(unit: Dictionary) -> Button:
	var unit_id: String = str(unit.get("character_id", ""))
	var is_current: bool = bool(unit.get("is_current", false))
	var can_select: bool = _selectable_turn_unit_ids.has(unit_id) and not bool(_current_summary.get("presentation_pending", false))
	var button: Button = TURN_ITEM_SCENE.instantiate() as Button
	button.disabled = not can_select or is_current
	button.tooltip_text = _build_turn_tooltip(unit)
	button.text = _portrait_fallback_text(unit)
	var texture := _get_avatar_texture(unit)
	if texture != null:
		button.icon = texture
		button.expand_icon = true
		button.text = ""
	if can_select:
		button.pressed.connect(_on_turn_unit_pressed.bind(unit_id))
	return button


func _refresh_status_icons(unit: Dictionary) -> void:
	_clear_children(_status_icons)
	var icon_x: float = 0.0
	for status_value in (unit.get("status_effects", {}) as Dictionary).values():
		var status: Dictionary = status_value as Dictionary
		var label: Label = STATUS_ICON_SCENE.instantiate() as Label
		label.text = str(status.get("display_name", status.get("id", ""))).left(1)
		label.tooltip_text = str(status.get("display_name", status.get("id", "")))
		_status_icons.add_child(label)
		label.position = Vector2(icon_x, 0.0)
		label.size = Vector2(22.0, 22.0)
		icon_x += 25.0


func _refresh_ai_debug() -> void:
	var decisions: Array = _current_summary.get("recent_ai_decisions", []) as Array
	if decisions.is_empty():
		ai_debug_title_label.text = "AI 评分"
		ai_debug_detail_label.text = "暂无 AI 决策。"
		return
	var decision: Dictionary = decisions.back() as Dictionary
	var chosen: Dictionary = decision.get("chosen", {}) as Dictionary
	ai_debug_title_label.text = "%s / %s" % [str(decision.get("character_id", "AI")), str(decision.get("profile_id", "balanced"))]
	var lines := PackedStringArray()
	lines.append("选择：%s" % str(chosen.get("description", "")))
	lines.append("总分：%.1f   候选：%d" % [float(chosen.get("total_score", 0.0)), int(decision.get("candidate_count", 0))])
	for entry_value in chosen.get("score_breakdown", []) as Array:
		var entry: Dictionary = entry_value as Dictionary
		lines.append("%s  %+.1f" % [str(entry.get("label", entry.get("id", ""))), float(entry.get("weighted", 0.0))])
	ai_debug_detail_label.text = "\n".join(lines)


func _on_skill_slot_pressed(slot_index: int) -> void:
	if slot_index >= 0 and slot_index < _skill_summaries.size():
		var skill_id: String = str((_skill_summaries[slot_index] as Dictionary).get("id", ""))
		if not skill_id.is_empty():
			skill_selected.emit(skill_id)


func _on_end_turn_pressed() -> void:
	wait_requested.emit()


func _on_turn_unit_pressed(character_id: String) -> void:
	if not character_id.is_empty():
		turn_unit_selected.emit(character_id)


func _style_turn_order() -> void:
	turn_order_title.text = "行动"
	var transparent := StyleBoxFlat.new()
	transparent.bg_color = Color.TRANSPARENT
	transparent.border_color = Color.TRANSPARENT
	turn_order_panel.add_theme_stylebox_override("panel", transparent)


func _get_full_portrait_texture(unit: Dictionary) -> Texture2D:
	var appearance: Dictionary = unit.get("appearance", {}) as Dictionary
	var portrait: Dictionary = appearance.get("portrait", {}) as Dictionary
	var source: String = str(portrait.get("avatar", portrait.get("full", appearance.get("portrait_source", ""))))
	return _load_portrait_texture(source)


func _get_avatar_texture(unit: Dictionary) -> Texture2D:
	var appearance: Dictionary = unit.get("appearance", {}) as Dictionary
	var portrait: Dictionary = appearance.get("portrait", {}) as Dictionary
	var source: String = str(portrait.get("avatar", portrait.get("full", appearance.get("portrait_source", ""))))
	return _load_portrait_texture(source)


func _load_portrait_texture(source: String) -> Texture2D:
	if source.is_empty():
		return null
	if _portrait_texture_cache.has(source):
		return _portrait_texture_cache[source] as Texture2D
	var texture: Texture2D = load(source) as Texture2D
	_portrait_texture_cache[source] = texture
	return texture


func _build_turn_tooltip(unit: Dictionary) -> String:
	return "%s  LV.%d\nHP %d/%d   MP %d/%d\n攻击 %d   防御 %d   速度 %d" % [
		str(unit.get("display_name", unit.get("character_id", "未知"))),
		int(unit.get("level", 1)),
		int(unit.get("hp", 0)),
		int(unit.get("max_hp", 0)),
		int(unit.get("mp", 0)),
		int(unit.get("max_mp", 0)),
		int(unit.get("attack", 0)),
		int(unit.get("defense", 0)),
		int(unit.get("speed", 0)),
	]


func _build_skill_detail(skill: Dictionary) -> String:
	var detail: String = "%s\nAP %d   MP %d   范围 %d" % [
		str(skill.get("description", "")),
		int(skill.get("ap_cost", 0)),
		int(skill.get("mp_cost", 0)),
		int(skill.get("range", 0)),
	]
	var failure: String = str(skill.get("failure_reason", ""))
	return detail if failure.is_empty() else detail + "\n不可用：" + failure


func _portrait_fallback_text(unit: Dictionary) -> String:
	var text: String = str(unit.get("display_name", unit.get("character_id", "?")))
	return text.left(1) if not text.is_empty() else "?"


func _clear_children(parent: Node) -> void:
	for child in parent.get_children():
		child.queue_free()

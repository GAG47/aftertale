class_name BattleHudPanel
extends Control

signal wait_requested()
signal flee_requested()
signal skill_selected(skill_id: String)
signal move_selected()
signal turn_unit_selected(character_id: String)

const MAX_SKILL_SLOTS := 4
const PORTRAIT_SIZE := 48.0
const CHARACTER_PORTRAIT_SIZE := Vector2(86.0, 86.0)
const BRIGHT_TEXT := Color(1.0, 1.0, 1.0, 1.0)

@onready var turn_order_panel: PanelContainer = $TurnOrderPanel
@onready var turn_order_title: Label = $TurnOrderPanel/TurnOrderMargin/TurnOrderBox/TurnOrderTitle
@onready var turn_order_list: VBoxContainer = $TurnOrderPanel/TurnOrderMargin/TurnOrderBox/TurnOrderScroll/TurnOrderList
@onready var legacy_bottom_panel: PanelContainer = $BottomPanel
@onready var legacy_skill_panel: PanelContainer = $SkillPanel
@onready var ai_debug_panel: PanelContainer = $AiDebugPanel
@onready var ai_debug_title_label: Label = $AiDebugPanel/AiDebugMargin/AiDebugBox/AiDebugTitleLabel
@onready var ai_debug_detail_label: Label = $AiDebugPanel/AiDebugMargin/AiDebugBox/AiDebugScroll/AiDebugDetailLabel

var _character_dock: PanelContainer
var _portrait_texture_rect: TextureRect
var _portrait_fallback_label: Label
var _name_label: Label
var _level_label: Label
var _status_icons: HBoxContainer
var _hp_label: Label
var _hp_bar: ProgressBar
var _attack_label: Label
var _defense_label: Label
var _speed_label: Label

var _skill_dock: PanelContainer
var _skill_buttons: Array[Button] = []
var _mp_label: Label
var _mp_bar: ProgressBar
var _ap_label: Label
var _round_label: Label
var _end_turn_button: Button
var _ai_debug_button: Button

var _current_summary: Dictionary = {}
var _skill_summaries: Array = []
var _selected_skill_id: String = ""
var _tactical_mode: String = "move"
var _can_control: bool = false
var _selectable_turn_unit_ids: Array[String] = []
var _portrait_texture_cache: Dictionary = {}
var _battle_id: String = ""


func _ready() -> void:
	visible = false
	legacy_bottom_panel.visible = false
	legacy_skill_panel.visible = false
	legacy_bottom_panel.queue_free()
	legacy_skill_panel.queue_free()
	_build_character_dock()
	_build_skill_dock()
	_style_turn_order()
	_apply_responsive_layout()


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
	var next_battle_id: String = str(summary.get("battle_id", ""))
	if next_battle_id != _battle_id:
		_battle_id = next_battle_id

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
	_battle_id = ""
	ai_debug_panel.visible = false


func toggle_ai_debug() -> void:
	ai_debug_panel.visible = not ai_debug_panel.visible
	_ai_debug_button.button_pressed = ai_debug_panel.visible
	if ai_debug_panel.visible:
		_refresh_ai_debug()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey:
		var key_event: InputEventKey = event as InputEventKey
		if key_event.pressed and not key_event.echo and key_event.keycode == KEY_F4:
			get_viewport().set_input_as_handled()
			toggle_ai_debug()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and is_node_ready():
		_apply_responsive_layout()


func _build_character_dock() -> void:
	_character_dock = PanelContainer.new()
	_character_dock.name = "CharacterDock"
	_set_bottom_left_rect(_character_dock, 12.0, 414.0, -112.0, -10.0)
	_character_dock.mouse_filter = Control.MOUSE_FILTER_STOP
	_character_dock.add_theme_stylebox_override("panel", _dock_style(
		Color(0.018, 0.035, 0.042, 0.76),
		Color(0.055, 0.110, 0.115, 0.34),
		Color(0.28, 0.88, 0.72, 0.68)
	))
	add_child(_character_dock)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_top", 7)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 7)
	_character_dock.add_child(margin)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	margin.add_child(row)

	var portrait_frame := PanelContainer.new()
	portrait_frame.custom_minimum_size = CHARACTER_PORTRAIT_SIZE
	portrait_frame.add_theme_stylebox_override("panel", _portrait_frame_style())
	row.add_child(portrait_frame)

	_portrait_texture_rect = TextureRect.new()
	_portrait_texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait_texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_portrait_texture_rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	portrait_frame.add_child(_portrait_texture_rect)
	_portrait_fallback_label = Label.new()
	_portrait_fallback_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_portrait_fallback_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_portrait_fallback_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_portrait_fallback_label.add_theme_font_size_override("font_size", 28)
	_portrait_fallback_label.add_theme_color_override("font_color", BRIGHT_TEXT)
	portrait_frame.add_child(_portrait_fallback_label)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 2)
	row.add_child(info)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 5)
	info.add_child(header)
	_name_label = Label.new()
	_name_label.add_theme_font_size_override("font_size", 18)
	_name_label.add_theme_color_override("font_color", BRIGHT_TEXT)
	header.add_child(_name_label)

	var level_badge := PanelContainer.new()
	level_badge.add_theme_stylebox_override("panel", _level_badge_style())
	header.add_child(level_badge)
	_level_label = Label.new()
	_level_label.add_theme_font_size_override("font_size", 12)
	_level_label.add_theme_color_override("font_color", Color(0.04, 0.05, 0.06))
	_level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	level_badge.add_child(_level_label)

	var header_spacer := Control.new()
	header_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(header_spacer)
	_status_icons = HBoxContainer.new()
	_status_icons.name = "StatusIcons"
	_status_icons.add_theme_constant_override("separation", 3)
	header.add_child(_status_icons)

	_hp_label = Label.new()
	_hp_label.add_theme_font_size_override("font_size", 13)
	_hp_label.add_theme_color_override("font_color", BRIGHT_TEXT)
	info.add_child(_hp_label)
	_hp_bar = ProgressBar.new()
	_hp_bar.custom_minimum_size = Vector2(0.0, 11.0)
	_hp_bar.show_percentage = false
	_hp_bar.add_theme_stylebox_override("background", _bar_style(Color(0.02, 0.06, 0.07, 0.92)))
	_hp_bar.add_theme_stylebox_override("fill", _bar_style(Color(0.18, 0.88, 0.62, 0.96)))
	info.add_child(_hp_bar)

	var stats := HBoxContainer.new()
	stats.add_theme_constant_override("separation", 15)
	info.add_child(stats)
	_attack_label = _stat_label()
	_defense_label = _stat_label()
	_speed_label = _stat_label()
	stats.add_child(_attack_label)
	stats.add_child(_defense_label)
	stats.add_child(_speed_label)


func _build_skill_dock() -> void:
	_skill_dock = PanelContainer.new()
	_skill_dock.name = "SkillDock"
	_set_bottom_right_rect(_skill_dock, -574.0, -12.0, -112.0, -10.0)
	_skill_dock.mouse_filter = Control.MOUSE_FILTER_STOP
	_skill_dock.add_theme_stylebox_override("panel", _dock_style(
		Color(0.018, 0.035, 0.055, 0.76),
		Color(0.045, 0.085, 0.130, 0.34),
		Color(0.25, 0.70, 1.0, 0.68)
	))
	add_child(_skill_dock)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 9)
	margin.add_theme_constant_override("margin_top", 7)
	margin.add_theme_constant_override("margin_right", 9)
	margin.add_theme_constant_override("margin_bottom", 7)
	_skill_dock.add_child(margin)

	var root_box := VBoxContainer.new()
	root_box.add_theme_constant_override("separation", 4)
	margin.add_child(root_box)

	var skill_row := HBoxContainer.new()
	skill_row.add_theme_constant_override("separation", 5)
	root_box.add_child(skill_row)
	for slot_index in range(MAX_SKILL_SLOTS):
		var button := Button.new()
		button.custom_minimum_size = Vector2(88.0, 52.0)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.focus_mode = Control.FOCUS_NONE
		button.toggle_mode = true
		button.add_theme_font_size_override("font_size", 13)
		button.add_theme_color_override("font_color", BRIGHT_TEXT)
		button.add_theme_color_override("font_hover_color", BRIGHT_TEXT)
		button.add_theme_color_override("font_pressed_color", BRIGHT_TEXT)
		button.add_theme_color_override("font_disabled_color", Color(0.70, 0.72, 0.75, 0.82))
		button.text = "%d\n-" % (slot_index + 1)
		button.pressed.connect(_on_skill_slot_pressed.bind(slot_index))
		button.add_theme_stylebox_override("normal", _skill_button_style(false))
		button.add_theme_stylebox_override("hover", _skill_button_style(true))
		button.add_theme_stylebox_override("pressed", _skill_button_style(true))
		button.add_theme_stylebox_override("disabled", _skill_button_style(false, true))
		skill_row.add_child(button)
		_skill_buttons.append(button)

	var resource_row := HBoxContainer.new()
	resource_row.add_theme_constant_override("separation", 7)
	root_box.add_child(resource_row)
	_mp_label = Label.new()
	_mp_label.custom_minimum_size = Vector2(72.0, 0.0)
	_mp_label.add_theme_color_override("font_color", BRIGHT_TEXT)
	resource_row.add_child(_mp_label)
	_mp_bar = ProgressBar.new()
	_mp_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mp_bar.custom_minimum_size = Vector2(72.0, 10.0)
	_mp_bar.show_percentage = false
	_mp_bar.add_theme_stylebox_override("background", _bar_style(Color(0.02, 0.05, 0.09, 0.94)))
	_mp_bar.add_theme_stylebox_override("fill", _bar_style(Color(0.16, 0.65, 0.96, 0.96)))
	resource_row.add_child(_mp_bar)
	_ap_label = Label.new()
	_ap_label.add_theme_color_override("font_color", BRIGHT_TEXT)
	resource_row.add_child(_ap_label)
	_round_label = Label.new()
	_round_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_round_label.add_theme_color_override("font_color", BRIGHT_TEXT)
	resource_row.add_child(_round_label)
	_ai_debug_button = Button.new()
	_ai_debug_button.custom_minimum_size = Vector2(38.0, 27.0)
	_ai_debug_button.text = "AI"
	_ai_debug_button.toggle_mode = true
	_ai_debug_button.tooltip_text = "AI 评分调试（F4）"
	_ai_debug_button.pressed.connect(toggle_ai_debug)
	resource_row.add_child(_ai_debug_button)
	_end_turn_button = Button.new()
	_end_turn_button.custom_minimum_size = Vector2(98.0, 27.0)
	_end_turn_button.text = "结束回合"
	_end_turn_button.add_theme_color_override("font_color", BRIGHT_TEXT)
	_end_turn_button.add_theme_color_override("font_hover_color", BRIGHT_TEXT)
	_end_turn_button.pressed.connect(_on_end_turn_pressed)
	_end_turn_button.add_theme_stylebox_override("normal", _end_turn_style(false))
	_end_turn_button.add_theme_stylebox_override("hover", _end_turn_style(true))
	_end_turn_button.add_theme_stylebox_override("pressed", _end_turn_style(true))
	resource_row.add_child(_end_turn_button)


func _refresh_character_dock() -> void:
	var unit: Dictionary = _current_summary.get("current_unit", {}) as Dictionary
	if unit.is_empty():
		_character_dock.visible = false
		return
	_character_dock.visible = true
	_name_label.text = str(unit.get("display_name", unit.get("character_id", "未知")))
	_level_label.text = "LV.%d" % int(unit.get("level", 1))
	_refresh_status_icons(unit)
	_hp_label.text = "HP  %d / %d" % [int(unit.get("hp", 0)), int(unit.get("max_hp", 0))]
	_hp_bar.max_value = max(1, int(unit.get("max_hp", 1)))
	_hp_bar.value = clampi(int(unit.get("hp", 0)), 0, int(_hp_bar.max_value))
	_attack_label.text = "攻击  %d" % int(unit.get("attack", 0))
	_defense_label.text = "防御  %d" % int(unit.get("defense", 0))
	_speed_label.text = "速度  %d" % int(unit.get("speed", 0))
	var portrait_texture: Texture2D = _get_portrait_texture(unit)
	_portrait_texture_rect.texture = portrait_texture
	_portrait_fallback_label.visible = portrait_texture == null
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
	_ap_label.text = "AP %d/%d" % [
		int(unit.get("action_points", 0)),
		int(unit.get("max_action_points", 0)),
	]
	_round_label.text = "TURN  %d" % int(_current_summary.get("round", 1))
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
	var button := Button.new()
	button.custom_minimum_size = Vector2(PORTRAIT_SIZE, PORTRAIT_SIZE)
	button.focus_mode = Control.FOCUS_NONE
	button.disabled = not can_select or is_current
	button.tooltip_text = _build_turn_tooltip(unit)
	button.text = _portrait_fallback_text(unit)
	button.add_theme_font_size_override("font_size", 18)
	var texture: Texture2D = _get_portrait_texture(unit)
	if texture != null:
		button.icon = texture
		button.expand_icon = true
		button.text = ""
	var team: String = str(unit.get("team", ""))
	button.add_theme_stylebox_override("normal", _turn_portrait_style(team, is_current))
	button.add_theme_stylebox_override("hover", _turn_portrait_style(team, true))
	button.add_theme_stylebox_override("pressed", _turn_portrait_style(team, true))
	button.add_theme_stylebox_override("disabled", _turn_portrait_style(team, is_current))
	if can_select:
		button.pressed.connect(_on_turn_unit_pressed.bind(unit_id))
	return button


func _refresh_ai_debug() -> void:
	var decisions: Array = _current_summary.get("recent_ai_decisions", []) as Array
	if decisions.is_empty():
		ai_debug_title_label.text = "AI 评分"
		ai_debug_detail_label.text = "暂无 AI 决策。"
		return
	var decision: Dictionary = decisions.back() as Dictionary
	var chosen: Dictionary = decision.get("chosen", {}) as Dictionary
	ai_debug_title_label.text = "%s / %s" % [
		str(decision.get("character_id", "AI")),
		str(decision.get("profile_id", "balanced")),
	]
	var lines := PackedStringArray()
	lines.append("选择：%s" % str(chosen.get("description", "")))
	lines.append("总分：%.1f   候选：%d" % [
		float(chosen.get("total_score", 0.0)),
		int(decision.get("candidate_count", 0)),
	])
	for entry_value in chosen.get("score_breakdown", []) as Array:
		var entry: Dictionary = entry_value as Dictionary
		lines.append("%s  %+.1f" % [
			str(entry.get("label", entry.get("id", ""))),
			float(entry.get("weighted", 0.0)),
		])
	ai_debug_detail_label.text = "\n".join(lines)


func _on_skill_slot_pressed(slot_index: int) -> void:
	if slot_index < 0 or slot_index >= _skill_summaries.size():
		return
	var skill: Dictionary = _skill_summaries[slot_index] as Dictionary
	var skill_id: String = str(skill.get("id", ""))
	if not skill_id.is_empty():
		skill_selected.emit(skill_id)


func _on_end_turn_pressed() -> void:
	wait_requested.emit()


func _on_turn_unit_pressed(character_id: String) -> void:
	if not character_id.is_empty():
		turn_unit_selected.emit(character_id)


func _style_turn_order() -> void:
	turn_order_title.text = "行动"
	turn_order_title.add_theme_color_override("font_color", Color(0.86, 0.90, 0.92, 0.88))
	var transparent := StyleBoxFlat.new()
	transparent.bg_color = Color.TRANSPARENT
	transparent.border_color = Color.TRANSPARENT
	turn_order_panel.add_theme_stylebox_override("panel", transparent)


func _apply_responsive_layout() -> void:
	if _character_dock == null or _skill_dock == null:
		return
	var viewport_size: Vector2 = get_viewport_rect().size
	var compact: bool = viewport_size.x < 1050.0
	var character_width: float = 366.0 if compact else 402.0
	var skill_width: float = 520.0 if compact else 562.0
	_character_dock.offset_left = 12.0
	_character_dock.offset_right = 12.0 + character_width
	_character_dock.offset_top = -112.0
	_character_dock.offset_bottom = -10.0
	_skill_dock.offset_left = -12.0 - skill_width
	_skill_dock.offset_right = -12.0
	_skill_dock.offset_top = -112.0
	_skill_dock.offset_bottom = -10.0
	for button in _skill_buttons:
		button.custom_minimum_size.x = 76.0 if compact else 88.0
		button.add_theme_font_size_override("font_size", 12 if compact else 13)


func _dock_style(base: Color, highlight: Color, accent: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = base
	style.border_color = accent
	style.border_width_top = 1
	style.border_width_bottom = 2
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.32)
	style.shadow_size = 5
	style.shadow_offset = Vector2(0.0, 2.0)
	style.anti_aliasing = true
	style.skew = Vector2(-0.025, 0.0)
	style.bg_color = base.lerp(highlight, 0.24)
	return style


func _portrait_frame_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.035, 0.045, 0.92)
	style.border_color = Color(0.34, 0.82, 0.74, 0.74)
	style.set_border_width_all(2)
	style.set_corner_radius_all(3)
	return style


func _level_badge_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.96, 0.97, 0.98, 1.0)
	style.set_corner_radius_all(2)
	style.content_margin_left = 5.0
	style.content_margin_right = 5.0
	style.content_margin_top = 1.0
	style.content_margin_bottom = 1.0
	return style


func _bar_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(2)
	return style


func _stat_label() -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", BRIGHT_TEXT)
	return label


func _skill_button_style(highlighted: bool, disabled: bool = false) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.045, 0.075, 0.105, 0.72 if not disabled else 0.42)
	style.border_color = Color(0.22, 0.62, 0.92, 0.88) if highlighted else Color(0.26, 0.38, 0.48, 0.72)
	style.set_border_width_all(2 if highlighted else 1)
	style.set_corner_radius_all(3)
	return style


func _end_turn_style(highlighted: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.46, 0.25, 0.06, 0.90) if highlighted else Color(0.25, 0.16, 0.07, 0.82)
	style.border_color = Color(1.0, 0.64, 0.20, 0.90)
	style.set_border_width_all(2 if highlighted else 1)
	style.set_corner_radius_all(3)
	return style


func _turn_portrait_style(team: String, current: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.035, 0.045, 0.62)
	style.border_color = Color(0.30, 0.70, 1.0) if team == "player" else Color(1.0, 0.34, 0.30)
	if current:
		style.border_color = Color(1.0, 0.84, 0.26)
	style.set_border_width_all(3 if current else 2)
	style.set_corner_radius_all(4)
	style.content_margin_left = 3.0
	style.content_margin_top = 3.0
	style.content_margin_right = 3.0
	style.content_margin_bottom = 3.0
	return style


func _get_portrait_texture(unit: Dictionary) -> Texture2D:
	var appearance: Dictionary = unit.get("appearance", {}) as Dictionary
	var portrait: Dictionary = appearance.get("portrait", {}) as Dictionary
	var source: String = str(portrait.get("badge", appearance.get("badge_source", "")))
	if source.is_empty():
		return null
	if _portrait_texture_cache.has(source):
		return _portrait_texture_cache[source] as Texture2D
	var texture: Texture2D = load(source) as Texture2D
	_portrait_texture_cache[source] = texture
	return texture


func _build_turn_tooltip(unit: Dictionary) -> String:
	return "%s  LV.%d\nHP %d/%d   MP %d/%d\n攻击 %d   防御 %d   速度 %d\n状态：%s" % [
		str(unit.get("display_name", unit.get("character_id", "未知"))),
		int(unit.get("level", 1)),
		int(unit.get("hp", 0)),
		int(unit.get("max_hp", 0)),
		int(unit.get("mp", 0)),
		int(unit.get("max_mp", 0)),
		int(unit.get("attack", 0)),
		int(unit.get("defense", 0)),
		int(unit.get("speed", 0)),
		_get_status_text(unit),
	]


func _build_skill_detail(skill: Dictionary) -> String:
	var detail: String = "%s\nAP %d   MP %d   范围 %d" % [
		str(skill.get("description", "")),
		int(skill.get("ap_cost", 0)),
		int(skill.get("mp_cost", 0)),
		int(skill.get("range", 0)),
	]
	var failure: String = str(skill.get("failure_reason", ""))
	if not failure.is_empty():
		detail += "\n不可用：%s" % failure
	return detail


func _get_status_text(unit: Dictionary) -> String:
	var status_text: String = str(unit.get("status_text", ""))
	return "无" if status_text.is_empty() else status_text


func _portrait_fallback_text(unit: Dictionary) -> String:
	var text: String = str(unit.get("display_name", unit.get("character_id", "?")))
	return text.left(1) if not text.is_empty() else "?"


func _clear_children(parent: Node) -> void:
	for child in parent.get_children():
		child.queue_free()


func _set_bottom_left_rect(control: Control, left: float, right: float, top: float, bottom: float) -> void:
	control.set_anchor(SIDE_LEFT, 0.0)
	control.set_anchor(SIDE_TOP, 1.0)
	control.set_anchor(SIDE_RIGHT, 0.0)
	control.set_anchor(SIDE_BOTTOM, 1.0)
	control.offset_left = left
	control.offset_right = right
	control.offset_top = top
	control.offset_bottom = bottom


func _set_bottom_right_rect(control: Control, left: float, right: float, top: float, bottom: float) -> void:
	control.set_anchor(SIDE_LEFT, 1.0)
	control.set_anchor(SIDE_TOP, 1.0)
	control.set_anchor(SIDE_RIGHT, 1.0)
	control.set_anchor(SIDE_BOTTOM, 1.0)
	control.offset_left = left
	control.offset_right = right
	control.offset_top = top
	control.offset_bottom = bottom


func _refresh_status_icons(unit: Dictionary) -> void:
	_clear_children(_status_icons)
	var statuses: Dictionary = unit.get("status_effects", {}) as Dictionary
	for status_value in statuses.values():
		var status: Dictionary = status_value as Dictionary
		var status_id: String = str(status.get("status_id", status.get("id", "")))
		if status_id.is_empty():
			continue
		_status_icons.add_child(_make_status_icon(status_id, status))


func _make_status_icon(status_id: String, status: Dictionary) -> Control:
	var badge := PanelContainer.new()
	badge.custom_minimum_size = Vector2(23.0, 23.0)
	badge.tooltip_text = str(status.get("display_name", _status_display_name(status_id)))
	var style := StyleBoxFlat.new()
	style.bg_color = _status_color(status_id)
	style.border_color = Color(1.0, 1.0, 1.0, 0.82)
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	badge.add_theme_stylebox_override("panel", style)

	var label := Label.new()
	label.text = _status_symbol(status_id)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", BRIGHT_TEXT)
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.85))
	label.add_theme_constant_override("outline_size", 2)
	badge.add_child(label)
	return badge


func _status_symbol(status_id: String) -> String:
	match status_id:
		"burning":
			return "火"
		"wet":
			return "湿"
		"frozen", "chilled":
			return "冰"
		"electrified", "shocked":
			return "雷"
		"stunned":
			return "晕"
		"shielded", "shield":
			return "盾"
		_:
			return "态"


func _status_display_name(status_id: String) -> String:
	match status_id:
		"burning":
			return "燃烧"
		"wet":
			return "湿润"
		"frozen":
			return "冻结"
		"chilled":
			return "寒冷"
		"electrified":
			return "导电"
		"shocked":
			return "感电"
		"stunned":
			return "眩晕"
		"shielded", "shield":
			return "护盾"
		_:
			return status_id


func _status_color(status_id: String) -> Color:
	match status_id:
		"burning":
			return Color(0.88, 0.20, 0.08, 0.92)
		"wet":
			return Color(0.08, 0.48, 0.92, 0.92)
		"frozen", "chilled":
			return Color(0.20, 0.74, 0.92, 0.92)
		"electrified", "shocked":
			return Color(0.92, 0.64, 0.05, 0.94)
		"stunned":
			return Color(0.62, 0.38, 0.92, 0.92)
		"shielded", "shield":
			return Color(0.18, 0.68, 0.48, 0.92)
		_:
			return Color(0.34, 0.38, 0.44, 0.92)

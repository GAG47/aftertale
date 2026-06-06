class_name CharacterPanel
extends Control

signal close_requested()
signal character_action_requested(action_type: String, target: Dictionary)

var _actor: CharacterEntity
var _party_summaries: Array[Dictionary] = []
var _selected_member_id: String = ""
var _selected_skill_id: String = ""

var _panel: PanelContainer
var _party_scroll: ScrollContainer
var _party_list: VBoxContainer
var _move_up_button: Button
var _move_down_button: Button
var _leave_button: Button
var _portrait_panel: Panel
var _name_label: Label
var _identity_label: Label
var _level_label: Label
var _attribute_box: VBoxContainer
var _equipment_box: VBoxContainer
var _skill_scroll: ScrollContainer
var _skill_list: VBoxContainer
var _skill_detail_title: Label
var _skill_detail_body: Label
var _portrait_texture_cache: Dictionary = {}


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_ui()


func open_for_actor(actor: CharacterEntity) -> void:
	_actor = actor
	_selected_member_id = actor.character_id if actor != null and is_instance_valid(actor) else ""
	visible = true
	_select_default_skill()
	refresh()


func close_panel() -> void:
	visible = false


func is_open() -> bool:
	return visible


func refresh() -> void:
	var summary: Dictionary = _get_actor_summary()
	_refresh_party_data(summary)
	summary = _get_selected_member_summary()
	_refresh_profile(summary)
	_refresh_attributes(summary)
	_refresh_equipment(summary)
	_refresh_skills(summary)


func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.name = "CharacterWindow"
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.custom_minimum_size = Vector2(1080.0, 600.0)
	_panel.offset_left = -540.0
	_panel.offset_top = -300.0
	_panel.offset_right = 540.0
	_panel.offset_bottom = 300.0
	_panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.045, 0.052, 0.052, 0.96), Color(0.72, 0.60, 0.42, 0.46), 8))
	add_child(_panel)

	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_bottom", 16)
	_panel.add_child(margin)

	var root: VBoxContainer = VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)

	root.add_child(_make_header())

	var body: HBoxContainer = HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 10)
	root.add_child(body)

	body.add_child(_make_party_area())
	body.add_child(_make_profile_area())
	body.add_child(_make_attribute_area())
	body.add_child(_make_equipment_area())
	body.add_child(_make_skill_area())


func _make_header() -> Control:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)

	var title: Label = Label.new()
	title.text = "角色"
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(0.96, 0.84, 0.62))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title)

	var hint: Label = Label.new()
	hint.text = "C 打开/关闭"
	hint.modulate = Color(0.76, 0.72, 0.64)
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(hint)

	var close_button: Button = Button.new()
	close_button.text = "关闭"
	close_button.custom_minimum_size = Vector2(76.0, 34.0)
	close_button.pressed.connect(_request_close)
	row.add_child(close_button)
	return row


func _make_party_area() -> Control:
	var panel: PanelContainer = PanelContainer.new()
	panel.custom_minimum_size = Vector2(210.0, 0.0)
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.02, 0.025, 0.026, 0.38), Color(0.68, 0.58, 0.42, 0.24), 6))

	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(margin)

	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	margin.add_child(box)

	var title: Label = Label.new()
	title.text = "当前队伍"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(0.96, 0.84, 0.62))
	box.add_child(title)

	var separator: HSeparator = HSeparator.new()
	box.add_child(separator)

	_party_scroll = ScrollContainer.new()
	_party_scroll.custom_minimum_size = Vector2(0.0, 350.0)
	_party_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_party_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_party_scroll)

	_party_list = VBoxContainer.new()
	_party_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_party_list.add_theme_constant_override("separation", 8)
	_party_scroll.add_child(_party_list)

	var controls: HBoxContainer = HBoxContainer.new()
	controls.add_theme_constant_override("separation", 6)
	box.add_child(controls)

	_move_up_button = _make_party_control_button("上移")
	_move_up_button.pressed.connect(_on_move_member_up_pressed)
	controls.add_child(_move_up_button)

	_move_down_button = _make_party_control_button("下移")
	_move_down_button.pressed.connect(_on_move_member_down_pressed)
	controls.add_child(_move_down_button)

	_leave_button = _make_party_control_button("离队")
	_leave_button.pressed.connect(_on_leave_member_pressed)
	controls.add_child(_leave_button)
	return panel


func _make_profile_area() -> Control:
	var panel: PanelContainer = PanelContainer.new()
	panel.custom_minimum_size = Vector2(230.0, 0.0)
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.03, 0.038, 0.04, 0.70), Color(0.70, 0.60, 0.45, 0.30), 6))

	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(margin)

	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	margin.add_child(box)

	_portrait_panel = Panel.new()
	_portrait_panel.custom_minimum_size = Vector2(0.0, 340.0)
	_portrait_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_portrait_panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.04, 0.05, 0.052, 0.84), Color(0.60, 0.50, 0.36, 0.22), 6))
	_portrait_panel.draw.connect(_draw_portrait)
	box.add_child(_portrait_panel)

	var info_panel: PanelContainer = PanelContainer.new()
	info_panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.035, 0.04, 0.04, 0.84), Color(0.70, 0.60, 0.45, 0.24), 6))
	box.add_child(info_panel)

	var info_margin: MarginContainer = MarginContainer.new()
	info_margin.add_theme_constant_override("margin_left", 12)
	info_margin.add_theme_constant_override("margin_top", 10)
	info_margin.add_theme_constant_override("margin_right", 12)
	info_margin.add_theme_constant_override("margin_bottom", 10)
	info_panel.add_child(info_margin)

	var info_box: VBoxContainer = VBoxContainer.new()
	info_box.add_theme_constant_override("separation", 6)
	info_margin.add_child(info_box)

	_name_label = Label.new()
	_name_label.add_theme_font_size_override("font_size", 22)
	_name_label.add_theme_color_override("font_color", Color(0.96, 0.92, 0.84))
	_name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_box.add_child(_name_label)

	_identity_label = Label.new()
	_identity_label.modulate = Color(0.78, 0.76, 0.70)
	_identity_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_box.add_child(_identity_label)

	_level_label = Label.new()
	_level_label.modulate = Color(0.74, 0.84, 0.96)
	info_box.add_child(_level_label)
	return panel


func _make_attribute_area() -> Control:
	var panel: PanelContainer = _make_column_panel(Vector2(175.0, 0.0))
	var box: VBoxContainer = _make_column_box(panel, "基础属性")
	_attribute_box = VBoxContainer.new()
	_attribute_box.add_theme_constant_override("separation", 8)
	box.add_child(_attribute_box)
	return panel


func _make_equipment_area() -> Control:
	var panel: PanelContainer = _make_column_panel(Vector2(175.0, 0.0))
	var box: VBoxContainer = _make_column_box(panel, "装备")
	_equipment_box = VBoxContainer.new()
	_equipment_box.add_theme_constant_override("separation", 8)
	box.add_child(_equipment_box)
	return panel


func _make_skill_area() -> Control:
	var panel: PanelContainer = _make_column_panel(Vector2(210.0, 0.0))
	var box: VBoxContainer = _make_column_box(panel, "技能")

	_skill_scroll = ScrollContainer.new()
	_skill_scroll.custom_minimum_size = Vector2(0.0, 300.0)
	_skill_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_skill_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_skill_scroll)

	_skill_list = VBoxContainer.new()
	_skill_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_skill_list.add_theme_constant_override("separation", 8)
	_skill_scroll.add_child(_skill_list)

	var detail_panel: PanelContainer = PanelContainer.new()
	detail_panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.035, 0.04, 0.04, 0.86), Color(0.70, 0.60, 0.45, 0.26), 6))
	box.add_child(detail_panel)

	var detail_margin: MarginContainer = MarginContainer.new()
	detail_margin.add_theme_constant_override("margin_left", 10)
	detail_margin.add_theme_constant_override("margin_top", 8)
	detail_margin.add_theme_constant_override("margin_right", 10)
	detail_margin.add_theme_constant_override("margin_bottom", 8)
	detail_panel.add_child(detail_margin)

	var detail_box: VBoxContainer = VBoxContainer.new()
	detail_box.add_theme_constant_override("separation", 6)
	detail_margin.add_child(detail_box)

	_skill_detail_title = Label.new()
	_skill_detail_title.add_theme_font_size_override("font_size", 17)
	_skill_detail_title.add_theme_color_override("font_color", Color(0.96, 0.84, 0.62))
	_skill_detail_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_box.add_child(_skill_detail_title)

	_skill_detail_body = Label.new()
	_skill_detail_body.modulate = Color(0.82, 0.84, 0.80)
	_skill_detail_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_box.add_child(_skill_detail_body)
	return panel


func _make_column_panel(minimum_size: Vector2) -> PanelContainer:
	var panel: PanelContainer = PanelContainer.new()
	panel.custom_minimum_size = minimum_size
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.03, 0.037, 0.038, 0.72), Color(0.70, 0.60, 0.45, 0.30), 6))
	return panel


func _make_column_box(panel: PanelContainer, title_text: String) -> VBoxContainer:
	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(margin)

	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	margin.add_child(box)

	var title: Label = Label.new()
	title.text = title_text
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(0.96, 0.84, 0.62))
	box.add_child(title)

	var separator: HSeparator = HSeparator.new()
	box.add_child(separator)
	return box


func _make_party_control_button(text: String) -> Button:
	var button: Button = Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0.0, 34.0)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return button


func _refresh_party_list(summary: Dictionary) -> void:
	_clear_children(_party_list)
	for member_summary in _party_summaries:
		_party_list.add_child(_make_party_slot(member_summary))
	var empty_slots: int = max(0, PartySystem.MAX_PARTY_SIZE - _party_summaries.size())
	for _index in range(empty_slots):
		_party_list.add_child(_make_empty_party_slot())
	_refresh_party_controls()


func _make_party_slot(summary: Dictionary) -> Control:
	var member_id: String = str(summary.get("party_member_id", summary.get("id", "")))
	var selected: bool = member_id == _selected_member_id
	var slot: PanelContainer = PanelContainer.new()
	slot.custom_minimum_size = Vector2(0.0, 76.0)
	slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slot.mouse_filter = Control.MOUSE_FILTER_STOP
	slot.set_meta("member_id", member_id)
	slot.add_theme_stylebox_override("panel", _make_panel_style(
		Color(0.11, 0.12, 0.11, 0.95) if selected else Color(0.04, 0.045, 0.046, 0.70),
		Color(0.95, 0.76, 0.42, 0.82) if selected else Color(0.55, 0.48, 0.38, 0.36),
		5,
		2 if selected else 1
	))
	slot.gui_input.connect(_on_party_slot_gui_input.bind(member_id))

	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 7)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 7)
	slot.add_child(margin)

	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	margin.add_child(row)

	var badge: Label = Label.new()
	badge.custom_minimum_size = Vector2(34.0, 48.0)
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge.text = _party_order_text(summary)
	badge.add_theme_font_size_override("font_size", 18)
	badge.add_theme_color_override("font_color", Color(0.96, 0.84, 0.62) if selected else Color(0.70, 0.64, 0.52))
	row.add_child(badge)

	var text_box: VBoxContainer = VBoxContainer.new()
	text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_box.add_theme_constant_override("separation", 3)
	row.add_child(text_box)

	var name_label: Label = _make_plain_label(str(summary.get("display_name", member_id)))
	name_label.add_theme_font_size_override("font_size", 16)
	name_label.add_theme_color_override("font_color", Color(0.96, 0.92, 0.84) if selected else Color(0.86, 0.84, 0.78))
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	text_box.add_child(name_label)

	var meta_label: Label = _make_plain_label(_party_meta_text(summary))
	meta_label.modulate = Color(0.72, 0.74, 0.68)
	meta_label.add_theme_font_size_override("font_size", 13)
	meta_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_box.add_child(meta_label)

	var hp_label: Label = _make_plain_label(_party_hp_text(summary))
	hp_label.modulate = Color(0.74, 0.84, 0.96)
	hp_label.add_theme_font_size_override("font_size", 13)
	text_box.add_child(hp_label)
	return slot


func _make_empty_party_slot() -> Control:
	var slot: PanelContainer = PanelContainer.new()
	slot.custom_minimum_size = Vector2(0.0, 54.0)
	slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slot.add_theme_stylebox_override("panel", _make_panel_style(
		Color(0.04, 0.045, 0.046, 0.70),
		Color(0.55, 0.48, 0.38, 0.36),
		5
	))
	var label: Label = Label.new()
	label.text = "空位"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", Color(0.55, 0.50, 0.42))
	slot.add_child(label)
	return slot


func _refresh_party_data(fallback_summary: Dictionary) -> void:
	_party_summaries = PartySystem.get_party_summary()
	if _party_summaries.is_empty() and not fallback_summary.is_empty():
		var copied_summary: Dictionary = fallback_summary.duplicate(true)
		copied_summary["party_member_id"] = str(copied_summary.get("id", ""))
		copied_summary["is_party_leader"] = true
		_party_summaries.append(copied_summary)

	if _selected_member_id.is_empty() and not _party_summaries.is_empty():
		_selected_member_id = _member_id_from_summary(_party_summaries[0] as Dictionary)
	if _get_selected_member_summary().is_empty() and not _party_summaries.is_empty():
		_selected_member_id = _member_id_from_summary(_party_summaries[0] as Dictionary)

	_refresh_party_list(fallback_summary)


func _get_selected_member_summary() -> Dictionary:
	for summary in _party_summaries:
		var member_id: String = _member_id_from_summary(summary)
		if member_id == _selected_member_id:
			return summary
	return {}


func _member_id_from_summary(summary: Dictionary) -> String:
	return str(summary.get("party_member_id", summary.get("id", "")))


func _refresh_profile(summary: Dictionary) -> void:
	_name_label.text = str(summary.get("display_name", summary.get("id", "未知角色")))
	_identity_label.text = "%s / %s" % [
		_kind_label(str(summary.get("kind", ""))),
		_identity_occupation(summary.get("identity", {}) as Dictionary),
	]
	var attributes: Dictionary = summary.get("attributes", {}) as Dictionary
	_level_label.text = "Lv. %d" % int(attributes.get("level", 1))
	_portrait_panel.queue_redraw()


func _refresh_attributes(summary: Dictionary) -> void:
	_clear_children(_attribute_box)
	var attributes: Dictionary = summary.get("attributes", {}) as Dictionary
	var effective: Dictionary = summary.get("effective_attributes", attributes) as Dictionary
	var hp: int = int(summary.get("hp", attributes.get("hp", 0)))
	var max_hp: int = int(summary.get("max_hp", effective.get("max_hp", 1)))

	_attribute_box.add_child(_make_bar_row("HP", hp, max(1, max_hp), Color(0.86, 0.24, 0.28)))
	_attribute_box.add_child(_make_text_row("AP", str(effective.get("action_points", 2))))
	_attribute_box.add_child(_make_text_row("速度", str(effective.get("speed", effective.get("agility", 1)))))
	_attribute_box.add_child(_make_separator())
	for key in ["strength", "agility", "intellect", "vitality"]:
		_attribute_box.add_child(_make_text_row(_attribute_label(key), _format_effective_attribute(attributes, effective, key)))
	_attribute_box.add_child(_make_separator())
	_attribute_box.add_child(_make_text_row("物理攻击", str(int(effective.get("strength", 1)) + 10)))
	_attribute_box.add_child(_make_text_row("物理防御", str(int(effective.get("vitality", 1)) + 8)))
	_attribute_box.add_child(_make_text_row("魔法防御", str(int(effective.get("intellect", 1)) + 8)))
	_attribute_box.add_child(_make_text_row("命中", "%d%%" % (80 + int(effective.get("agility", 1)) * 2)))
	_attribute_box.add_child(_make_text_row("闪避", "%d%%" % max(0, int(effective.get("agility", 1)) * 2)))
	_attribute_box.add_child(_make_text_row("暴击率", "%d%%" % max(1, int(effective.get("agility", 1)))))


func _refresh_equipment(summary: Dictionary) -> void:
	_clear_children(_equipment_box)
	var equipment: Dictionary = summary.get("equipment_slots", {}) as Dictionary
	for slot_id in ["weapon", "offhand", "head", "body", "accessory", "tool"]:
		var slot_data: Dictionary = equipment.get(slot_id, {}) as Dictionary
		_equipment_box.add_child(_make_equipment_row(slot_id, slot_data))


func _refresh_skills(summary: Dictionary) -> void:
	_clear_children(_skill_list)
	var skill_ids: Array = summary.get("skills", []) as Array
	if skill_ids.is_empty():
		_skill_list.add_child(_make_empty_label("没有技能。"))
		_skill_detail_title.text = "技能"
		_skill_detail_body.text = "当前角色还没有可显示的技能。"
		return

	for skill_id_value in skill_ids:
		var skill_id: String = str(skill_id_value)
		var skill: Dictionary = SkillSystem.get_skill(skill_id)
		if skill.is_empty():
			skill = { "id": skill_id, "display_name": skill_id, "description": "" }
		_skill_list.add_child(_make_skill_row(skill))

	if _selected_skill_id.is_empty() or not skill_ids.has(_selected_skill_id):
		_selected_skill_id = str(skill_ids[0])
	_refresh_skill_detail()


func _make_bar_row(label_text: String, value: int, max_value: int, color: Color) -> Control:
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)

	var row: HBoxContainer = HBoxContainer.new()
	var label: Label = _make_plain_label(label_text)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var value_label: Label = _make_plain_label("%d / %d" % [value, max_value])
	row.add_child(value_label)
	box.add_child(row)

	var bar: ProgressBar = ProgressBar.new()
	bar.custom_minimum_size = Vector2(0.0, 12.0)
	bar.min_value = 0
	bar.max_value = max(1, max_value)
	bar.value = clampi(value, 0, max(1, max_value))
	bar.show_percentage = false
	bar.add_theme_stylebox_override("fill", _make_panel_style(color, color, 4, 0))
	box.add_child(bar)
	return box


func _make_text_row(label_text: String, value_text: String) -> Control:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var label: Label = _make_plain_label(label_text)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var value: Label = _make_plain_label(value_text)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value)
	return row


func _make_equipment_row(slot_id: String, slot_data: Dictionary) -> Control:
	var row: PanelContainer = PanelContainer.new()
	row.custom_minimum_size = Vector2(0.0, 64.0)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_stylebox_override("panel", _make_panel_style(Color(0.035, 0.04, 0.04, 0.76), Color(0.58, 0.50, 0.38, 0.24), 6))

	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_top", 7)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_bottom", 7)
	row.add_child(margin)

	var box: HBoxContainer = HBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	margin.add_child(box)

	var icon: Label = Label.new()
	icon.custom_minimum_size = Vector2(42.0, 42.0)
	icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	icon.text = _equipment_icon(slot_id)
	icon.add_theme_font_size_override("font_size", 24)
	icon.add_theme_color_override("font_color", Color(0.82, 0.74, 0.60))
	box.add_child(icon)

	var text_box: VBoxContainer = VBoxContainer.new()
	text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_box.add_theme_constant_override("separation", 2)
	box.add_child(text_box)

	var slot_label: Label = _make_plain_label(_slot_label(slot_id))
	slot_label.modulate = Color(0.70, 0.70, 0.66)
	text_box.add_child(slot_label)

	var item_name: String = str(slot_data.get("display_name", ""))
	if item_name.is_empty():
		item_name = "暂未装备"
	var item_label: Label = _make_plain_label(item_name)
	item_label.add_theme_font_size_override("font_size", 16)
	text_box.add_child(item_label)

	var retrieve_button: Button = Button.new()
	retrieve_button.text = "取回"
	retrieve_button.custom_minimum_size = Vector2(58.0, 34.0)
	retrieve_button.disabled = not bool(slot_data.get("is_player_override", false))
	retrieve_button.pressed.connect(_on_unequip_pressed.bind(slot_id))
	box.add_child(retrieve_button)
	return row


func _make_skill_row(skill: Dictionary) -> Control:
	var skill_id: String = str(skill.get("id", ""))
	var selected: bool = skill_id == _selected_skill_id
	var row: PanelContainer = PanelContainer.new()
	row.custom_minimum_size = Vector2(0.0, 70.0)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.set_meta("skill_id", skill_id)
	row.add_theme_stylebox_override("panel", _make_panel_style(
		Color(0.06, 0.075, 0.082, 0.92) if selected else Color(0.035, 0.04, 0.04, 0.80),
		Color(0.22, 0.66, 1.0, 0.78) if selected else Color(0.58, 0.50, 0.38, 0.24),
		6,
		2 if selected else 1
	))
	row.gui_input.connect(_on_skill_gui_input.bind(skill_id))

	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 8)
	row.add_child(margin)

	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	margin.add_child(box)

	var top: HBoxContainer = HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	box.add_child(top)

	var name_label: Label = _make_plain_label(str(skill.get("display_name", skill_id)))
	name_label.add_theme_font_size_override("font_size", 16)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(name_label)

	var ap_label: Label = _make_plain_label("AP %d" % int(skill.get("ap_cost", 0)))
	ap_label.add_theme_color_override("font_color", Color(0.36, 0.74, 1.0))
	top.add_child(ap_label)

	var detail: Label = _make_plain_label(_skill_short_detail(skill))
	detail.modulate = Color(0.74, 0.76, 0.72)
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(detail)
	return row


func _refresh_skill_detail() -> void:
	var skill: Dictionary = SkillSystem.get_skill(_selected_skill_id)
	if skill.is_empty():
		_skill_detail_title.text = _selected_skill_id
		_skill_detail_body.text = ""
		return

	_skill_detail_title.text = str(skill.get("display_name", _selected_skill_id))
	_skill_detail_body.text = "%s\n%s / 射程 %d / %s" % [
		str(skill.get("description", "")),
		_target_type_label(str(skill.get("target_type", ""))),
		int(skill.get("range", 0)),
		_area_label(skill),
	]


func _on_skill_gui_input(event: InputEvent, skill_id: String) -> void:
	if event is InputEventMouseButton:
		var mouse_event: InputEventMouseButton = event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
			_selected_skill_id = skill_id
			_refresh_skill_selection_styles()
			_refresh_skill_detail()
			get_viewport().set_input_as_handled()


func _on_party_slot_gui_input(event: InputEvent, member_id: String) -> void:
	if event is InputEventMouseButton:
		var mouse_event: InputEventMouseButton = event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
			_selected_member_id = member_id
			_select_default_skill_for_summary(_get_selected_member_summary())
			refresh()
			get_viewport().set_input_as_handled()


func _on_move_member_up_pressed() -> void:
	_publish_party_result(PartySystem.move_member_up(_selected_member_id))


func _on_move_member_down_pressed() -> void:
	_publish_party_result(PartySystem.move_member_down(_selected_member_id))


func _on_leave_member_pressed() -> void:
	_publish_party_result(PartySystem.remove_member(_selected_member_id))


func _on_unequip_pressed(slot_id: String) -> void:
	if _selected_member_id.is_empty():
		return
	character_action_requested.emit("UnequipItemAction", {
		"slot_id": slot_id,
		"target_character_id": _selected_member_id,
	})


func _publish_party_result(result: ActionResult) -> void:
	if result == null:
		return
	ActionSystem.publish_result(result)
	if result.success:
		refresh()


func _refresh_skill_selection_styles() -> void:
	for child in _skill_list.get_children():
		if not child is PanelContainer:
			continue
		var row: PanelContainer = child as PanelContainer
		var skill_id: String = str(row.get_meta("skill_id", ""))
		var selected: bool = skill_id == _selected_skill_id
		row.add_theme_stylebox_override("panel", _make_panel_style(
			Color(0.06, 0.075, 0.082, 0.92) if selected else Color(0.035, 0.04, 0.04, 0.80),
			Color(0.22, 0.66, 1.0, 0.78) if selected else Color(0.58, 0.50, 0.38, 0.24),
			6,
			2 if selected else 1
		))


func _select_default_skill() -> void:
	_selected_skill_id = ""
	if _actor == null or not is_instance_valid(_actor):
		return
	if not _actor.skills.is_empty():
		_selected_skill_id = str(_actor.skills[0])


func _select_default_skill_for_summary(summary: Dictionary) -> void:
	_selected_skill_id = ""
	var skills: Array = summary.get("skills", []) as Array
	if not skills.is_empty():
		_selected_skill_id = str(skills[0])


func _refresh_party_controls() -> void:
	if _move_up_button == null or _move_down_button == null or _leave_button == null:
		return

	var selected_summary: Dictionary = _get_selected_member_summary()
	var selected_id: String = _member_id_from_summary(selected_summary)
	var selected_index: int = PartySystem.get_member_order_index(selected_id)
	var is_leader: bool = bool(selected_summary.get("is_party_leader", selected_id == PartySystem.leader_id))
	var can_reorder: bool = PartySystem.can_reorder_member(selected_id)
	_move_up_button.disabled = not can_reorder or selected_index <= 1
	_move_down_button.disabled = not can_reorder or selected_index >= _party_summaries.size() - 1
	_leave_button.disabled = selected_id.is_empty() or is_leader


func _party_order_text(summary: Dictionary) -> String:
	if bool(summary.get("is_party_leader", false)):
		return "队"
	return "%02d" % int(summary.get("party_order", 0))


func _party_meta_text(summary: Dictionary) -> String:
	if bool(summary.get("is_party_leader", false)):
		return "队长 / 当前同行"
	var follow_order: int = int(summary.get("follow_order", 0))
	var battle_priority: int = int(summary.get("battle_priority", follow_order))
	return "跟随第 %d / 战斗优先 %d" % [follow_order, battle_priority]


func _party_hp_text(summary: Dictionary) -> String:
	var attributes: Dictionary = summary.get("attributes", {}) as Dictionary
	var effective: Dictionary = summary.get("effective_attributes", attributes) as Dictionary
	var hp: int = int(summary.get("hp", attributes.get("hp", 0)))
	var max_hp: int = int(summary.get("max_hp", effective.get("max_hp", 1)))
	return "HP %d/%d" % [hp, max(1, max_hp)]


func _get_actor_summary() -> Dictionary:
	if _actor == null or not is_instance_valid(_actor):
		return {}
	return _actor.get_summary()


func _draw_portrait() -> void:
	if _portrait_panel == null:
		return
	var rect: Rect2 = Rect2(Vector2.ZERO, _portrait_panel.size)
	_portrait_panel.draw_rect(rect, Color(0.022, 0.028, 0.030, 1.0), true)
	var center: Vector2 = rect.size * 0.5 + Vector2(0.0, 22.0)
	var ring_color: Color = Color(0.68, 0.58, 0.42, 0.12)
	for radius in [92.0, 128.0, 164.0]:
		_portrait_panel.draw_arc(center, radius, 0.0, TAU, 96, ring_color, 1.2)

	var summary: Dictionary = _get_selected_member_summary()
	var appearance: Dictionary = summary.get("appearance", {}) as Dictionary
	var portrait: Dictionary = appearance.get("portrait", {}) as Dictionary
	var source: String = str(portrait.get("full", appearance.get("portrait_source", "")))
	var texture: Texture2D = _load_portrait_texture(source)
	if texture == null:
		return

	var texture_size: Vector2 = texture.get_size()
	if texture_size.x <= 0.0 or texture_size.y <= 0.0:
		return
	var target: Rect2 = rect.grow(-12.0)
	var scale: float = min(target.size.x / texture_size.x, target.size.y / texture_size.y)
	var draw_size: Vector2 = texture_size * scale
	var draw_position := Vector2(
		target.position.x + (target.size.x - draw_size.x) * 0.5,
		target.position.y + target.size.y - draw_size.y
	)
	_portrait_panel.draw_texture_rect(texture, Rect2(draw_position, draw_size), false)


func _load_portrait_texture(source: String) -> Texture2D:
	if source.is_empty():
		return null
	if _portrait_texture_cache.has(source):
		return _portrait_texture_cache.get(source, null) as Texture2D
	if ResourceLoader.exists(source):
		var loaded_texture: Texture2D = load(source) as Texture2D
		_portrait_texture_cache[source] = loaded_texture
		return loaded_texture
	if source.begins_with("res://") and not FileAccess.file_exists(source):
		_portrait_texture_cache[source] = null
		return null

	var image := Image.new()
	var error: Error = image.load(source)
	if error != OK:
		_portrait_texture_cache[source] = null
		return null
	var image_texture: ImageTexture = ImageTexture.create_from_image(image)
	_portrait_texture_cache[source] = image_texture
	return image_texture


func _make_plain_label(text: String) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.add_theme_color_override("font_color", Color(0.90, 0.90, 0.84))
	return label


func _make_empty_label(text: String) -> Label:
	var label: Label = _make_plain_label(text)
	label.modulate = Color(0.74, 0.74, 0.70)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _make_separator() -> HSeparator:
	return HSeparator.new()


func _format_effective_attribute(base_attributes: Dictionary, effective_attributes: Dictionary, attribute_id: String) -> String:
	var base_value: int = int(base_attributes.get(attribute_id, 0))
	var effective_value: int = int(effective_attributes.get(attribute_id, base_value))
	if effective_value == base_value:
		return str(base_value)
	var delta: int = effective_value - base_value
	var prefix: String = "+" if delta > 0 else ""
	return "%d (%s%d)" % [effective_value, prefix, delta]


func _skill_short_detail(skill: Dictionary) -> String:
	return "%s / 射程 %d" % [
		_target_type_label(str(skill.get("target_type", ""))),
		int(skill.get("range", 0)),
	]


func _area_label(skill: Dictionary) -> String:
	if str(skill.get("area", "single")) == "radius":
		return "范围 %d" % int(skill.get("radius", 0))
	return "单体"


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


func _equipment_icon(slot_id: String) -> String:
	match slot_id:
		"weapon":
			return "W"
		"offhand":
			return "O"
		"head":
			return "H"
		"body":
			return "B"
		"accessory":
			return "A"
		"tool":
			return "T"
		_:
			return "-"


func _kind_label(kind: String) -> String:
	match kind:
		"player":
			return "玩家"
		"companion":
			return "同伴"
		"npc":
			return "NPC"
		"enemy":
			return "敌人"
		_:
			return kind


func _identity_occupation(identity: Dictionary) -> String:
	var occupation: String = str(identity.get("occupation", ""))
	match occupation:
		"wanderer":
			return "冒险者"
		"guard":
			return "守卫"
		_:
			return occupation if not occupation.is_empty() else "未知身份"


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


func _solid_colors(count: int, color: Color) -> PackedColorArray:
	var colors: PackedColorArray = PackedColorArray()
	for _index in range(count):
		colors.append(color)
	return colors


func _clear_children(parent: Node) -> void:
	for child in parent.get_children():
		child.queue_free()


func _request_close() -> void:
	close_requested.emit()

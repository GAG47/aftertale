class_name CharacterPanel
extends Control

signal close_requested()
signal character_action_requested(action_type: String, target: Dictionary)

const DETAIL_PAGE := 0
const UPGRADE_PAGE := 1
const MAX_SKILL_SLOTS := 4
const EQUIPMENT_SLOTS := ["weapon", "offhand", "head", "body", "accessory", "tool"]

var _actor: CharacterEntity
var _party_summaries: Array[Dictionary] = []
var _selected_member_id: String = ""
var _selected_skill_id: String = ""
var _current_page: int = DETAIL_PAGE
var _portrait_texture_cache: Dictionary = {}

@onready var _detail_tab: Button = $CharacterMenuRoot/Layout/TopBar/DetailTab
@onready var _upgrade_tab: Button = $CharacterMenuRoot/Layout/TopBar/UpgradeTab
@onready var _close_button: Button = $CharacterMenuRoot/Layout/TopBar/CloseButton
@onready var _detail_page: Control = $CharacterMenuRoot/Layout/PageStack/DetailPage
@onready var _upgrade_page: Control = $CharacterMenuRoot/Layout/PageStack/UpgradePage

@onready var _name_label: Label = $CharacterMenuRoot/Layout/PageStack/DetailPage/LeftStatsPanel/Margin/Content/CharacterHeader/Name
@onready var _id_label: Label = $CharacterMenuRoot/Layout/PageStack/DetailPage/LeftStatsPanel/Margin/Content/CharacterHeader/Id
@onready var _identity_label: Label = $CharacterMenuRoot/Layout/PageStack/DetailPage/LeftStatsPanel/Margin/Content/CharacterHeader/Identity
@onready var _level_label: Label = $CharacterMenuRoot/Layout/PageStack/DetailPage/LeftStatsPanel/Margin/Content/LevelRow/Level
@onready var _experience_label: Label = $CharacterMenuRoot/Layout/PageStack/DetailPage/LeftStatsPanel/Margin/Content/LevelRow/Experience
@onready var _speed_value: Label = $CharacterMenuRoot/Layout/PageStack/DetailPage/LeftStatsPanel/Margin/Content/SpeedRow/Value
@onready var _resource_root: Control = $CharacterMenuRoot/Layout/PageStack/DetailPage/LeftStatsPanel/Margin/Content/ResourceBars
@onready var _attribute_grid: GridContainer = $CharacterMenuRoot/Layout/PageStack/DetailPage/LeftStatsPanel/Margin/Content/AttributeGrid

@onready var _portrait_backdrop: Control = $CharacterMenuRoot/Layout/PageStack/DetailPage/CenterPortraitPanel/Backdrop
@onready var _portrait: TextureRect = $CharacterMenuRoot/Layout/PageStack/DetailPage/CenterPortraitPanel/Portrait
@onready var _character_index: Label = $CharacterMenuRoot/Layout/PageStack/DetailPage/CenterPortraitPanel/CharacterIndex
@onready var _previous_button: Button = $CharacterMenuRoot/Layout/PageStack/DetailPage/CenterPortraitPanel/PreviousButton
@onready var _next_button: Button = $CharacterMenuRoot/Layout/PageStack/DetailPage/CenterPortraitPanel/NextButton

@onready var _skill_rows: Array[Button] = [
	$CharacterMenuRoot/Layout/PageStack/DetailPage/RightInfoPanel/SkillSummaryPanel/Margin/Content/SkillRows/Skill0,
	$CharacterMenuRoot/Layout/PageStack/DetailPage/RightInfoPanel/SkillSummaryPanel/Margin/Content/SkillRows/Skill1,
	$CharacterMenuRoot/Layout/PageStack/DetailPage/RightInfoPanel/SkillSummaryPanel/Margin/Content/SkillRows/Skill2,
	$CharacterMenuRoot/Layout/PageStack/DetailPage/RightInfoPanel/SkillSummaryPanel/Margin/Content/SkillRows/Skill3,
]
@onready var _equipment_grid: GridContainer = $CharacterMenuRoot/Layout/PageStack/DetailPage/RightInfoPanel/EquipmentSummaryPanel/Margin/Content/EquipmentGrid

@onready var _upgrade_skill_buttons: Array[Button] = [
	$CharacterMenuRoot/Layout/PageStack/UpgradePage/SkillListPanel/Margin/Content/SkillButtons/Skill0,
	$CharacterMenuRoot/Layout/PageStack/UpgradePage/SkillListPanel/Margin/Content/SkillButtons/Skill1,
	$CharacterMenuRoot/Layout/PageStack/UpgradePage/SkillListPanel/Margin/Content/SkillButtons/Skill2,
	$CharacterMenuRoot/Layout/PageStack/UpgradePage/SkillListPanel/Margin/Content/SkillButtons/Skill3,
]
@onready var _upgrade_title: Label = $CharacterMenuRoot/Layout/PageStack/UpgradePage/SkillDetailPanel/Margin/Content/Title
@onready var _upgrade_type: Label = $CharacterMenuRoot/Layout/PageStack/UpgradePage/SkillDetailPanel/Margin/Content/Type
@onready var _upgrade_meta: Label = $CharacterMenuRoot/Layout/PageStack/UpgradePage/SkillDetailPanel/Margin/Content/Meta
@onready var _upgrade_description: Label = $CharacterMenuRoot/Layout/PageStack/UpgradePage/SkillDetailPanel/Margin/Content/Description


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	_detail_tab.pressed.connect(_show_page.bind(DETAIL_PAGE))
	_upgrade_tab.pressed.connect(_show_page.bind(UPGRADE_PAGE))
	_close_button.pressed.connect(_request_close)
	_previous_button.pressed.connect(_switch_character.bind(-1))
	_next_button.pressed.connect(_switch_character.bind(1))
	_portrait_backdrop.draw.connect(_draw_portrait_backdrop)
	for index in range(MAX_SKILL_SLOTS):
		_skill_rows[index].pressed.connect(_select_skill_slot.bind(index))
		_upgrade_skill_buttons[index].pressed.connect(_select_skill_slot.bind(index))
	_show_page(DETAIL_PAGE)


func open_for_actor(actor: CharacterEntity) -> void:
	_actor = actor
	_selected_member_id = actor.character_id if actor != null and is_instance_valid(actor) else ""
	_selected_skill_id = ""
	visible = true
	_show_page(DETAIL_PAGE)
	refresh()


func close_panel() -> void:
	visible = false


func is_open() -> bool:
	return visible


func refresh() -> void:
	_refresh_party_data()
	var summary: Dictionary = _get_selected_member_summary()
	_refresh_character_details(summary)
	_refresh_skill_summary(summary)
	_refresh_equipment_summary(summary)
	_refresh_upgrade_page(summary)


func _refresh_character_details(summary: Dictionary) -> void:
	var character_id: String = _member_id_from_summary(summary)
	var attributes: Dictionary = summary.get("attributes", {}) as Dictionary
	var effective: Dictionary = summary.get("effective_attributes", attributes) as Dictionary
	var identity: Dictionary = summary.get("identity", {}) as Dictionary
	var level: int = max(1, int(attributes.get("level", 1)))
	var experience: int = max(0, int(attributes.get("experience", attributes.get("exp", 0))))
	var experience_max: int = max(1, int(attributes.get("experience_to_next", level * 1000)))

	_name_label.text = str(summary.get("display_name", character_id if not character_id.is_empty() else "未知角色"))
	_id_label.text = "ID: %s" % (character_id if not character_id.is_empty() else "--")
	_identity_label.text = "%s / %s" % [
		_kind_label(str(summary.get("kind", ""))),
		_occupation_label(str(identity.get("occupation", ""))),
	]
	_level_label.text = "Lv. %d" % level
	_experience_label.text = "经验值 %d / %d" % [experience, experience_max]

	var hp: int = int(summary.get("hp", attributes.get("hp", 0)))
	var max_hp: int = max(1, int(summary.get("max_hp", effective.get("max_hp", hp))))
	var max_mp: int = max(1, int(effective.get("max_mp", int(effective.get("intellect", 1)) * 3)))
	var current_mp: int = clampi(int(summary.get("mp", summary.get("magic_points", max_mp))), 0, max_mp)
	var max_ap: int = max(1, int(effective.get("action_points", 2)))
	var current_ap: int = clampi(int(summary.get("ap", summary.get("action_points", max_ap))), 0, max_ap)
	_set_resource_row("HP", hp, max_hp)
	_set_resource_row("MP", current_mp, max_mp)
	_set_resource_row("AP", current_ap, max_ap)

	var strength: int = int(effective.get("strength", 0))
	var agility: int = int(effective.get("agility", 0))
	var intellect: int = int(effective.get("intellect", 0))
	var vitality: int = int(effective.get("vitality", 0))
	_speed_value.text = str(int(effective.get("speed", agility)))
	_set_attribute_value("StrengthValue", _format_effective_attribute(attributes, effective, "strength"))
	_set_attribute_value("AgilityValue", _format_effective_attribute(attributes, effective, "agility"))
	_set_attribute_value("IntellectValue", _format_effective_attribute(attributes, effective, "intellect"))
	_set_attribute_value("VitalityValue", _format_effective_attribute(attributes, effective, "vitality"))
	_set_attribute_value("PhysicalAttackValue", str(int(effective.get("physical_attack", strength + 10))))
	_set_attribute_value("PhysicalDefenseValue", str(int(effective.get("physical_defense", vitality + 8))))
	_set_attribute_value("MagicDefenseValue", str(int(effective.get("magic_defense", intellect + 8))))
	_set_attribute_value("HitValue", "%d%%" % int(effective.get("hit", 80 + agility * 2)))
	_set_attribute_value("EvasionValue", "%d%%" % int(effective.get("evasion", max(0, agility * 2))))
	_set_attribute_value("CritValue", "%d%%" % int(effective.get("critical_rate", max(1, agility))))

	_refresh_portrait(summary)
	var selected_index: int = _selected_member_index()
	_character_index.text = "%d / %d" % [selected_index + 1, max(1, _party_summaries.size())]
	var can_switch: bool = _party_summaries.size() > 1
	_previous_button.disabled = not can_switch
	_next_button.disabled = not can_switch
	_portrait_backdrop.queue_redraw()


func _refresh_skill_summary(summary: Dictionary) -> void:
	var skill_ids: Array = summary.get("skills", []) as Array
	if _selected_skill_id.is_empty() or not skill_ids.has(_selected_skill_id):
		_selected_skill_id = str(skill_ids[0]) if not skill_ids.is_empty() else ""

	for index in range(MAX_SKILL_SLOTS):
		var row: Button = _skill_rows[index]
		if index >= skill_ids.size():
			row.visible = false
			continue
		row.visible = true
		var skill_id: String = str(skill_ids[index])
		var skill: Dictionary = SkillSystem.get_skill(skill_id)
		if skill.is_empty():
			skill = {"id": skill_id, "display_name": skill_id, "description": ""}
		row.set_meta("skill_id", skill_id)
		row.button_pressed = skill_id == _selected_skill_id
		(row.get_node("Row/Text/Name") as Label).text = str(skill.get("display_name", skill_id))
		(row.get_node("Row/Text/Meta") as Label).text = "%s · 射程 %d · %s" % [
			_target_type_label(str(skill.get("target_type", ""))),
			int(skill.get("range", 0)),
			_area_label(skill),
		]
		(row.get_node("Row/Text/Description") as Label).text = str(skill.get("description", ""))
		(row.get_node("Row/Cost") as Label).text = "AP %d" % int(skill.get("ap_cost", 0))


func _refresh_equipment_summary(summary: Dictionary) -> void:
	var equipment: Dictionary = summary.get("equipment_slots", {}) as Dictionary
	for slot_id in EQUIPMENT_SLOTS:
		var value_label: Label = _equipment_grid.get_node("%sValue" % _pascal_case(slot_id)) as Label
		var slot_data: Dictionary = equipment.get(slot_id, {}) as Dictionary
		var item_name: String = str(slot_data.get("display_name", ""))
		value_label.text = item_name if not item_name.is_empty() else "未装备"
		value_label.add_theme_color_override(
			"font_color",
			Color(1.0, 0.58, 0.22) if not item_name.is_empty() else Color(0.5, 0.54, 0.57)
		)


func _refresh_upgrade_page(summary: Dictionary) -> void:
	var skill_ids: Array = summary.get("skills", []) as Array
	for index in range(MAX_SKILL_SLOTS):
		var button: Button = _upgrade_skill_buttons[index]
		if index >= skill_ids.size():
			button.visible = false
			continue
		button.visible = true
		var skill_id: String = str(skill_ids[index])
		var skill: Dictionary = SkillSystem.get_skill(skill_id)
		button.set_meta("skill_id", skill_id)
		button.text = str(skill.get("display_name", skill_id))
		button.button_pressed = skill_id == _selected_skill_id
	_refresh_upgrade_skill_detail()


func _refresh_upgrade_skill_detail() -> void:
	var skill: Dictionary = SkillSystem.get_skill(_selected_skill_id)
	if skill.is_empty():
		_upgrade_title.text = "选择技能"
		_upgrade_type.text = "类型：--"
		_upgrade_meta.text = "AP 0 · 射程 0 · 目标 --"
		_upgrade_description.text = "当前角色没有可显示的技能。"
		return
	_upgrade_title.text = str(skill.get("display_name", _selected_skill_id))
	_upgrade_type.text = "类型：%s" % _skill_type_label(str(skill.get("skill_type", "")))
	_upgrade_meta.text = "AP %d · MP %d · 射程 %d · 目标 %s" % [
		int(skill.get("ap_cost", 0)),
		int(skill.get("mp_cost", 0)),
		int(skill.get("range", 0)),
		_target_type_label(str(skill.get("target_type", ""))),
	]
	_upgrade_description.text = str(skill.get("description", ""))


func _refresh_party_data() -> void:
	_party_summaries = PartySystem.get_party_summary()
	var actor_summary: Dictionary = _get_actor_summary()
	if _party_summaries.is_empty() and not actor_summary.is_empty():
		var fallback: Dictionary = actor_summary.duplicate(true)
		fallback["party_member_id"] = str(fallback.get("id", ""))
		fallback["is_party_leader"] = true
		_party_summaries.append(fallback)
	if _party_summaries.is_empty():
		_selected_member_id = ""
		return
	if _selected_member_id.is_empty() or _get_selected_member_summary().is_empty():
		_selected_member_id = _member_id_from_summary(_party_summaries[0])


func _switch_character(direction: int) -> void:
	if _party_summaries.size() <= 1:
		return
	var current_index: int = _selected_member_index()
	var next_index: int = posmod(current_index + direction, _party_summaries.size())
	_selected_member_id = _member_id_from_summary(_party_summaries[next_index])
	_selected_skill_id = ""
	refresh()


func _select_skill_slot(index: int) -> void:
	var summary: Dictionary = _get_selected_member_summary()
	var skill_ids: Array = summary.get("skills", []) as Array
	if index < 0 or index >= skill_ids.size():
		return
	_selected_skill_id = str(skill_ids[index])
	_refresh_skill_summary(summary)
	_refresh_upgrade_page(summary)


func _show_page(page: int) -> void:
	_current_page = page
	_detail_page.visible = page == DETAIL_PAGE
	_upgrade_page.visible = page == UPGRADE_PAGE
	_detail_tab.button_pressed = page == DETAIL_PAGE
	_upgrade_tab.button_pressed = page == UPGRADE_PAGE


func _unhandled_key_input(event: InputEvent) -> void:
	if not visible or not event.pressed or event.echo:
		return
	if event.keycode == KEY_ESCAPE or event.keycode == KEY_E:
		_request_close()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_A:
		_switch_character(-1)
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_D:
		_switch_character(1)
		get_viewport().set_input_as_handled()


func _set_resource_row(row_name: String, value: int, max_value: int) -> void:
	var row: Control = _resource_root.get_node(row_name) as Control
	var bar: ProgressBar = row.get_node("Bar") as ProgressBar
	var value_label: Label = row.get_node("Value") as Label
	bar.max_value = max(1, max_value)
	bar.value = clampi(value, 0, max(1, max_value))
	value_label.text = "%d / %d" % [value, max_value]


func _set_attribute_value(node_name: String, value: String) -> void:
	var label: Label = _attribute_grid.get_node(node_name) as Label
	label.text = value
	label.add_theme_color_override("font_color", Color(0.96, 0.91, 0.82))


func _refresh_portrait(summary: Dictionary) -> void:
	var appearance: Dictionary = summary.get("appearance", {}) as Dictionary
	var portrait_data: Dictionary = appearance.get("portrait", {}) as Dictionary
	var source: String = str(portrait_data.get("full", appearance.get("portrait_source", "")))
	_portrait.texture = _load_portrait_texture(source)


func _draw_portrait_backdrop() -> void:
	var size: Vector2 = _portrait_backdrop.size
	var center: Vector2 = Vector2(size.x * 0.5, size.y * 0.57)
	_portrait_backdrop.draw_rect(Rect2(Vector2.ZERO, size), Color(0.025, 0.043, 0.065, 0.48), true)
	for radius_factor in [0.23, 0.34, 0.45]:
		var radius: float = min(size.x, size.y) * radius_factor
		_portrait_backdrop.draw_arc(center, radius, 0.0, TAU, 96, Color(0.85, 0.58, 0.31, 0.14), 1.0)
	for index in range(12):
		var angle: float = TAU * float(index) / 12.0
		var inner: Vector2 = center + Vector2(cos(angle), sin(angle)) * min(size.x, size.y) * 0.18
		var outer: Vector2 = center + Vector2(cos(angle), sin(angle)) * min(size.x, size.y) * 0.47
		_portrait_backdrop.draw_line(inner, outer, Color(0.35, 0.58, 0.72, 0.07), 1.0)
	_portrait_backdrop.draw_line(
		Vector2(size.x * 0.08, size.y - 18.0),
		Vector2(size.x * 0.92, size.y - 18.0),
		Color(0.95, 0.55, 0.22, 0.25),
		1.0
	)


func _load_portrait_texture(source: String) -> Texture2D:
	if source.is_empty():
		return null
	if _portrait_texture_cache.has(source):
		return _portrait_texture_cache.get(source, null) as Texture2D
	if ResourceLoader.exists(source):
		var texture: Texture2D = load(source) as Texture2D
		_portrait_texture_cache[source] = texture
		return texture
	var image := Image.new()
	if image.load(source) != OK:
		_portrait_texture_cache[source] = null
		return null
	var image_texture: ImageTexture = ImageTexture.create_from_image(image)
	_portrait_texture_cache[source] = image_texture
	return image_texture


func _get_selected_member_summary() -> Dictionary:
	for summary in _party_summaries:
		if _member_id_from_summary(summary) == _selected_member_id:
			return summary
	return {}


func _selected_member_index() -> int:
	for index in range(_party_summaries.size()):
		if _member_id_from_summary(_party_summaries[index]) == _selected_member_id:
			return index
	return 0


func _member_id_from_summary(summary: Dictionary) -> String:
	return str(summary.get("party_member_id", summary.get("id", "")))


func _get_actor_summary() -> Dictionary:
	if _actor == null or not is_instance_valid(_actor):
		return {}
	return _actor.get_summary()


func _format_effective_attribute(base_attributes: Dictionary, effective_attributes: Dictionary, attribute_id: String) -> String:
	var base_value: int = int(base_attributes.get(attribute_id, 0))
	var effective_value: int = int(effective_attributes.get(attribute_id, base_value))
	if effective_value == base_value:
		return str(base_value)
	var delta: int = effective_value - base_value
	return "%d (%+d)" % [effective_value, delta]


func _target_type_label(target_type: String) -> String:
	match target_type:
		"self":
			return "自身"
		"enemy":
			return "敌方"
		"ally":
			return "友方"
		"ally_or_self":
			return "友方 / 自身"
		_:
			return target_type if not target_type.is_empty() else "--"


func _area_label(skill: Dictionary) -> String:
	match str(skill.get("area", "single")):
		"radius":
			return "范围 %d" % int(skill.get("radius", 0))
		"line":
			return "直线"
		_:
			return "单体"


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
			return kind if not kind.is_empty() else "角色"


func _occupation_label(occupation: String) -> String:
	match occupation:
		"wanderer":
			return "冒险者"
		"guard":
			return "守卫"
		"villager":
			return "村民"
		"training target":
			return "训练目标"
		_:
			return occupation if not occupation.is_empty() else "未知身份"


func _skill_type_label(skill_type: String) -> String:
	return "战斗技能" if skill_type == "battle" else (skill_type if not skill_type.is_empty() else "--")


func _pascal_case(value: String) -> String:
	if value.is_empty():
		return value
	return value.left(1).to_upper() + value.substr(1)


func _request_close() -> void:
	close_requested.emit()

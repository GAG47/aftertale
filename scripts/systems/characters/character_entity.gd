class_name CharacterEntity
extends Node2D

signal grid_position_changed(character_id: String, previous_cell: Vector2i, new_cell: Vector2i)
signal facing_changed(character_id: String, facing: String)

const KIND_PLAYER := "player"
const KIND_NPC := "npc"
const KIND_ENEMY := "enemy"
const KIND_COMPANION := "companion"

const FACING_UP := "up"
const FACING_DOWN := "down"
const FACING_LEFT := "left"
const FACING_RIGHT := "right"
const CharacterAppearanceRendererScript := preload("res://scripts/systems/characters/character_appearance_renderer.gd")

@export var character_id: String = ""
@export var display_name: String = ""
@export var character_kind: String = KIND_NPC
@export var grid_position: Vector2i = Vector2i.ZERO
@export var facing: String = FACING_DOWN
@export var faction_id: String = "none"
@export var is_player_controlled: bool = false
@export var is_interactable: bool = false
@export var is_combatable: bool = false
@export var blocks_movement: bool = true
@export_file("*.json") var dialogue_source: String = ""
@export_file("*.json") var definition_source: String = ""

var attributes: Dictionary = {}
var identity: Dictionary = {}
var relation_slots: Dictionary = {}
var appearance_profile: Dictionary = {}
var appearance: Dictionary = {}
var skills: Array[String] = []
var schedule: Array[Dictionary] = []
var current_schedule_entry_id: String = ""
var current_schedule_anchor_id: String = ""
var current_activity_type: String = "idle"
var current_activity: String = "idle"
var current_movement_mode: String = "walk"
var current_interruption_reason: String = ""
var current_interruption_priority: int = 0
var scheduled_location_id: String = ""
var hp: int = 1
var max_hp: int = 1
var is_defeated: bool = false
var inventory: Inventory
var equipment_slots: EquipmentSlots
var location_root: Node
var _movement_tween: Tween
var _battle_presentation_active: bool = false
var _battle_presentation_current: bool = false
var _battle_presentation_team: String = ""
var _battle_presentation_hp: int = 0
var _battle_presentation_max_hp: int = 1
var _battle_presentation_ap: int = 0
var _battle_presentation_max_ap: int = 1
var _battle_presentation_status: String = ""
var _battle_effect_color: Color = Color.TRANSPARENT
var _battle_effect_alpha: float = 0.0
var _battle_effect_radius: float = 18.0
var _battle_effect_tween: Tween


func configure(definition: Dictionary, spawn_data: Dictionary, parent_location: Node) -> void:
	character_id = str(spawn_data.get("id", definition.get("id", character_id)))
	display_name = str(spawn_data.get("display_name", definition.get("display_name", character_id)))
	definition_source = str(spawn_data.get("source", definition.get("source", definition_source)))
	character_kind = str(spawn_data.get("character_kind", definition.get("character_kind", character_kind)))
	facing = str(spawn_data.get("facing", definition.get("facing", facing)))
	faction_id = str(spawn_data.get("faction_id", definition.get("faction_id", faction_id)))
	is_player_controlled = bool(spawn_data.get("is_player_controlled", definition.get("is_player_controlled", is_player_controlled)))
	is_interactable = bool(spawn_data.get("is_interactable", definition.get("is_interactable", is_interactable)))
	is_combatable = bool(spawn_data.get("is_combatable", definition.get("is_combatable", is_combatable)))
	blocks_movement = bool(spawn_data.get("blocks_movement", definition.get("blocks_movement", blocks_movement)))
	dialogue_source = str(spawn_data.get("dialogue_source", definition.get("dialogue_source", dialogue_source)))

	var definition_attributes: Dictionary = definition.get("attributes", {}) as Dictionary
	var spawn_attributes: Dictionary = spawn_data.get("attributes", {}) as Dictionary
	attributes = definition_attributes.duplicate(true)
	attributes.merge(spawn_attributes, true)
	max_hp = max(1, int(attributes.get("max_hp", int(attributes.get("vitality", 1)) * 4)))
	hp = clampi(int(attributes.get("hp", max_hp)), 0, max_hp)
	is_defeated = hp <= 0
	attributes["max_hp"] = max_hp
	attributes["hp"] = hp

	var definition_identity: Dictionary = definition.get("identity", {}) as Dictionary
	var spawn_identity: Dictionary = spawn_data.get("identity", {}) as Dictionary
	identity = definition_identity.duplicate(true)
	identity.merge(spawn_identity, true)

	var definition_relations: Dictionary = definition.get("relation_slots", {}) as Dictionary
	var spawn_relations: Dictionary = spawn_data.get("relation_slots", {}) as Dictionary
	relation_slots = definition_relations.duplicate(true)
	relation_slots.merge(spawn_relations, true)

	appearance_profile = _merge_dictionaries_deep(
		definition.get("appearance_profile", {}) as Dictionary,
		spawn_data.get("appearance_profile", {}) as Dictionary
	)
	_fill_default_appearance_profile()
	appearance = _merge_dictionaries_deep(
		definition.get("appearance", {}) as Dictionary,
		spawn_data.get("appearance", {}) as Dictionary
	)

	skills.clear()
	var skill_rows: Array = spawn_data.get("skills", definition.get("skills", ["basic_attack"])) as Array
	for skill_value in skill_rows:
		var skill_id: String = str(skill_value)
		if skill_id.is_empty():
			continue
		skills.append(skill_id)
	if skills.is_empty():
		skills.append("basic_attack")

	schedule.clear()
	var schedule_rows: Array = spawn_data.get("schedule", definition.get("schedule", [])) as Array
	for schedule_value in schedule_rows:
		var schedule_entry: Dictionary = schedule_value as Dictionary
		schedule.append(schedule_entry.duplicate(true))

	current_schedule_entry_id = str(spawn_data.get("schedule_entry_id", ""))
	current_schedule_anchor_id = str(spawn_data.get("anchor_id", current_schedule_anchor_id))
	current_activity_type = str(spawn_data.get("activity_type", current_activity_type))
	current_activity = str(spawn_data.get("activity", current_activity))
	current_movement_mode = str(spawn_data.get("movement", current_movement_mode))
	scheduled_location_id = str(spawn_data.get("scheduled_location_id", ""))

	var inventory_capacity: int = int(spawn_data.get("inventory_capacity", definition.get("inventory_capacity", 24)))
	inventory = Inventory.new()
	inventory.configure(character_id, inventory_capacity)

	var starting_items: Array = definition.get("inventory", []) as Array
	for item_value in starting_items:
		var item_entry: Dictionary = item_value as Dictionary
		var item_definition: Dictionary = _read_item_definition(str(item_entry.get("source", "")))
		if item_definition.is_empty():
			continue
		inventory.add_item(item_definition, int(item_entry.get("quantity", 1)))

	equipment_slots = EquipmentSlots.new()
	equipment_slots.configure(character_id)
	_apply_default_equipment(definition, spawn_data)

	var position_data: Dictionary = spawn_data.get("grid_position", {}) as Dictionary
	grid_position = Vector2i(int(position_data.get("x", grid_position.x)), int(position_data.get("y", grid_position.y)))
	location_root = parent_location
	name = character_id
	_update_world_position()
	queue_redraw()


func get_runtime_state() -> Dictionary:
	return {
		"character_id": character_id,
		"attributes": attributes.duplicate(true),
		"hp": hp,
		"max_hp": max_hp,
		"is_defeated": is_defeated,
		"inventory": inventory.get_runtime_state() if inventory != null else {},
		"equipment_slots": equipment_slots.get_runtime_state() if equipment_slots != null else {},
	}


func apply_runtime_state(state: Dictionary) -> void:
	if state.is_empty():
		return

	var saved_attributes: Dictionary = state.get("attributes", {}) as Dictionary
	attributes.merge(saved_attributes, true)
	max_hp = max(1, int(state.get("max_hp", attributes.get("max_hp", max_hp))))
	hp = clampi(int(state.get("hp", attributes.get("hp", hp))), 0, max_hp)
	is_defeated = bool(state.get("is_defeated", hp <= 0))
	attributes["max_hp"] = max_hp
	attributes["hp"] = hp
	attributes["defeated"] = is_defeated

	var inventory_state: Dictionary = state.get("inventory", {}) as Dictionary
	if inventory != null and not inventory_state.is_empty():
		inventory.apply_runtime_state(inventory_state)

	var equipment_state: Dictionary = state.get("equipment_slots", {}) as Dictionary
	if equipment_slots != null and not equipment_state.is_empty():
		if equipment_state.has("equipped_items"):
			equipment_slots.apply_runtime_state(equipment_state)
		else:
			equipment_slots.slots.merge(equipment_state, true)

	queue_redraw()


func set_grid_position(new_cell: Vector2i) -> void:
	if grid_position == new_cell:
		return

	var previous_cell: Vector2i = grid_position
	grid_position = new_cell
	_update_world_position(true)
	grid_position_changed.emit(character_id, previous_cell, grid_position)


func set_facing(new_facing: String) -> void:
	if facing == new_facing:
		return

	facing = new_facing
	facing_changed.emit(character_id, facing)
	queue_redraw()


func set_schedule_state(entry: Dictionary, location_id: String) -> void:
	current_schedule_entry_id = str(entry.get("id", ""))
	current_schedule_anchor_id = str(entry.get("anchor_id", current_schedule_anchor_id))
	current_activity_type = str(entry.get("activity_type", current_activity_type))
	current_activity = str(entry.get("activity", current_activity))
	current_movement_mode = str(entry.get("movement", current_movement_mode))
	scheduled_location_id = location_id
	queue_redraw()


func set_interruption_state(reason: String, priority: int) -> void:
	current_interruption_reason = reason
	current_interruption_priority = max(0, priority)
	queue_redraw()


func clear_interruption_state(reason: String = "") -> void:
	if not reason.is_empty() and current_interruption_reason != reason:
		return

	current_interruption_reason = ""
	current_interruption_priority = 0
	queue_redraw()


func set_combat_stats(new_hp: int, new_max_hp: int, defeated: bool) -> void:
	max_hp = max(1, new_max_hp)
	hp = clampi(new_hp, 0, max_hp)
	is_defeated = defeated or hp <= 0
	attributes["max_hp"] = max_hp
	attributes["hp"] = hp
	attributes["defeated"] = is_defeated
	queue_redraw()


func play_battle_effect(effect_type: String) -> void:
	var color: Color = Color(1.0, 0.88, 0.28, 0.85)
	match effect_type:
		"damage":
			color = Color(1.0, 0.24, 0.18, 0.88)
		"heal":
			color = Color(0.35, 1.0, 0.48, 0.82)
		"status":
			color = Color(0.74, 0.52, 1.0, 0.82)
		"skill":
			color = Color(1.0, 0.82, 0.28, 0.88)

	_battle_effect_color = color
	_battle_effect_alpha = color.a
	_battle_effect_radius = 13.0
	if _battle_effect_tween != null and _battle_effect_tween.is_valid():
		_battle_effect_tween.kill()
	if not is_inside_tree():
		queue_redraw()
		return

	_battle_effect_tween = create_tween()
	_battle_effect_tween.set_parallel(true)
	_battle_effect_tween.tween_property(self, "_battle_effect_alpha", 0.0, 0.38).from(color.a)
	_battle_effect_tween.tween_property(self, "_battle_effect_radius", 27.0, 0.38).from(13.0)
	_battle_effect_tween.tween_callback(queue_redraw).set_delay(0.38)
	_battle_effect_tween.tween_method(_set_battle_effect_progress, 0.0, 1.0, 0.38)
	queue_redraw()


func set_battle_presentation(summary: Dictionary, is_current: bool) -> void:
	_battle_presentation_active = true
	_battle_presentation_current = is_current
	_battle_presentation_team = str(summary.get("team", ""))
	_battle_presentation_hp = int(summary.get("hp", hp))
	_battle_presentation_max_hp = max(1, int(summary.get("max_hp", max_hp)))
	_battle_presentation_ap = int(summary.get("action_points", 0))
	_battle_presentation_max_ap = max(1, int(summary.get("max_action_points", 1)))
	_battle_presentation_status = str(summary.get("status_text", ""))
	queue_redraw()


func clear_battle_presentation() -> void:
	if not _battle_presentation_active:
		return

	_battle_presentation_active = false
	_battle_presentation_current = false
	_battle_presentation_team = ""
	_battle_presentation_status = ""
	queue_redraw()


func face_direction(direction: Vector2i) -> void:
	if direction == Vector2i.UP:
		set_facing(FACING_UP)
	elif direction == Vector2i.DOWN:
		set_facing(FACING_DOWN)
	elif direction == Vector2i.LEFT:
		set_facing(FACING_LEFT)
	elif direction == Vector2i.RIGHT:
		set_facing(FACING_RIGHT)


func get_summary() -> Dictionary:
	return {
		"id": character_id,
		"display_name": display_name,
		"kind": character_kind,
		"grid_position": grid_position,
		"facing": facing,
		"faction_id": faction_id,
		"is_player_controlled": is_player_controlled,
		"is_interactable": is_interactable,
		"is_combatable": is_combatable,
		"blocks_movement": blocks_movement,
		"dialogue_source": dialogue_source,
		"definition_source": definition_source,
		"attributes": attributes,
		"identity": identity,
		"relation_slots": relation_slots,
		"appearance_profile": appearance_profile,
		"appearance": appearance,
		"skills": skills.duplicate(),
		"schedule_entry_id": current_schedule_entry_id,
		"anchor_id": current_schedule_anchor_id,
		"activity_type": current_activity_type,
		"activity": current_activity,
		"movement": current_movement_mode,
		"interruption_reason": current_interruption_reason,
		"interruption_priority": current_interruption_priority,
		"scheduled_location_id": scheduled_location_id,
		"hp": hp,
		"max_hp": max_hp,
		"is_defeated": is_defeated,
		"inventory": inventory.get_summary() if inventory != null else [],
		"equipment_slots": equipment_slots.get_detailed_summary() if equipment_slots != null else {},
		"effective_attributes": get_effective_attributes(),
	}


func get_effective_attributes() -> Dictionary:
	var effective: Dictionary = attributes.duplicate(true)
	if equipment_slots == null:
		return effective

	var bonuses: Dictionary = equipment_slots.get_attribute_bonuses()
	for key in bonuses.keys():
		var attribute_id: String = str(key)
		effective[attribute_id] = int(effective.get(attribute_id, 0)) + int(bonuses[key])

	if bonuses.has("vitality") and not bonuses.has("max_hp"):
		effective["max_hp"] = int(effective.get("max_hp", max_hp)) + int(bonuses["vitality"]) * 4

	return effective


func get_equipment_bonus_summary() -> Dictionary:
	if equipment_slots == null:
		return {}

	return equipment_slots.get_attribute_bonuses()


func _get_appearance_context() -> Dictionary:
	return {
		"character_id": character_id,
		"display_name": display_name,
		"kind": character_kind,
		"facing": facing,
		"identity": identity,
		"appearance_profile": appearance_profile,
		"appearance": appearance,
		"activity_type": current_activity_type,
		"activity": current_activity,
		"interruption_reason": current_interruption_reason,
		"is_training_dummy": _is_training_dummy(),
	}


func _fill_default_appearance_profile() -> void:
	if not appearance_profile.has("importance"):
		appearance_profile["importance"] = "important" if character_kind == KIND_PLAYER else "common"
	if not appearance_profile.has("role"):
		appearance_profile["role"] = str(identity.get("occupation", character_kind))
	if not appearance_profile.has("species"):
		appearance_profile["species"] = str(identity.get("species", "human"))
	if not appearance_profile.has("gender_hint"):
		appearance_profile["gender_hint"] = str(identity.get("gender", "neutral"))
	if not appearance_profile.has("age_hint"):
		appearance_profile["age_hint"] = _age_hint(int(identity.get("age", 30)))


func _age_hint(age: int) -> String:
	if age <= 14:
		return "child"
	if age >= 60:
		return "elder"
	if age <= 25:
		return "young"
	return "adult"


func _merge_dictionaries_deep(base: Dictionary, override: Dictionary) -> Dictionary:
	var result: Dictionary = base.duplicate(true)
	for key in override.keys():
		var override_value: Variant = override.get(key)
		var base_value: Variant = result.get(key)
		if typeof(base_value) == TYPE_DICTIONARY and typeof(override_value) == TYPE_DICTIONARY:
			result[key] = _merge_dictionaries_deep(base_value as Dictionary, override_value as Dictionary)
		else:
			result[key] = override_value
	return result


func _update_world_position(animated: bool = false) -> void:
	if location_root == null or not location_root.has_method("grid_to_world"):
		return

	var target_position: Vector2 = location_root.grid_to_world(grid_position)
	if not animated or not is_inside_tree():
		position = target_position
		return

	if _movement_tween != null and _movement_tween.is_valid():
		_movement_tween.kill()

	_movement_tween = create_tween()
	_movement_tween.set_trans(Tween.TRANS_SINE)
	_movement_tween.set_ease(Tween.EASE_OUT)
	_movement_tween.tween_property(self, "position", target_position, 0.14)


func _draw() -> void:
	CharacterAppearanceRendererScript.draw_character(self, _get_appearance_context())

	_draw_facing_marker()

	if is_interactable:
		_draw_status_badge(Vector2(10.0, -13.0), Color(1.0, 0.90, 0.28), Color(0.36, 0.26, 0.06))

	if is_combatable:
		_draw_status_badge(Vector2(-10.0, -13.0), Color(0.92, 0.22, 0.18), Color(0.34, 0.06, 0.04))

	if is_defeated:
		draw_line(Vector2(-9.0, -12.0), Vector2(9.0, 7.0), Color(0.10, 0.08, 0.06), 2.4)
		draw_line(Vector2(9.0, -12.0), Vector2(-9.0, 7.0), Color(0.10, 0.08, 0.06), 2.4)

	if _battle_presentation_active:
		_draw_battle_presentation()

	if _battle_effect_alpha > 0.01:
		_draw_battle_effect()


func _get_debug_color() -> Color:
	match character_kind:
		KIND_PLAYER:
			return Color(0.48, 0.67, 0.92)
		KIND_NPC:
			if _occupation() == "guard":
				return Color(0.44, 0.52, 0.62)
			return Color(0.43, 0.68, 0.50)
		KIND_ENEMY:
			return Color(0.74, 0.30, 0.24)
		KIND_COMPANION:
			return Color(0.46, 0.70, 0.56)
		_:
			return Color(0.62, 0.60, 0.55)


func _draw_token_shadow() -> void:
	_draw_ellipse(Vector2(0.0, 9.0), Vector2(25.0, 7.0), Color(0.0, 0.0, 0.0, 0.20))


func _draw_token_base() -> void:
	var base_color: Color = _get_base_color()
	_draw_ellipse(Vector2(0.0, 6.0), Vector2(24.0, 12.0), Color(base_color.r, base_color.g, base_color.b, 0.86))
	_draw_ellipse_outline(Vector2(0.0, 6.0), Vector2(24.0, 12.0), Color(0.08, 0.07, 0.06, 0.36), 1.3)


func _draw_character_token() -> void:
	var body_color: Color = _get_debug_color()
	var trim_color: Color = _get_trim_color()
	var skin_color: Color = Color(0.91, 0.77, 0.62)
	var hair_color: Color = _get_hair_color()

	_draw_ellipse(Vector2(0.0, 4.5), Vector2(13.5, 14.0), body_color)
	_draw_ellipse_outline(Vector2(0.0, 4.5), Vector2(13.5, 14.0), Color(0.08, 0.07, 0.06, 0.50), 1.2)
	draw_line(Vector2(-4.5, 1.0), Vector2(4.5, 1.0), trim_color, 1.4)

	draw_circle(Vector2(0.0, -7.5), 8.2, skin_color)
	draw_arc(Vector2(0.0, -7.5), 8.3, 0.0, TAU, 24, Color(0.08, 0.07, 0.06, 0.52), 1.2)
	_draw_hair(hair_color)
	_draw_face_marks()


func _draw_training_dummy_token() -> void:
	var wood: Color = Color(0.70, 0.46, 0.22)
	var dark: Color = Color(0.24, 0.13, 0.06)
	draw_line(Vector2(0.0, 8.0), Vector2(0.0, -13.0), dark, 4.8)
	draw_line(Vector2(0.0, 8.0), Vector2(0.0, -13.0), wood, 3.0)
	draw_line(Vector2(-9.0, -2.0), Vector2(9.0, -2.0), dark, 4.2)
	draw_line(Vector2(-9.0, -2.0), Vector2(9.0, -2.0), Color(0.82, 0.60, 0.32), 2.5)
	draw_circle(Vector2(0.0, -13.0), 6.8, Color(0.78, 0.56, 0.29))
	draw_arc(Vector2(0.0, -13.0), 7.0, 0.0, TAU, 20, dark, 1.4)
	draw_line(Vector2(-3.0, -14.5), Vector2(-0.8, -12.2), dark, 1.2)
	draw_line(Vector2(3.0, -14.5), Vector2(0.8, -12.2), dark, 1.2)


func _draw_hair(hair_color: Color) -> void:
	var hair := PackedVector2Array([
		Vector2(-7.5, -9.0),
		Vector2(-4.5, -15.0),
		Vector2(2.0, -16.2),
		Vector2(7.2, -11.0),
		Vector2(5.5, -6.6),
		Vector2(-6.2, -6.4),
	])
	draw_polygon(hair, _solid_colors(hair.size(), hair_color))


func _draw_face_marks() -> void:
	if facing == FACING_UP:
		return

	var eye_y: float = -7.6
	var eye_offset: float = 2.8
	if facing == FACING_LEFT:
		draw_circle(Vector2(-eye_offset, eye_y), 0.9, Color(0.12, 0.10, 0.09))
	elif facing == FACING_RIGHT:
		draw_circle(Vector2(eye_offset, eye_y), 0.9, Color(0.12, 0.10, 0.09))
	else:
		draw_circle(Vector2(-eye_offset, eye_y), 0.9, Color(0.12, 0.10, 0.09))
		draw_circle(Vector2(eye_offset, eye_y), 0.9, Color(0.12, 0.10, 0.09))


func _draw_facing_marker() -> void:
	var direction: Vector2 = _facing_vector()
	var perpendicular: Vector2 = Vector2(-direction.y, direction.x)
	var tip: Vector2 = direction * 17.0 + Vector2(0.0, 2.0)
	var base: Vector2 = direction * 11.0 + Vector2(0.0, 2.0)
	var marker := PackedVector2Array([
		tip,
		base + perpendicular * 3.5,
		base - perpendicular * 3.5,
	])
	draw_polygon(marker, _solid_colors(marker.size(), Color(1.0, 0.86, 0.28, 0.96)))
	draw_polyline(PackedVector2Array([marker[0], marker[1], marker[2], marker[0]]), Color(0.32, 0.24, 0.05, 0.70), 1.1)


func _draw_status_badge(center: Vector2, fill: Color, outline: Color) -> void:
	draw_circle(center, 3.5, fill)
	draw_arc(center, 3.7, 0.0, TAU, 14, outline, 1.0)


func _draw_battle_presentation() -> void:
	var team_color: Color = Color(0.42, 0.72, 1.0, 0.88)
	if _battle_presentation_team == BattleUnitState.TEAM_ENEMY:
		team_color = Color(1.0, 0.30, 0.24, 0.88)

	_draw_ellipse_outline(Vector2(0.0, 6.0), Vector2(28.0, 15.0), team_color, 2.0)
	if _battle_presentation_current:
		draw_arc(Vector2.ZERO, 18.0, -PI * 0.72, -PI * 0.28, 12, Color(1.0, 0.88, 0.22, 0.98), 2.6)

	_draw_small_bar(
		Vector2(-13.0, -23.0),
		Vector2(26.0, 3.2),
		_battle_presentation_hp,
		_battle_presentation_max_hp,
		Color(0.82, 0.20, 0.18, 0.96)
	)
	_draw_small_bar(
		Vector2(-13.0, -18.5),
		Vector2(26.0, 2.6),
		_battle_presentation_ap,
		_battle_presentation_max_ap,
		Color(0.32, 0.62, 1.0, 0.95)
	)

	if not _battle_presentation_status.is_empty():
		draw_circle(Vector2(13.0, -18.0), 3.2, Color(0.65, 0.48, 0.95, 0.96))
		draw_arc(Vector2(13.0, -18.0), 3.4, 0.0, TAU, 12, Color(0.18, 0.10, 0.28, 0.70), 1.0)


func _draw_battle_effect() -> void:
	var color: Color = _battle_effect_color
	color.a = _battle_effect_alpha
	draw_arc(Vector2.ZERO, _battle_effect_radius, 0.0, TAU, 28, color, 2.6)
	var fill_color: Color = color
	fill_color.a *= 0.18
	draw_circle(Vector2.ZERO, _battle_effect_radius * 0.55, fill_color)


func _set_battle_effect_progress(_value: float) -> void:
	queue_redraw()


func _draw_small_bar(origin: Vector2, size: Vector2, value: int, max_value: int, fill_color: Color) -> void:
	var background := Rect2(origin, size)
	draw_rect(background, Color(0.05, 0.04, 0.03, 0.58), true)
	var ratio: float = clampf(float(value) / float(max(1, max_value)), 0.0, 1.0)
	var fill_rect := Rect2(origin + Vector2(0.8, 0.8), Vector2(max(0.0, (size.x - 1.6) * ratio), max(0.0, size.y - 1.6)))
	draw_rect(fill_rect, fill_color, true)


func _get_base_color() -> Color:
	match character_kind:
		KIND_PLAYER:
			return Color(0.48, 0.62, 0.86)
		KIND_ENEMY:
			return Color(0.78, 0.38, 0.32)
		KIND_COMPANION:
			return Color(0.43, 0.70, 0.54)
		_:
			if _occupation() == "guard":
				return Color(0.46, 0.50, 0.56)
			return Color(0.54, 0.68, 0.47)


func _get_trim_color() -> Color:
	match character_kind:
		KIND_PLAYER:
			return Color(0.98, 0.91, 0.45)
		KIND_ENEMY:
			return Color(0.36, 0.12, 0.10)
		_:
			if _occupation() == "guard":
				return Color(0.82, 0.76, 0.58)
			return Color(0.96, 0.84, 0.48)


func _get_hair_color() -> Color:
	if character_kind == KIND_PLAYER:
		return Color(0.28, 0.25, 0.22)
	if _occupation() == "guard":
		return Color(0.20, 0.19, 0.18)
	return Color(0.45, 0.31, 0.17)


func _is_training_dummy() -> bool:
	return character_id.find("dummy") >= 0 or str(identity.get("species", "")) == "construct"


func _occupation() -> String:
	return str(identity.get("occupation", ""))


func _solid_colors(count: int, color: Color) -> PackedColorArray:
	var colors := PackedColorArray()
	for _index in range(count):
		colors.append(color)
	return colors


func _draw_ellipse(center: Vector2, size: Vector2, color: Color) -> void:
	var points := PackedVector2Array()
	var steps: int = 24
	for index in range(steps):
		var angle: float = TAU * float(index) / float(steps)
		points.append(center + Vector2(cos(angle) * size.x * 0.5, sin(angle) * size.y * 0.5))
	draw_polygon(points, _solid_colors(points.size(), color))


func _draw_ellipse_outline(center: Vector2, size: Vector2, color: Color, width: float) -> void:
	var points := PackedVector2Array()
	var steps: int = 24
	for index in range(steps):
		var angle: float = TAU * float(index) / float(steps)
		points.append(center + Vector2(cos(angle) * size.x * 0.5, sin(angle) * size.y * 0.5))
	points.append(points[0])
	draw_polyline(points, color, width)


func _facing_vector() -> Vector2:
	match facing:
		FACING_UP:
			return Vector2.UP
		FACING_DOWN:
			return Vector2.DOWN
		FACING_LEFT:
			return Vector2.LEFT
		FACING_RIGHT:
			return Vector2.RIGHT
		_:
			return Vector2.DOWN


func get_facing_cell() -> Vector2i:
	match facing:
		FACING_UP:
			return grid_position + Vector2i.UP
		FACING_DOWN:
			return grid_position + Vector2i.DOWN
		FACING_LEFT:
			return grid_position + Vector2i.LEFT
		FACING_RIGHT:
			return grid_position + Vector2i.RIGHT
		_:
			return grid_position + Vector2i.DOWN


func _read_item_definition(resource_path: String) -> Dictionary:
	return DefinitionLoader.load_item(resource_path)


func _apply_default_equipment(definition: Dictionary, spawn_data: Dictionary) -> void:
	if equipment_slots == null:
		return

	var equipment_data: Variant = spawn_data.get("default_equipment", definition.get("default_equipment", definition.get("equipment", {})))
	if typeof(equipment_data) == TYPE_DICTIONARY:
		var equipment_dict: Dictionary = equipment_data as Dictionary
		for slot_id_value in equipment_dict.keys():
			var slot_id: String = str(slot_id_value)
			var source: String = _equipment_source_from_value(equipment_dict.get(slot_id_value))
			_set_default_equipment_from_source(slot_id, source)
	elif typeof(equipment_data) == TYPE_ARRAY:
		var equipment_rows: Array = equipment_data as Array
		for equipment_value in equipment_rows:
			var equipment_entry: Dictionary = equipment_value as Dictionary
			var slot_id: String = str(equipment_entry.get("slot_id", equipment_entry.get("slot", "")))
			var source: String = str(equipment_entry.get("source", ""))
			_set_default_equipment_from_source(slot_id, source)


func _equipment_source_from_value(value: Variant) -> String:
	if typeof(value) == TYPE_DICTIONARY:
		var entry: Dictionary = value as Dictionary
		return str(entry.get("source", ""))
	return str(value)


func _set_default_equipment_from_source(slot_id: String, source: String) -> void:
	if slot_id.is_empty() or source.is_empty():
		return
	var item_definition: Dictionary = _read_item_definition(source)
	if item_definition.is_empty():
		return
	equipment_slots.set_default_item(item_definition, slot_id)

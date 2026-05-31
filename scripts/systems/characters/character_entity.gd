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

var attributes: Dictionary = {}
var identity: Dictionary = {}
var relation_slots: Dictionary = {}
var skills: Array[String] = []
var schedule: Array[Dictionary] = []
var current_schedule_entry_id: String = ""
var current_activity: String = "idle"
var scheduled_location_id: String = ""
var hp: int = 1
var max_hp: int = 1
var is_defeated: bool = false
var inventory: Inventory
var equipment_slots: EquipmentSlots
var location_root: Node


func configure(definition: Dictionary, spawn_data: Dictionary, parent_location: Node) -> void:
	character_id = str(spawn_data.get("id", definition.get("id", character_id)))
	display_name = str(definition.get("display_name", character_id))
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
	current_activity = str(spawn_data.get("activity", current_activity))
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
		"equipment_slots": equipment_slots.get_summary() if equipment_slots != null else {},
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
		equipment_slots.slots.merge(equipment_state, true)

	queue_redraw()


func set_grid_position(new_cell: Vector2i) -> void:
	if grid_position == new_cell:
		return

	var previous_cell: Vector2i = grid_position
	grid_position = new_cell
	_update_world_position()
	grid_position_changed.emit(character_id, previous_cell, grid_position)


func set_facing(new_facing: String) -> void:
	if facing == new_facing:
		return

	facing = new_facing
	facing_changed.emit(character_id, facing)
	queue_redraw()


func set_schedule_state(entry: Dictionary, location_id: String) -> void:
	current_schedule_entry_id = str(entry.get("id", ""))
	current_activity = str(entry.get("activity", current_activity))
	scheduled_location_id = location_id


func set_combat_stats(new_hp: int, new_max_hp: int, defeated: bool) -> void:
	max_hp = max(1, new_max_hp)
	hp = clampi(new_hp, 0, max_hp)
	is_defeated = defeated or hp <= 0
	attributes["max_hp"] = max_hp
	attributes["hp"] = hp
	attributes["defeated"] = is_defeated
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
		"attributes": attributes,
		"identity": identity,
		"relation_slots": relation_slots,
		"skills": skills.duplicate(),
		"schedule_entry_id": current_schedule_entry_id,
		"activity": current_activity,
		"scheduled_location_id": scheduled_location_id,
		"hp": hp,
		"max_hp": max_hp,
		"is_defeated": is_defeated,
		"inventory": inventory.get_summary() if inventory != null else [],
		"equipment_slots": equipment_slots.get_summary() if equipment_slots != null else {},
	}


func _update_world_position() -> void:
	if location_root != null and location_root.has_method("grid_to_world"):
		position = location_root.grid_to_world(grid_position)


func _draw() -> void:
	var radius: float = 10.0
	var body_color: Color = _get_debug_color()
	draw_circle(Vector2.ZERO, radius, body_color)
	draw_arc(Vector2.ZERO, radius + 2.0, 0.0, TAU, 24, Color(0.1, 0.1, 0.1), 2.0)
	draw_line(Vector2.ZERO, _facing_vector() * 16.0, Color(0.05, 0.05, 0.05), 2.0)

	if is_interactable:
		draw_circle(Vector2(8.0, -8.0), 3.0, Color(1.0, 0.95, 0.35))

	if is_combatable:
		draw_circle(Vector2(-8.0, -8.0), 3.0, Color(0.9, 0.2, 0.2))

	if is_defeated:
		draw_line(Vector2(-8.0, -8.0), Vector2(8.0, 8.0), Color.BLACK, 2.0)
		draw_line(Vector2(8.0, -8.0), Vector2(-8.0, 8.0), Color.BLACK, 2.0)


func _get_debug_color() -> Color:
	match character_kind:
		KIND_PLAYER:
			return Color(0.95, 0.95, 1.0)
		KIND_NPC:
			return Color(0.25, 0.55, 0.95)
		KIND_ENEMY:
			return Color(0.9, 0.2, 0.2)
		KIND_COMPANION:
			return Color(0.25, 0.85, 0.45)
		_:
			return Color(0.7, 0.7, 0.7)


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

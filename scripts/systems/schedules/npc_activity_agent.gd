class_name NpcActivityAgent
extends RefCounted

const STEP_INTERVAL_SECONDS := 1.4
const MOBILE_ACTIVITY_TYPES := ["patrol", "train", "social"]

var grid: LocationGrid
var _states: Dictionary = {}


func configure(location_grid: LocationGrid) -> void:
	grid = location_grid
	_states.clear()


func update(delta: float, movement_agent: Variant = null) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if grid == null:
		return events
	if GameState.current_mode == GameState.GameMode.COMBAT:
		return events

	for character_value in grid.characters_by_id.values():
		var character: CharacterEntity = _as_character(character_value)
		if character == null:
			continue
		if _should_skip_character(character, movement_agent):
			continue

		var activity_type: String = _normalized_activity_type(character.current_activity_type)
		var key: String = _activity_key(character, activity_type)
		var state: Dictionary = _states.get(character.character_id, {}) as Dictionary
		if str(state.get("key", "")) != key:
			state = {
				"key": key,
				"elapsed": 0.0,
				"index": 0,
			}
			_states[character.character_id] = state
			events.append(_activity_event(character, "scheduled_character_activity_entered"))

		if not MOBILE_ACTIVITY_TYPES.has(activity_type):
			continue

		state["elapsed"] = float(state.get("elapsed", 0.0)) + delta
		if float(state.get("elapsed", 0.0)) < STEP_INTERVAL_SECONDS:
			_states[character.character_id] = state
			continue

		state["elapsed"] = 0.0
		var step_event: Dictionary = _try_activity_step(character, state)
		_states[character.character_id] = state
		if not step_event.is_empty():
			events.append(step_event)

	return events


func cancel_character(character_id: String) -> void:
	_states.erase(character_id)


func _should_skip_character(character: CharacterEntity, movement_agent: Variant) -> bool:
	if character.is_player_controlled:
		return true
	if PartySystem.is_member(character.character_id):
		return true
	if character.is_defeated:
		return true
	if character.current_schedule_entry_id.is_empty():
		return true
	if character.scheduled_location_id != grid.location_id:
		return true
	if _normalized_activity_type(character.current_activity_type) == "travel":
		return true
	if movement_agent != null and movement_agent.has_method("has_active_movement"):
		if bool(movement_agent.has_active_movement(character.character_id)):
			return true

	return false


func _try_activity_step(character: CharacterEntity, state: Dictionary) -> Dictionary:
	var cells: Array[Vector2i] = _activity_cells(character)
	if cells.is_empty():
		return {}

	var start_index: int = int(state.get("index", 0))
	for attempt in range(cells.size()):
		var index: int = (start_index + attempt) % cells.size()
		var target_cell: Vector2i = cells[index]
		if target_cell == character.grid_position:
			continue
		if _cell_distance(character.grid_position, target_cell) != 1:
			continue
		if not grid.can_enter(target_cell):
			continue

		var from_cell: Vector2i = character.grid_position
		var direction: Vector2i = target_cell - from_cell
		character.face_direction(direction)
		if not grid.move_character(character.character_id, from_cell, target_cell, character.blocks_movement):
			continue

		character.set_grid_position(target_cell)
		state["index"] = (index + 1) % cells.size()
		return {
			"type": "scheduled_character_activity_step",
			"character_id": character.character_id,
			"location_id": grid.location_id,
			"entry_id": character.current_schedule_entry_id,
			"anchor_id": character.current_schedule_anchor_id,
			"activity_type": _normalized_activity_type(character.current_activity_type),
			"from": from_cell,
			"to": target_cell,
		}

	return {}


func _activity_cells(character: CharacterEntity) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var anchor: Dictionary = grid.get_anchor(character.current_schedule_anchor_id)
	if anchor.is_empty():
		return result

	var cell_rows: Array = anchor.get("activity_cells", anchor.get("patrol_cells", [])) as Array
	for cell_value in cell_rows:
		var cell_data: Dictionary = cell_value as Dictionary
		var cell := Vector2i(int(cell_data.get("x", -1)), int(cell_data.get("y", -1)))
		if not grid.in_bounds(cell):
			continue
		result.append(cell)

	return result


func _activity_event(character: CharacterEntity, event_type: String) -> Dictionary:
	return {
		"type": event_type,
		"character_id": character.character_id,
		"location_id": grid.location_id,
		"entry_id": character.current_schedule_entry_id,
		"anchor_id": character.current_schedule_anchor_id,
		"activity_type": _normalized_activity_type(character.current_activity_type),
		"activity": character.current_activity,
		"grid_position": character.grid_position,
	}


func _activity_key(character: CharacterEntity, activity_type: String) -> String:
	return "%s|%s|%s" % [
		character.current_schedule_entry_id,
		character.current_schedule_anchor_id,
		activity_type,
	]


func _normalized_activity_type(activity_type: String) -> String:
	if activity_type.is_empty():
		return "idle"
	return activity_type


func _cell_distance(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)


func _as_character(value: Variant) -> CharacterEntity:
	if typeof(value) != TYPE_OBJECT or not is_instance_valid(value):
		return null

	return value as CharacterEntity

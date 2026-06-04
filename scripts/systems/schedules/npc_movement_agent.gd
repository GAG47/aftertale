class_name NpcMovementAgent
extends RefCounted

const STEP_INTERVAL_SECONDS := 0.24
const STATE_WALKING := "walking"
const STATE_ARRIVED := "arrived"
const STATE_BLOCKED := "blocked"
const STATE_CANCELLED := "cancelled"

var grid: LocationGrid
var _intents: Dictionary = {}


func configure(location_grid: LocationGrid) -> void:
	grid = location_grid
	_intents.clear()


func has_active_intent(character_id: String, schedule_entry_id: String = "", target_cell: Vector2i = Vector2i(-9999, -9999)) -> bool:
	if not _intents.has(character_id):
		return false

	var intent: Dictionary = _intents.get(character_id, {}) as Dictionary
	if str(intent.get("state", "")) != STATE_WALKING:
		return false

	if not schedule_entry_id.is_empty() and str(intent.get("schedule_entry_id", "")) != schedule_entry_id:
		return false

	if target_cell.x != -9999 or target_cell.y != -9999:
		var intent_target: Vector2i = intent.get("target_cell", Vector2i.ZERO) as Vector2i
		if intent_target != target_cell:
			return false

	return true


func has_active_movement(character_id: String) -> bool:
	return has_active_intent(character_id)


func cancel_movement(character_id: String) -> Dictionary:
	if not _intents.has(character_id):
		return {}

	var intent: Dictionary = _intents.get(character_id, {}) as Dictionary
	_intents.erase(character_id)
	return {
		"type": "scheduled_character_movement_cancelled",
		"character_id": character_id,
		"location_id": grid.location_id if grid != null else "",
		"entry_id": str(intent.get("schedule_entry_id", "")),
		"state": STATE_CANCELLED,
	}


func request_schedule_movement(character: CharacterEntity, entry: Dictionary, scheduled_location_id: String, target_cell: Vector2i) -> Dictionary:
	if grid == null:
		return _build_request_event(character, entry, target_cell, STATE_BLOCKED, "missing_grid")
	if character == null or not is_instance_valid(character):
		return _build_request_event(character, entry, target_cell, STATE_BLOCKED, "missing_character")
	if not grid.in_bounds(target_cell):
		return _build_request_event(character, entry, target_cell, STATE_BLOCKED, "target_out_of_bounds")

	var entry_id: String = str(entry.get("id", ""))
	if has_active_intent(character.character_id, entry_id, target_cell):
		return _build_request_event(character, entry, target_cell, "unchanged", "")

	if character.grid_position == target_cell:
		cancel_movement(character.character_id)
		_apply_arrival_state(character, entry, scheduled_location_id)
		return _build_request_event(character, entry, target_cell, STATE_ARRIVED, "")

	var path: Array[Vector2i] = _find_path(character.grid_position, target_cell)
	if path.is_empty():
		_intents.erase(character.character_id)
		return _build_request_event(character, entry, target_cell, STATE_BLOCKED, "no_path")

	_intents[character.character_id] = {
		"character": character,
		"entry": entry.duplicate(true),
		"schedule_entry_id": entry_id,
		"target_cell": target_cell,
		"target_location_id": scheduled_location_id,
		"arrival_facing": str(entry.get("facing", character.facing)),
		"arrival_activity": str(entry.get("activity", character.current_activity)),
		"path": path,
		"elapsed": 0.0,
		"state": STATE_WALKING,
	}
	return _build_request_event(character, entry, target_cell, "started", "")


func update(delta: float) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if grid == null:
		return events
	if GameState.current_mode == GameState.GameMode.COMBAT:
		return events

	for character_id_value in _intents.keys().duplicate():
		var character_id: String = str(character_id_value)
		var intent: Dictionary = _intents.get(character_id, {}) as Dictionary
		var character: CharacterEntity = intent.get("character", null) as CharacterEntity
		if character == null or not is_instance_valid(character):
			_intents.erase(character_id)
			continue

		var elapsed: float = float(intent.get("elapsed", 0.0)) + delta
		if elapsed < STEP_INTERVAL_SECONDS:
			intent["elapsed"] = elapsed
			_intents[character_id] = intent
			continue

		intent["elapsed"] = 0.0
		var event: Dictionary = _advance_intent(character, intent)
		if not event.is_empty():
			events.append(event)

	return events


func _advance_intent(character: CharacterEntity, intent: Dictionary) -> Dictionary:
	var target_cell: Vector2i = intent.get("target_cell", Vector2i.ZERO) as Vector2i
	if character.grid_position == target_cell:
		return _finish_arrival(character, intent)

	var path: Array[Vector2i] = intent.get("path", []) as Array[Vector2i]
	if path.is_empty():
		path = _find_path(character.grid_position, target_cell)
		if path.is_empty():
			return _finish_blocked(character, intent, "no_path")

	var next_cell: Vector2i = path.pop_front() as Vector2i
	if not _try_move_step(character, next_cell):
		path = _find_path(character.grid_position, target_cell)
		if path.is_empty():
			return _finish_blocked(character, intent, "blocked")

		next_cell = path.pop_front() as Vector2i
		if not _try_move_step(character, next_cell):
			return _finish_blocked(character, intent, "blocked")

	intent["path"] = path
	_intents[character.character_id] = intent

	if character.grid_position == target_cell:
		return _finish_arrival(character, intent)

	return {
		"type": "scheduled_character_step",
		"character_id": character.character_id,
		"location_id": grid.location_id,
		"entry_id": str(intent.get("schedule_entry_id", "")),
		"to": character.grid_position,
		"target": target_cell,
	}


func _try_move_step(character: CharacterEntity, next_cell: Vector2i) -> bool:
	var from_cell: Vector2i = character.grid_position
	var direction: Vector2i = next_cell - from_cell
	if direction == Vector2i.ZERO:
		return true

	character.face_direction(direction)
	if not grid.move_character(character.character_id, from_cell, next_cell, character.blocks_movement):
		return false

	character.set_grid_position(next_cell)
	return true


func _finish_arrival(character: CharacterEntity, intent: Dictionary) -> Dictionary:
	var entry: Dictionary = intent.get("entry", {}) as Dictionary
	var scheduled_location_id: String = str(intent.get("target_location_id", grid.location_id))
	_apply_arrival_state(character, entry, scheduled_location_id)
	_intents.erase(character.character_id)
	return {
		"type": "scheduled_character_arrived",
		"character_id": character.character_id,
		"location_id": grid.location_id,
		"entry_id": str(intent.get("schedule_entry_id", "")),
		"grid_position": character.grid_position,
		"facing": character.facing,
		"activity": character.current_activity,
	}


func _finish_blocked(character: CharacterEntity, intent: Dictionary, reason: String) -> Dictionary:
	_intents.erase(character.character_id)
	return {
		"type": "scheduled_character_blocked",
		"character_id": character.character_id,
		"location_id": grid.location_id,
		"entry_id": str(intent.get("schedule_entry_id", "")),
		"target": intent.get("target_cell", Vector2i.ZERO),
		"reason": reason,
	}


func _apply_arrival_state(character: CharacterEntity, entry: Dictionary, scheduled_location_id: String) -> void:
	if entry.has("facing"):
		character.set_facing(str(entry.get("facing", character.facing)))
	character.set_schedule_state(entry, scheduled_location_id)


func _find_path(start_cell: Vector2i, target_cell: Vector2i) -> Array[Vector2i]:
	var empty_path: Array[Vector2i] = []
	if grid == null:
		return empty_path
	if start_cell == target_cell:
		return empty_path
	if not grid.in_bounds(start_cell) or not grid.in_bounds(target_cell):
		return empty_path
	if not grid.can_enter(target_cell):
		return empty_path

	var frontier: Array[Vector2i] = [start_cell]
	var came_from: Dictionary = {}
	var visited: Dictionary = { grid.cell_key(start_cell): true }
	var directions: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
	var found: bool = false

	while not frontier.is_empty():
		var current: Vector2i = frontier.pop_front() as Vector2i
		for direction in directions:
			var next_cell: Vector2i = current + direction
			var next_key: String = grid.cell_key(next_cell)
			if visited.has(next_key):
				continue
			if not grid.in_bounds(next_cell):
				continue
			if not grid.can_enter(next_cell):
				continue

			visited[next_key] = true
			came_from[next_key] = current
			if next_cell == target_cell:
				found = true
				frontier.clear()
				break
			frontier.append(next_cell)

	if not found:
		return empty_path

	var path: Array[Vector2i] = []
	var cursor: Vector2i = target_cell
	while cursor != start_cell:
		path.push_front(cursor)
		var cursor_key: String = grid.cell_key(cursor)
		if not came_from.has(cursor_key):
			return empty_path
		cursor = came_from.get(cursor_key, start_cell) as Vector2i

	return path


func _build_request_event(character: CharacterEntity, entry: Dictionary, target_cell: Vector2i, state: String, reason: String) -> Dictionary:
	var character_id := ""
	if character != null and is_instance_valid(character):
		character_id = character.character_id

	return {
		"type": "scheduled_character_movement_request",
		"character_id": character_id,
		"location_id": grid.location_id if grid != null else "",
		"entry_id": str(entry.get("id", "")),
		"target": target_cell,
		"state": state,
		"reason": reason,
	}

class_name NpcAutonomyAgent
extends RefCounted

const DANGER_REASON := "danger_alert"
const DANGER_PRIORITY := 80
const RETRY_INTERVAL_SECONDS := 1.5

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

	var danger_level: int = int(grid.state.get("danger_level", 0))
	for character_value in grid.characters_by_id.values():
		var character: CharacterEntity = _as_character(character_value)
		if character == null:
			continue

		if _should_hard_skip_character(character):
			if has_active_interruption(character.character_id):
				events.append(_clear_interruption(character, "hard_rule", movement_agent))
			continue

		if danger_level > 0 and _is_guard(character):
			events.append_array(_ensure_danger_interruption(character, danger_level, delta, movement_agent))
		elif _has_interruption_reason(character.character_id, DANGER_REASON):
			events.append(_clear_interruption(character, "danger_cleared", movement_agent))

	return events


func has_active_interruption(character_id: String) -> bool:
	return _states.has(character_id)


func cancel_character(character_id: String) -> void:
	_states.erase(character_id)


func _ensure_danger_interruption(
	character: CharacterEntity,
	danger_level: int,
	delta: float,
	movement_agent: Variant
) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var target_anchor: Dictionary = _find_guard_post_anchor(character)
	if target_anchor.is_empty():
		return events

	var target_anchor_id: String = str(target_anchor.get("id", ""))
	var target_cell: Vector2i = _cell_from_dict(target_anchor.get("grid_position", {}) as Dictionary)
	if not grid.in_bounds(target_cell):
		return events

	var entry: Dictionary = _build_danger_entry(character, target_anchor, target_cell)
	var state: Dictionary = _states.get(character.character_id, {}) as Dictionary
	var already_interrupted: bool = str(state.get("reason", "")) == DANGER_REASON
	if already_interrupted:
		state["elapsed"] = float(state.get("elapsed", 0.0)) + delta
		state["danger_level"] = danger_level
		_states[character.character_id] = state
		if _movement_agent_has_active_movement(movement_agent, character.character_id):
			return events
		if character.grid_position == target_cell:
			return events
		if float(state.get("elapsed", 0.0)) < RETRY_INTERVAL_SECONDS:
			return events

		state["elapsed"] = 0.0
		_states[character.character_id] = state
		var retry_request: Dictionary = _request_temporary_movement(character, entry, target_cell, movement_agent)
		if str(retry_request.get("state", "")) == "started":
			events.append(_movement_request_event(character, entry, target_cell, retry_request, "scheduled_character_interruption_retried"))
		return events

	var movement_request: Dictionary = _request_temporary_movement(character, entry, target_cell, movement_agent)
	character.set_interruption_state(DANGER_REASON, DANGER_PRIORITY)
	character.set_schedule_state(entry, grid.location_id)
	_states[character.character_id] = {
		"reason": DANGER_REASON,
		"priority": DANGER_PRIORITY,
		"started_at": TimeManager.get_absolute_minutes(),
		"target_anchor_id": target_anchor_id,
		"target_cell": target_cell,
		"danger_level": danger_level,
		"elapsed": 0.0,
	}
	events.append({
		"type": "scheduled_character_interruption_started",
		"character_id": character.character_id,
		"location_id": grid.location_id,
		"reason": DANGER_REASON,
		"priority": DANGER_PRIORITY,
		"entry_id": str(entry.get("id", "")),
		"anchor_id": target_anchor_id,
		"activity_type": str(entry.get("activity_type", "patrol")),
		"activity": str(entry.get("activity", "")),
		"target": target_cell,
		"movement_state": str(movement_request.get("state", "")),
		"danger_level": danger_level,
	})
	return events


func _clear_interruption(character: CharacterEntity, clear_reason: String, movement_agent: Variant) -> Dictionary:
	var state: Dictionary = _states.get(character.character_id, {}) as Dictionary
	var reason: String = str(state.get("reason", character.current_interruption_reason))
	var priority: int = int(state.get("priority", character.current_interruption_priority))
	_states.erase(character.character_id)
	if movement_agent != null and movement_agent.has_method("cancel_movement"):
		movement_agent.cancel_movement(character.character_id)
	character.clear_interruption_state(reason)
	return {
		"type": "scheduled_character_interruption_cleared",
		"character_id": character.character_id,
		"location_id": grid.location_id,
		"reason": reason,
		"clear_reason": clear_reason,
		"priority": priority,
		"grid_position": character.grid_position,
	}


func _request_temporary_movement(
	character: CharacterEntity,
	entry: Dictionary,
	target_cell: Vector2i,
	movement_agent: Variant
) -> Dictionary:
	if movement_agent == null or not movement_agent.has_method("request_schedule_movement"):
		return {
			"state": "blocked",
			"reason": "missing_movement_agent",
		}

	return movement_agent.request_schedule_movement(character, entry, grid.location_id, target_cell)


func _movement_request_event(
	character: CharacterEntity,
	entry: Dictionary,
	target_cell: Vector2i,
	movement_request: Dictionary,
	event_type: String
) -> Dictionary:
	return {
		"type": event_type,
		"character_id": character.character_id,
		"location_id": grid.location_id,
		"reason": DANGER_REASON,
		"priority": DANGER_PRIORITY,
		"entry_id": str(entry.get("id", "")),
		"anchor_id": str(entry.get("anchor_id", "")),
		"target": target_cell,
		"movement_state": str(movement_request.get("state", "")),
		"block_reason": str(movement_request.get("reason", "")),
	}


func _build_danger_entry(character: CharacterEntity, target_anchor: Dictionary, target_cell: Vector2i) -> Dictionary:
	var facing: String = str(target_anchor.get("facing", character.facing))
	return {
		"id": "interrupt_%s_danger_alert" % character.character_id,
		"location_id": grid.location_id,
		"anchor_id": str(target_anchor.get("id", "")),
		"grid_position": {
			"x": target_cell.x,
			"y": target_cell.y,
		},
		"facing": facing,
		"activity_type": "patrol",
		"activity": "responding to danger",
		"movement": "walk",
	}


func _find_guard_post_anchor(character: CharacterEntity) -> Dictionary:
	for anchor_id in ["wild_gate_guard_post", "clearing_guard_post"]:
		var anchor: Dictionary = grid.get_anchor(anchor_id)
		if _is_guard_post_anchor(anchor):
			return anchor

	for anchor_id_value in grid.anchors_by_id.keys():
		var anchor_id: String = str(anchor_id_value)
		var anchor: Dictionary = grid.get_anchor(anchor_id)
		if _is_guard_post_anchor(anchor):
			return anchor

	var current_anchor: Dictionary = grid.get_anchor(character.current_schedule_anchor_id)
	if not current_anchor.is_empty():
		return current_anchor

	return {}


func _is_guard_post_anchor(anchor: Dictionary) -> bool:
	if anchor.is_empty():
		return false
	return str(anchor.get("kind", "")) == "guard_post"


func _movement_agent_has_active_movement(movement_agent: Variant, character_id: String) -> bool:
	if movement_agent == null or not movement_agent.has_method("has_active_movement"):
		return false
	return bool(movement_agent.has_active_movement(character_id))


func _has_interruption_reason(character_id: String, reason: String) -> bool:
	if not _states.has(character_id):
		return false

	var state: Dictionary = _states.get(character_id, {}) as Dictionary
	return str(state.get("reason", "")) == reason


func _should_hard_skip_character(character: CharacterEntity) -> bool:
	if character.is_player_controlled:
		return true
	if PartySystem.is_member(character.character_id):
		return true
	if character.is_defeated:
		return true
	if character.scheduled_location_id != grid.location_id and not character.scheduled_location_id.is_empty():
		return true
	return false


func _is_guard(character: CharacterEntity) -> bool:
	return str(character.identity.get("occupation", "")) == "guard"


func _cell_from_dict(value: Dictionary) -> Vector2i:
	return Vector2i(int(value.get("x", -1)), int(value.get("y", -1)))


func _as_character(value: Variant) -> CharacterEntity:
	if typeof(value) != TYPE_OBJECT or not is_instance_valid(value):
		return null

	return value as CharacterEntity

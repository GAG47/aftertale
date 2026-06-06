class_name BattleState
extends RefCounted

const MAX_REACTION_HISTORY := 24

var battle_id: String = ""
var location_root: Node
var grid: LocationGrid
var units: Array[BattleUnitState] = []
var tile_states_by_cell: Dictionary = {}
var recent_reactions: Array[Dictionary] = []
var turn_index: int = 0
var round_number: int = 1
var active: bool = false
var result_status: String = ""


func configure(new_battle_id: String, battle_location_root: Node, battle_grid: LocationGrid, battle_units: Array[BattleUnitState]) -> void:
	battle_id = new_battle_id
	location_root = battle_location_root
	grid = battle_grid
	units.clear()
	for unit in battle_units:
		units.append(unit)
	tile_states_by_cell.clear()
	recent_reactions.clear()
	_sort_units_by_speed()
	turn_index = 0
	round_number = 1
	active = true
	result_status = ""
	var unit: BattleUnitState = get_current_unit()
	if unit != null:
		unit.refresh_turn()


func get_current_unit() -> BattleUnitState:
	if units.is_empty():
		return null

	turn_index = clampi(turn_index, 0, units.size() - 1)
	return units[turn_index]


func advance_turn() -> BattleUnitState:
	if units.is_empty():
		return null

	var guard_count: int = 0
	while guard_count < units.size():
		turn_index += 1
		if turn_index >= units.size():
			turn_index = 0
			round_number += 1
			_sort_units_by_speed()

		var unit: BattleUnitState = get_current_unit()
		if unit != null and unit.is_active():
			unit.refresh_turn()
			return unit
		guard_count += 1

	return null


func set_current_unit(character_id: String) -> bool:
	if character_id.is_empty():
		return false

	for index in range(units.size()):
		var unit: BattleUnitState = units[index]
		if unit.character_id != character_id or not unit.is_active():
			continue
		turn_index = index
		unit.refresh_turn()
		return true

	return false


func promote_contiguous_unit_to_current(character_id: String, team: String) -> bool:
	if character_id.is_empty() or team.is_empty() or units.is_empty():
		return false

	var current_unit: BattleUnitState = get_current_unit()
	if current_unit == null or current_unit.team != team:
		return false

	var contiguous_indexes: Array[int] = _get_contiguous_unit_indexes_from_current(team)
	if contiguous_indexes.is_empty():
		return false

	var target_offset: int = -1
	for offset in range(contiguous_indexes.size()):
		var unit: BattleUnitState = units[contiguous_indexes[offset]]
		if unit.character_id == character_id:
			target_offset = offset
			break
	if target_offset < 0:
		return false
	if target_offset == 0:
		return true

	var block_units: Array[BattleUnitState] = []
	for index in contiguous_indexes:
		block_units.append(units[index])

	var selected_unit: BattleUnitState = block_units[target_offset]
	block_units.remove_at(target_offset)
	block_units.insert(0, selected_unit)
	for offset in range(contiguous_indexes.size()):
		units[contiguous_indexes[offset]] = block_units[offset]

	turn_index = contiguous_indexes[0]
	selected_unit.refresh_turn()
	return true


func get_unit_for_character(character_id: String) -> BattleUnitState:
	for unit in units:
		if unit.character_id == character_id:
			return unit

	return null


func get_unit_at(cell: Vector2i) -> BattleUnitState:
	for unit in units:
		if unit.is_active() and unit.character.grid_position == cell:
			return unit

	return null


func cell_key(cell: Vector2i) -> String:
	if grid != null:
		return grid.cell_key(cell)
	return "%d,%d" % [cell.x, cell.y]


func get_tile_state_at(cell: Vector2i):
	return tile_states_by_cell.get(cell_key(cell))


func has_tile_state(cell: Vector2i, state_id: String = "") -> bool:
	var tile_state = get_tile_state_at(cell)
	if tile_state == null:
		return false
	if state_id.is_empty():
		return true
	return tile_state.id == state_id


func apply_tile_state(tile_state, result: ActionResult = null) -> bool:
	if tile_state == null or tile_state.id.is_empty():
		return false
	if grid != null and not grid.in_bounds(tile_state.cell):
		return false

	var key: String = cell_key(tile_state.cell)
	var existing = tile_states_by_cell.get(key)
	var previous_state_id: String = existing.id if existing != null else ""
	var refreshed: bool = existing != null and existing.id == tile_state.id
	if refreshed:
		existing.refresh_from(tile_state)
		tile_state = existing
	else:
		tile_states_by_cell[key] = tile_state

	if result != null:
		result.add_world_change({
			"type": "battle_tile_state_applied",
			"battle_id": battle_id,
			"cell": tile_state.cell,
			"state_id": tile_state.id,
			"previous_state_id": previous_state_id,
			"refreshed": refreshed,
			"tile_state": tile_state.get_summary(),
		})
		result.add_feedback("Tile %s is now %s." % [tile_state.cell, tile_state.id])

	on_tile_state_created(tile_state, result)
	return true


func remove_tile_state(cell: Vector2i, state_id: String = "", result: ActionResult = null, reason: String = "removed") -> bool:
	var key: String = cell_key(cell)
	var existing = tile_states_by_cell.get(key)
	if existing == null:
		return false
	if not state_id.is_empty() and existing.id != state_id:
		return false

	tile_states_by_cell.erase(key)
	if result != null:
		result.add_world_change({
			"type": "battle_tile_state_removed",
			"battle_id": battle_id,
			"cell": cell,
			"state_id": existing.id,
			"reason": reason,
			"tile_state": existing.get_summary(),
		})
	return true


func record_reaction(reaction: Dictionary, result: ActionResult = null) -> void:
	var recorded_reaction: Dictionary = reaction.duplicate(true)
	recorded_reaction["battle_id"] = battle_id
	recent_reactions.append(recorded_reaction)
	while recent_reactions.size() > MAX_REACTION_HISTORY:
		recent_reactions.pop_front()

	if result == null:
		return

	var world_change: Dictionary = recorded_reaction.duplicate(true)
	world_change["type"] = "reaction_event"
	result.add_world_change(world_change)
	var feedback: String = str(recorded_reaction.get("feedback", ""))
	if not feedback.is_empty():
		result.add_feedback(feedback)


func get_reaction_summaries() -> Array[Dictionary]:
	var summaries: Array[Dictionary] = []
	for reaction in recent_reactions:
		summaries.append(reaction.duplicate(true))
	return summaries


func on_tile_state_created(_tile_state, _result: ActionResult = null) -> void:
	pass


func on_unit_enters_cell(_unit: BattleUnitState, _cell: Vector2i, _result: ActionResult = null) -> void:
	pass


func on_unit_starts_turn_on_cell(unit: BattleUnitState, result: ActionResult = null) -> void:
	if unit == null:
		return
	_tick_tile_state_durations(result)


func on_unit_ends_turn_on_cell(_unit: BattleUnitState, _result: ActionResult = null) -> void:
	pass


func on_round_ends(_result: ActionResult = null) -> void:
	pass


func on_tile_state_expires(_tile_state, _result: ActionResult = null) -> void:
	pass


func get_tile_state_summaries() -> Array[Dictionary]:
	var summaries: Array[Dictionary] = []
	for key_value in tile_states_by_cell.keys():
		var tile_state = tile_states_by_cell[key_value]
		if tile_state != null:
			summaries.append(tile_state.get_summary())
	summaries.sort_custom(Callable(self, "_compare_tile_state_summaries"))
	return summaries


func get_active_units_for_team(team: String) -> Array[BattleUnitState]:
	var result: Array[BattleUnitState] = []
	for unit in units:
		if unit.team == team and unit.is_active():
			result.append(unit)

	return result


func has_active_team(team: String) -> bool:
	return not get_active_units_for_team(team).is_empty()


func get_contiguous_units_from_current(team: String = "") -> Array[BattleUnitState]:
	var result: Array[BattleUnitState] = []
	if units.is_empty():
		return result

	var indexes: Array[int] = _get_contiguous_unit_indexes_from_current(team)
	for index in indexes:
		result.append(units[index])

	return result


func _get_contiguous_unit_indexes_from_current(team: String = "") -> Array[int]:
	var result: Array[int] = []
	if units.is_empty():
		return result

	var start_index: int = clampi(turn_index, 0, units.size() - 1)
	var first_team: String = team
	for offset in range(units.size()):
		var index: int = (start_index + offset) % units.size()
		var unit: BattleUnitState = units[index]
		if not unit.is_active():
			continue
		if first_team.is_empty():
			first_team = unit.team
		if unit.team != first_team:
			break
		result.append(index)

	return result


func get_turn_order_summary(max_count: int = 8) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if units.is_empty() or max_count <= 0:
		return result

	var added: int = 0
	var offset: int = 0
	while added < max_count and offset < units.size() * 2:
		var index: int = (turn_index + offset) % units.size()
		var unit: BattleUnitState = units[index]
		if unit.is_active():
			var summary: Dictionary = unit.get_summary()
			summary["queue_index"] = added
			summary["turn_index"] = index
			summary["is_current"] = offset == 0
			result.append(summary)
			added += 1
		offset += 1

	return result


func get_summary() -> Dictionary:
	var unit_summaries: Array[Dictionary] = []
	for unit in units:
		unit_summaries.append(unit.get_summary())

	var current_unit: BattleUnitState = get_current_unit()
	return {
		"battle_id": battle_id,
		"active": active,
		"round": round_number,
		"turn_index": turn_index,
		"current_unit": current_unit.get_summary() if current_unit != null else {},
		"units": unit_summaries,
		"turn_order": get_turn_order_summary(),
		"tile_states": get_tile_state_summaries(),
		"recent_reactions": get_reaction_summaries(),
		"result_status": result_status,
	}


func _sort_units_by_speed() -> void:
	units.sort_custom(Callable(self, "_compare_units"))


func _compare_units(a: BattleUnitState, b: BattleUnitState) -> bool:
	if a.speed == b.speed:
		var a_party_rank: int = PartySystem.get_member_order_rank(a.character_id) if PartySystem.is_member(a.character_id) else 999
		var b_party_rank: int = PartySystem.get_member_order_rank(b.character_id) if PartySystem.is_member(b.character_id) else 999
		if a_party_rank != b_party_rank:
			return a_party_rank < b_party_rank
		return a.character_id < b.character_id

	return a.speed > b.speed


func _tick_tile_state_durations(result: ActionResult = null) -> void:
	var expired_keys: Array[String] = []
	for key_value in tile_states_by_cell.keys():
		var key: String = str(key_value)
		var tile_state = tile_states_by_cell[key]
		if tile_state == null:
			expired_keys.append(key)
			continue
		if tile_state.should_skip_tick(round_number, turn_index):
			continue
		if tile_state.tick_duration():
			expired_keys.append(key)

	for key in expired_keys:
		var expired_state = tile_states_by_cell.get(key)
		tile_states_by_cell.erase(key)
		if expired_state == null:
			continue
		on_tile_state_expires(expired_state, result)
		if result != null:
			result.add_world_change({
				"type": "battle_tile_state_expired",
				"battle_id": battle_id,
				"cell": expired_state.cell,
				"state_id": expired_state.id,
				"tile_state": expired_state.get_summary(),
			})
			result.add_feedback("%s at %s faded." % [expired_state.id, expired_state.cell])


func _compare_tile_state_summaries(a: Dictionary, b: Dictionary) -> bool:
	var a_cell: Vector2i = a.get("cell", Vector2i.ZERO) as Vector2i
	var b_cell: Vector2i = b.get("cell", Vector2i.ZERO) as Vector2i
	if a_cell.y == b_cell.y:
		return a_cell.x < b_cell.x
	return a_cell.y < b_cell.y

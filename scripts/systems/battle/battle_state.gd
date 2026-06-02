class_name BattleState
extends RefCounted

var battle_id: String = ""
var location_root: Node
var grid: LocationGrid
var units: Array[BattleUnitState] = []
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

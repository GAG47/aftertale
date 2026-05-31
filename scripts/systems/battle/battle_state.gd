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
		"result_status": result_status,
	}


func _sort_units_by_speed() -> void:
	units.sort_custom(Callable(self, "_compare_units"))


func _compare_units(a: BattleUnitState, b: BattleUnitState) -> bool:
	if a.speed == b.speed:
		return a.character_id < b.character_id

	return a.speed > b.speed

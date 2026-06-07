class_name BattleTileUnitEffectSystem
extends RefCounted

const SURFACE_STATUS_SOURCE := "tile_surface"
const ENTER_DAMAGE := {
	"burning": 1,
	"electrified": 1,
}
const TURN_START_DAMAGE := {
	"burning": 2,
	"electrified": 2,
}


static func on_unit_enters_cell(unit: BattleUnitState, cell: Vector2i, battle_state: BattleState, result: ActionResult) -> void:
	if unit == null or not unit.is_active() or battle_state == null:
		return

	_sync_surface_status(unit, cell, battle_state, result)
	var tile_state = battle_state.get_tile_state_at(cell)
	if tile_state == null:
		return

	var damage: int = int(ENTER_DAMAGE.get(tile_state.id, 0)) * max(1, tile_state.intensity)
	if damage > 0:
		_deal_automatic_damage(unit, damage, tile_state, "enter_cell", battle_state, result)


static func on_unit_starts_turn(unit: BattleUnitState, battle_state: BattleState, result: ActionResult) -> void:
	if unit == null or not unit.is_active() or battle_state == null:
		return

	_apply_pending_status_effects(unit, battle_state, result)
	if not unit.is_active():
		return

	var cell: Vector2i = unit.character.grid_position
	_sync_surface_status(unit, cell, battle_state, result)
	var tile_state = battle_state.get_tile_state_at(cell)
	if tile_state == null:
		return

	var damage: int = int(TURN_START_DAMAGE.get(tile_state.id, 0)) * max(1, tile_state.intensity)
	if damage > 0:
		_deal_automatic_damage(unit, damage, tile_state, "turn_start", battle_state, result)
	if not unit.is_active():
		return

	match tile_state.id:
		"frozen":
			_reduce_action_points(unit, 1, "frozen_surface", battle_state, result)
		"electrified":
			_reduce_action_points(unit, 1, "electrified_surface", battle_state, result)


static func on_unit_ends_turn(unit: BattleUnitState, battle_state: BattleState, result: ActionResult) -> void:
	if unit == null or battle_state == null:
		return

	_clear_expiring_statuses(unit, "turn_end", battle_state, result)
	if unit.is_active():
		_sync_surface_status(unit, unit.character.grid_position, battle_state, result)


static func on_unit_hit_by_skill(
	unit: BattleUnitState,
	source_unit: BattleUnitState,
	skill: Dictionary,
	pre_hit_tile_state_id: String,
	battle_state: BattleState,
	result: ActionResult
) -> void:
	if unit == null or not unit.is_active() or battle_state == null:
		return

	var element: String = str(skill.get("element", ""))
	if element.is_empty():
		return

	var is_wet: bool = pre_hit_tile_state_id == "wet" or unit.has_status_effect("wet")
	var source_character_id: String = source_unit.character_id if source_unit != null else ""
	match element:
		"fire":
			if is_wet:
				_remove_status(unit, "wet", battle_state, result, "fire_dried_wet")
			else:
				_apply_status(unit, _status("burning", "燃烧", "turn_end", "skill_hit", {
					"source_character_id": source_character_id,
				}), battle_state, result)
		"water":
			_remove_status(unit, "burning", battle_state, result, "water_extinguished_burning")
			_apply_status(unit, _status("wet", "湿润", "turn_end", "skill_hit", {
				"source_character_id": source_character_id,
			}), battle_state, result)
		"ice":
			if is_wet:
				_remove_status(unit, "wet", battle_state, result, "ice_froze_wet")
				_apply_status(unit, _status("frozen", "冻结", "", "skill_hit", {
					"source_character_id": source_character_id,
				}), battle_state, result)
			else:
				_apply_status(unit, _status("chilled", "寒冷", "turn_end", "skill_hit", {
					"move_cost_bonus": 1,
					"source_character_id": source_character_id,
				}), battle_state, result)
		"lightning":
			_apply_status(unit, _status("shocked", "感电", "", "skill_hit", {
				"source_character_id": source_character_id,
			}), battle_state, result)
			if is_wet:
				var intensity: int = _get_skill_element_intensity(skill)
				_deal_skill_reaction_damage(
					unit,
					max(1, intensity * 2),
					"wet_lightning",
					source_character_id,
					battle_state,
					result
				)


static func get_battle_cell_move_cost(unit: BattleUnitState, _from_cell: Vector2i, to_cell: Vector2i, battle_state: BattleState) -> int:
	var cost: int = 1
	if unit != null:
		for status_value in unit.status_effects.values():
			var status_data: Dictionary = status_value as Dictionary
			cost += max(0, int(status_data.get("move_cost_bonus", 0)))

	if battle_state != null:
		var tile_state = battle_state.get_tile_state_at(to_cell)
		if tile_state != null and tile_state.id == "frozen":
			cost += max(1, tile_state.intensity)
	return max(1, cost)


static func _sync_surface_status(unit: BattleUnitState, cell: Vector2i, battle_state: BattleState, result: ActionResult) -> void:
	var tile_state = battle_state.get_tile_state_at(cell)
	var desired_status: Dictionary = {}
	var tile_state_id: String = tile_state.id if tile_state != null else ""
	var source_character_id: String = tile_state.source_character_id if tile_state != null else ""
	match tile_state_id:
		"burning":
			desired_status = _status("burning", "燃烧", "", SURFACE_STATUS_SOURCE, {
				"source_character_id": source_character_id,
			})
		"wet":
			desired_status = _status("wet", "湿润", "", SURFACE_STATUS_SOURCE, {
				"source_character_id": source_character_id,
			})
		"frozen":
			desired_status = _status("chilled", "寒冷", "", SURFACE_STATUS_SOURCE, {
				"source_character_id": source_character_id,
			})
		"electrified":
			desired_status = _status("shocked", "感电", "", SURFACE_STATUS_SOURCE, {
				"source_character_id": source_character_id,
			})

	var desired_status_id: String = str(desired_status.get("status_id", ""))
	_remove_surface_statuses(unit, desired_status_id, battle_state, result)
	if not desired_status.is_empty():
		_apply_status(unit, desired_status, battle_state, result)


static func _apply_pending_status_effects(unit: BattleUnitState, battle_state: BattleState, result: ActionResult) -> void:
	var burning_status: Dictionary = unit.get_status_effect("burning")
	if str(burning_status.get("source_kind", "")) == "skill_hit":
		_deal_status_damage(
			unit,
			1,
			"burning",
			str(burning_status.get("source_character_id", "")),
			battle_state,
			result
		)
		if not unit.is_active():
			return
	var frozen_status: Dictionary = unit.get_status_effect("frozen")
	if str(frozen_status.get("source_kind", "")) == "skill_hit":
		_reduce_action_points(unit, unit.action_points, "frozen_status", battle_state, result)
		_remove_status(unit, "frozen", battle_state, result, "consumed_at_turn_start")
	var shocked_status: Dictionary = unit.get_status_effect("shocked")
	if str(shocked_status.get("source_kind", "")) == "skill_hit":
		_reduce_action_points(unit, 1, "shocked_status", battle_state, result)
		_remove_status(unit, "shocked", battle_state, result, "consumed_at_turn_start")


static func _remove_surface_statuses(
	unit: BattleUnitState,
	keep_status_id: String,
	battle_state: BattleState,
	result: ActionResult
) -> void:
	for status_id_value in unit.status_effects.keys().duplicate():
		var status_id: String = str(status_id_value)
		var status_data: Dictionary = unit.status_effects.get(status_id, {}) as Dictionary
		if str(status_data.get("source_kind", "")) != SURFACE_STATUS_SOURCE:
			continue
		if status_id == keep_status_id:
			continue
		_remove_status(unit, status_id, battle_state, result, "left_surface")


static func _clear_expiring_statuses(
	unit: BattleUnitState,
	expire_rule: String,
	battle_state: BattleState,
	result: ActionResult
) -> void:
	for status_id_value in unit.status_effects.keys().duplicate():
		var status_id: String = str(status_id_value)
		var status_data: Dictionary = unit.status_effects.get(status_id, {}) as Dictionary
		if str(status_data.get("expires", "")) != expire_rule:
			continue
		_remove_status(unit, status_id, battle_state, result, "expired_%s" % expire_rule)


static func _apply_status(unit: BattleUnitState, status_data: Dictionary, battle_state: BattleState, result: ActionResult) -> void:
	var status_id: String = str(status_data.get("status_id", ""))
	if status_id.is_empty():
		return

	var previous: Dictionary = unit.get_status_effect(status_id)
	if previous == status_data:
		return
	if not previous.is_empty():
		var previous_source_kind: String = str(previous.get("source_kind", ""))
		var next_source_kind: String = str(status_data.get("source_kind", ""))
		if next_source_kind == SURFACE_STATUS_SOURCE and previous_source_kind != SURFACE_STATUS_SOURCE:
			return
	unit.add_status_effect(status_data)
	if result != null:
		result.add_world_change({
			"type": "battle_status_applied",
			"battle_id": battle_state.battle_id,
			"source_id": str(status_data.get("source_character_id", "")),
			"target_id": unit.character_id,
			"status_id": status_id,
			"status": status_data.duplicate(true),
			"automatic": true,
		})
		result.add_feedback("%s 获得状态：%s。" % [unit.display_name, str(status_data.get("display_name", status_id))])


static func _remove_status(unit: BattleUnitState, status_id: String, battle_state: BattleState, result: ActionResult, reason: String) -> void:
	if not unit.remove_status_effect(status_id):
		return
	if result != null:
		result.add_world_change({
			"type": "battle_status_removed",
			"battle_id": battle_state.battle_id,
			"target_id": unit.character_id,
			"status_id": status_id,
			"reason": reason,
			"automatic": true,
		})


static func _reduce_action_points(unit: BattleUnitState, amount: int, reason: String, battle_state: BattleState, result: ActionResult) -> void:
	var actual_reduction: int = mini(max(0, amount), unit.action_points)
	if actual_reduction <= 0:
		return
	unit.action_points -= actual_reduction
	if result != null:
		result.add_world_change({
			"type": "battle_action_points_reduced",
			"battle_id": battle_state.battle_id,
			"character_id": unit.character_id,
			"amount": actual_reduction,
			"remaining_ap": unit.action_points,
			"reason": reason,
		})
		result.add_feedback("%s 因%s失去 %d AP。" % [unit.display_name, _reason_label(reason), actual_reduction])


static func _deal_automatic_damage(
	unit: BattleUnitState,
	damage: int,
	tile_state,
	timing: String,
	battle_state: BattleState,
	result: ActionResult
) -> void:
	var actual_damage: int = unit.apply_damage(damage)
	if result != null:
		result.add_world_change({
			"type": "battle_unit_damaged",
			"battle_id": battle_state.battle_id,
			"attacker_id": tile_state.source_character_id,
			"target_id": unit.character_id,
			"damage": actual_damage,
			"hp": unit.hp,
			"max_hp": unit.max_hp,
			"damage_source": "tile_state",
			"tile_state_id": tile_state.id,
			"timing": timing,
		})
		result.add_feedback("%s 受到%s影响，损失 %d HP。" % [unit.display_name, _state_label(tile_state.id), actual_damage])
		_record_defeat_if_needed(unit, tile_state.source_character_id, battle_state, result)


static func _deal_skill_reaction_damage(
	unit: BattleUnitState,
	damage: int,
	reaction_id: String,
	source_character_id: String,
	battle_state: BattleState,
	result: ActionResult
) -> void:
	var actual_damage: int = unit.apply_damage(damage)
	if result != null:
		result.add_world_change({
			"type": "battle_unit_damaged",
			"battle_id": battle_state.battle_id,
			"attacker_id": source_character_id,
			"target_id": unit.character_id,
			"damage": actual_damage,
			"hp": unit.hp,
			"max_hp": unit.max_hp,
			"damage_source": "unit_reaction",
			"reaction_id": reaction_id,
		})
		result.add_feedback("%s 因湿润导电，额外损失 %d HP。" % [unit.display_name, actual_damage])
		_record_defeat_if_needed(unit, source_character_id, battle_state, result)


static func _deal_status_damage(
	unit: BattleUnitState,
	damage: int,
	status_id: String,
	source_character_id: String,
	battle_state: BattleState,
	result: ActionResult
) -> void:
	var actual_damage: int = unit.apply_damage(damage)
	if result != null:
		result.add_world_change({
			"type": "battle_unit_damaged",
			"battle_id": battle_state.battle_id,
			"attacker_id": source_character_id,
			"target_id": unit.character_id,
			"damage": actual_damage,
			"hp": unit.hp,
			"max_hp": unit.max_hp,
			"damage_source": "unit_status",
			"status_id": status_id,
			"timing": "turn_start",
		})
		result.add_feedback("%s 因燃烧状态损失 %d HP。" % [unit.display_name, actual_damage])
		_record_defeat_if_needed(unit, source_character_id, battle_state, result)


static func _record_defeat_if_needed(unit: BattleUnitState, source_character_id: String, battle_state: BattleState, result: ActionResult) -> void:
	if not unit.defeated or result == null:
		return
	result.add_world_change({
		"type": "battle_unit_defeated",
		"battle_id": battle_state.battle_id,
		"character_id": unit.character_id,
		"defeated_by": source_character_id,
	})
	result.add_feedback("%s 被击败。" % unit.display_name)


static func _status(
	status_id: String,
	display_name: String,
	expires: String,
	source_kind: String,
	extra: Dictionary = {}
) -> Dictionary:
	var result: Dictionary = {
		"status_id": status_id,
		"display_name": display_name,
		"source_kind": source_kind,
	}
	if not expires.is_empty():
		result["expires"] = expires
	for key in extra:
		result[key] = extra[key]
	return result


static func _get_skill_element_intensity(skill: Dictionary) -> int:
	var intensity: int = 1
	for effect_value in skill.get("effects", []) as Array:
		var effect: Dictionary = effect_value as Dictionary
		if str(effect.get("type", "")) != "apply_element":
			continue
		intensity = max(intensity, int(effect.get("intensity", 1)))
	return intensity


static func _state_label(state_id: String) -> String:
	match state_id:
		"burning":
			return "燃烧地面"
		"electrified":
			return "感电地面"
		_:
			return state_id


static func _reason_label(reason: String) -> String:
	match reason:
		"frozen_surface", "frozen_status":
			return "冻结"
		"electrified_surface", "shocked_status":
			return "感电"
		_:
			return reason

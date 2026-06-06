class_name BattleEffectResolver
extends RefCounted

const BattleTileStateScript := preload("res://scripts/systems/battle/battle_tile_state.gd")
const BattleElementReactionSystemScript := preload("res://scripts/systems/battle/battle_element_reaction_system.gd")


static func resolve_skill_effects(context: Dictionary, result: ActionResult) -> void:
	if result == null:
		return

	var skill: Dictionary = context.get("skill", {}) as Dictionary
	var effects: Array = skill.get("effects", []) as Array
	for effect_value in effects:
		var effect: Dictionary = effect_value as Dictionary
		resolve_effect(effect, context, result)


static func resolve_effect(effect: Dictionary, context: Dictionary, result: ActionResult) -> void:
	if result == null:
		return

	var effect_type: String = str(effect.get("type", ""))
	match effect_type:
		"damage_unit":
			_apply_damage_unit(effect, context, result)
		"heal_unit":
			_apply_heal_unit(effect, context, result)
		"apply_unit_status":
			_apply_unit_status(effect, context, result)
		"remove_unit_status":
			_remove_unit_status(effect, context, result)
		"apply_tile_state":
			_apply_tile_state(effect, context, result)
		"remove_tile_state":
			_remove_tile_state(effect, context, result)
		"apply_element":
			BattleElementReactionSystemScript.apply_element(effect, context, result)
		_:
			_record_ignored_battle_effect(effect_type, effect, context, result)


static func is_unit_damage_effect(effect: Dictionary) -> bool:
	return str(effect.get("type", "")) == "damage_unit"


static func is_unit_heal_effect(effect: Dictionary) -> bool:
	return str(effect.get("type", "")) == "heal_unit"


static func _apply_damage_unit(effect: Dictionary, context: Dictionary, result: ActionResult) -> void:
	var unit: BattleUnitState = context.get("caster") as BattleUnitState
	var skill: Dictionary = context.get("skill", {}) as Dictionary
	var battle_state: BattleState = context.get("battle_state") as BattleState
	if unit == null or battle_state == null:
		return

	var affected_units: Array[BattleUnitState] = _get_affected_units(context)
	for target_unit in affected_units:
		if target_unit == null:
			continue

		var damage: int = SkillSystem.calculate_damage(unit, target_unit, effect)
		var actual_damage: int = target_unit.apply_damage(damage)
		result.add_world_change({
			"type": "battle_unit_damaged",
			"battle_id": battle_state.battle_id,
			"skill_id": str(skill.get("id", "")),
			"attacker_id": unit.character_id,
			"target_id": target_unit.character_id,
			"damage": actual_damage,
			"hp": target_unit.hp,
			"max_hp": target_unit.max_hp,
			"remaining_ap": unit.action_points,
			"remaining_mp": unit.magic_points,
		})
		result.add_world_change({
			"type": "relation_delta",
			"scope": "character",
			"source_id": target_unit.character_id,
			"target_id": unit.character_id,
			"delta": { "affinity": -15, "trust": -10, "hostility": 35 },
			"reason": "attacked",
		})
		result.add_feedback("%s dealt %d damage to %s." % [unit.display_name, actual_damage, target_unit.display_name])

		if target_unit.defeated:
			result.add_world_change({
				"type": "battle_unit_defeated",
				"battle_id": battle_state.battle_id,
				"character_id": target_unit.character_id,
				"defeated_by": unit.character_id,
			})
			result.add_feedback("%s was defeated." % target_unit.display_name)


static func _apply_heal_unit(effect: Dictionary, context: Dictionary, result: ActionResult) -> void:
	var unit: BattleUnitState = context.get("caster") as BattleUnitState
	var skill: Dictionary = context.get("skill", {}) as Dictionary
	var battle_state: BattleState = context.get("battle_state") as BattleState
	if unit == null or battle_state == null:
		return

	var affected_units: Array[BattleUnitState] = _get_affected_units(context)
	for target_unit in affected_units:
		if target_unit == null:
			continue

		var heal_amount: int = SkillSystem.calculate_heal(unit, effect)
		var actual_heal: int = target_unit.apply_heal(heal_amount)
		result.add_world_change({
			"type": "battle_unit_healed",
			"battle_id": battle_state.battle_id,
			"skill_id": str(skill.get("id", "")),
			"source_id": unit.character_id,
			"target_id": target_unit.character_id,
			"healing": actual_heal,
			"hp": target_unit.hp,
			"max_hp": target_unit.max_hp,
			"remaining_ap": unit.action_points,
			"remaining_mp": unit.magic_points,
		})
		result.add_feedback("%s restored %d HP." % [target_unit.display_name, actual_heal])


static func _apply_unit_status(effect: Dictionary, context: Dictionary, result: ActionResult) -> void:
	var unit: BattleUnitState = context.get("caster") as BattleUnitState
	var skill: Dictionary = context.get("skill", {}) as Dictionary
	var battle_state: BattleState = context.get("battle_state") as BattleState
	if unit == null or battle_state == null:
		return

	var affected_units: Array[BattleUnitState] = _get_affected_units(context)
	if affected_units.is_empty():
		affected_units.append(unit)

	for target_unit in affected_units:
		if target_unit == null:
			continue

		target_unit.add_status_effect(effect)
		result.add_world_change({
			"type": "battle_status_applied",
			"battle_id": battle_state.battle_id,
			"skill_id": str(skill.get("id", "")),
			"source_id": unit.character_id,
			"target_id": target_unit.character_id,
			"status_id": str(effect.get("status_id", effect.get("id", ""))),
			"status": effect.duplicate(true),
		})
		result.add_feedback("%s gained status: %s." % [
			target_unit.display_name,
			str(effect.get("display_name", effect.get("status_id", "a status"))),
		])


static func _remove_unit_status(effect: Dictionary, context: Dictionary, result: ActionResult) -> void:
	var unit: BattleUnitState = context.get("caster") as BattleUnitState
	var skill: Dictionary = context.get("skill", {}) as Dictionary
	var battle_state: BattleState = context.get("battle_state") as BattleState
	if unit == null or battle_state == null:
		return

	var status_id: String = str(effect.get("status_id", effect.get("id", "")))
	if status_id.is_empty():
		return

	var affected_units: Array[BattleUnitState] = _get_affected_units(context)
	if affected_units.is_empty():
		affected_units.append(unit)

	for target_unit in affected_units:
		if target_unit == null or not target_unit.remove_status_effect(status_id):
			continue
		result.add_world_change({
			"type": "battle_status_removed",
			"battle_id": battle_state.battle_id,
			"skill_id": str(skill.get("id", "")),
			"source_id": unit.character_id,
			"target_id": target_unit.character_id,
			"status_id": status_id,
		})


static func _apply_tile_state(effect: Dictionary, context: Dictionary, result: ActionResult) -> void:
	var battle_state: BattleState = context.get("battle_state") as BattleState
	if battle_state == null:
		return

	var target_cells: Array[Vector2i] = _get_affected_cells(context)
	for cell in target_cells:
		var tile_state: RefCounted = BattleTileStateScript.from_effect(effect, cell, context)
		battle_state.apply_tile_state(tile_state, result)


static func _remove_tile_state(effect: Dictionary, context: Dictionary, result: ActionResult) -> void:
	var battle_state: BattleState = context.get("battle_state") as BattleState
	if battle_state == null:
		return

	var state_id: String = str(effect.get("state_id", effect.get("id", "")))
	var target_cells: Array[Vector2i] = _get_affected_cells(context)
	for cell in target_cells:
		battle_state.remove_tile_state(cell, state_id, result)


static func _record_ignored_battle_effect(effect_type: String, effect: Dictionary, context: Dictionary, result: ActionResult) -> void:
	var unit: BattleUnitState = context.get("caster") as BattleUnitState
	var skill: Dictionary = context.get("skill", {}) as Dictionary
	var battle_state: BattleState = context.get("battle_state") as BattleState
	var battle_id: String = battle_state.battle_id if battle_state != null else ""
	result.add_world_change({
		"type": "battle_skill_effect_ignored",
		"battle_id": battle_id,
		"character_id": unit.character_id if unit != null else "",
		"skill_id": str(skill.get("id", "")),
		"effect_type": effect_type,
		"effect": effect.duplicate(true),
	})


static func _get_affected_units(context: Dictionary) -> Array[BattleUnitState]:
	var result: Array[BattleUnitState] = []
	var affected_units: Array = context.get("affected_units", []) as Array
	for unit_value in affected_units:
		var unit: BattleUnitState = unit_value as BattleUnitState
		if unit != null:
			result.append(unit)
	return result


static func _get_affected_cells(context: Dictionary) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var affected_cells: Array = context.get("affected_cells", []) as Array
	for cell_value in affected_cells:
		var cell: Vector2i = cell_value as Vector2i
		if not result.has(cell):
			result.append(cell)

	if result.is_empty():
		result.append(context.get("target_cell", Vector2i.ZERO) as Vector2i)

	return result

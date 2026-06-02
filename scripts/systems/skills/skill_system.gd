extends Node

signal skills_loaded(count: int)

const SKILL_PATHS = [
	"res://data/skills/basic_attack.json",
	"res://data/skills/power_strike.json",
	"res://data/skills/guard.json",
	"res://data/skills/quick_shot.json",
	"res://data/skills/first_aid.json",
	"res://data/skills/shockwave.json",
]

var skill_definitions: Dictionary = {}


func _ready() -> void:
	_load_skill_definitions()


func get_skill(skill_id: String) -> Dictionary:
	if skill_id.is_empty() or not skill_definitions.has(skill_id):
		return {}

	var skill: Dictionary = skill_definitions[skill_id] as Dictionary
	return skill.duplicate(true)


func get_skill_summaries_for_unit(unit: BattleUnitState, battle_state: BattleState) -> Array[Dictionary]:
	var summaries: Array[Dictionary] = []
	if unit == null:
		return summaries

	for skill_id in unit.skills:
		var skill: Dictionary = get_skill(str(skill_id))
		if skill.is_empty():
			continue

		var target_cell: Vector2i = unit.character.grid_position
		var target_cells: Array[Vector2i] = get_range_cells(unit, str(skill.get("id", "")), battle_state)
		if not target_cells.is_empty():
			target_cell = target_cells[0]

		var failure_reason: String = get_skill_failure(unit, str(skill.get("id", "")), target_cell, battle_state)
		for candidate_cell in target_cells:
			var candidate_failure: String = get_skill_failure(unit, str(skill.get("id", "")), candidate_cell, battle_state)
			if candidate_failure.is_empty():
				target_cell = candidate_cell
				failure_reason = ""
				break
			if failure_reason.is_empty():
				failure_reason = candidate_failure
		var summary: Dictionary = skill.duplicate(true)
		summary["can_use"] = failure_reason.is_empty()
		summary["failure_reason"] = failure_reason
		summary["target_cells"] = target_cells
		summary["cooldown_remaining"] = unit.get_skill_cooldown(str(skill.get("id", "")))
		summaries.append(summary)

	return summaries


func get_target_cells(unit: BattleUnitState, skill_id: String, battle_state: BattleState) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if unit == null or not unit.is_active() or battle_state == null or not battle_state.active:
		return result

	var skill: Dictionary = get_skill(skill_id)
	if skill.is_empty():
		return result

	var target_type: String = str(skill.get("target_type", "enemy"))
	var skill_range: int = max(0, int(skill.get("range", 1)))
	match target_type:
		"self":
			result.append(unit.character.grid_position)
		"enemy":
			_append_unit_target_cells(result, unit, battle_state, skill_range, "enemy")
		"ally":
			_append_unit_target_cells(result, unit, battle_state, skill_range, "ally")
		"ally_or_self":
			_append_unit_target_cells(result, unit, battle_state, skill_range, "ally")
		_:
			pass

	return result


func get_range_cells(unit: BattleUnitState, skill_id: String, battle_state: BattleState) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if unit == null or not unit.is_active() or battle_state == null or not battle_state.active or battle_state.grid == null:
		return result

	var skill: Dictionary = get_skill(skill_id)
	if skill.is_empty():
		return result

	var origin: Vector2i = unit.character.grid_position
	var target_type: String = str(skill.get("target_type", "enemy"))
	var skill_range: int = max(0, int(skill.get("range", 1)))
	if target_type == "self":
		result.append(origin)
		return result

	for x in range(origin.x - skill_range, origin.x + skill_range + 1):
		for y in range(origin.y - skill_range, origin.y + skill_range + 1):
			var cell: Vector2i = Vector2i(x, y)
			if not battle_state.grid.in_bounds(cell):
				continue
			var distance: int = _manhattan(origin, cell)
			if distance > skill_range:
				continue
			if distance == 0 and target_type != "ally_or_self":
				continue
			if not _has_line_of_sight(unit, cell, battle_state):
				continue
			result.append(cell)

	return result


func get_skill_failure(unit: BattleUnitState, skill_id: String, target_cell: Vector2i, battle_state: BattleState) -> String:
	if unit == null or not unit.is_active():
		return "技能需要有效的战斗单位。"
	if battle_state == null or not battle_state.active:
		return "技能需要处于战斗中。"

	var skill: Dictionary = get_skill(skill_id)
	if skill.is_empty():
		return "未知技能：%s" % skill_id
	if not unit.skills.has(skill_id):
		return "%s 不会使用 %s。" % [unit.display_name, skill_id]

	var ap_cost: int = max(0, int(skill.get("ap_cost", 0)))
	if unit.action_points < ap_cost:
		return "%s 需要 %d 行动点。" % [str(skill.get("display_name", skill_id)), ap_cost]
	if unit.get_skill_cooldown(skill_id) > 0:
		return "%s 还在冷却中。" % str(skill.get("display_name", skill_id))

	var target_type: String = str(skill.get("target_type", "enemy"))
	var skill_range: int = max(0, int(skill.get("range", 1)))
	if target_type == "self":
		if target_cell != unit.character.grid_position:
			return "%s 只能以自己为目标。" % str(skill.get("display_name", skill_id))
		return ""

	if battle_state.grid != null and not battle_state.grid.in_bounds(target_cell):
		return "%s 需要有效的目标格。" % str(skill.get("display_name", skill_id))
	if _manhattan(unit.character.grid_position, target_cell) > skill_range:
		return "%s 超出射程。" % str(skill.get("display_name", skill_id))
	if not _has_line_of_sight(unit, target_cell, battle_state):
		return "%s 的视线被阻挡。" % str(skill.get("display_name", skill_id))

	var target_unit: BattleUnitState = battle_state.get_unit_at(target_cell)
	if target_type == "enemy":
		if target_unit == null:
			if _can_target_empty_cell(skill):
				return ""
			return "%s 需要敌方目标。" % str(skill.get("display_name", skill_id))
		if not target_unit.is_active() or target_unit.team == unit.team:
			return "%s 需要敌方目标。" % str(skill.get("display_name", skill_id))
		return ""

	if target_type == "ally":
		if target_unit == null or not target_unit.is_active() or target_unit.team != unit.team:
			return "%s 需要友方目标。" % str(skill.get("display_name", skill_id))
		return ""

	if target_type == "ally_or_self":
		if target_unit == null or not target_unit.is_active() or target_unit.team != unit.team:
			return "%s 需要友方或自己作为目标。" % str(skill.get("display_name", skill_id))
		return ""

	return "不支持的目标类型：%s" % target_type


func get_affected_units(unit: BattleUnitState, skill_id: String, target_cell: Vector2i, battle_state: BattleState) -> Array[BattleUnitState]:
	var result: Array[BattleUnitState] = []
	if unit == null or battle_state == null:
		return result

	var skill: Dictionary = get_skill(skill_id)
	if skill.is_empty():
		return result

	var area: String = str(skill.get("area", "single"))
	var radius: int = max(0, int(skill.get("radius", 0)))
	var target_type: String = str(skill.get("target_type", "enemy"))
	if area == "single":
		var target_unit: BattleUnitState = _resolve_target_unit(unit, target_type, target_cell, battle_state)
		if target_unit != null:
			result.append(target_unit)
		return result

	if area == "radius":
		for possible_target in battle_state.units:
			if possible_target == null or not possible_target.is_active():
				continue
			if _manhattan(possible_target.character.grid_position, target_cell) > radius:
				continue
			if _unit_matches_target_type(unit, possible_target, target_type):
				result.append(possible_target)

	return result


func get_area_cells(skill_id: String, target_cell: Vector2i, battle_state: BattleState) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if battle_state == null or battle_state.grid == null:
		return result

	var skill: Dictionary = get_skill(skill_id)
	if skill.is_empty():
		return result

	var area: String = str(skill.get("area", "single"))
	if area != "radius":
		if battle_state.grid.in_bounds(target_cell):
			result.append(target_cell)
		return result

	var radius: int = max(0, int(skill.get("radius", 0)))
	for x in range(target_cell.x - radius, target_cell.x + radius + 1):
		for y in range(target_cell.y - radius, target_cell.y + radius + 1):
			var cell: Vector2i = Vector2i(x, y)
			if not battle_state.grid.in_bounds(cell):
				continue
			if _manhattan(cell, target_cell) > radius:
				continue
			result.append(cell)

	return result


func calculate_damage(attacker: BattleUnitState, defender: BattleUnitState, effect: Dictionary) -> int:
	var formula: String = str(effect.get("formula", "strength"))
	var power: int = int(effect.get("power", 0))
	var attack_value: int = power
	match formula:
		"strength":
			attack_value += int(attacker.character.get_effective_attributes().get("strength", 1))
		"intellect":
			attack_value += int(attacker.character.get_effective_attributes().get("intellect", 1))
		"agility":
			attack_value += int(attacker.character.get_effective_attributes().get("agility", 1))
		"flat":
			pass
		_:
			attack_value += int(attacker.character.get_effective_attributes().get("strength", 1))

	var vitality: int = int(defender.character.get_effective_attributes().get("vitality", 1))
	var raw_damage: int = max(1, attack_value - int(vitality / 2.0))
	return max(0, raw_damage - defender.get_defense_bonus())


func calculate_heal(source: BattleUnitState, effect: Dictionary) -> int:
	var formula: String = str(effect.get("formula", "flat"))
	var power: int = int(effect.get("power", 0))
	match formula:
		"intellect":
			return max(1, power + int(source.character.get_effective_attributes().get("intellect", 1)))
		"vitality":
			return max(1, power + int(source.character.get_effective_attributes().get("vitality", 1)))
		"flat":
			return max(1, power)
		_:
			return max(1, power)


func estimate_damage(attacker: BattleUnitState, defender: BattleUnitState, skill_id: String) -> int:
	var skill: Dictionary = get_skill(skill_id)
	if skill.is_empty():
		return 0

	var total: int = 0
	var effects: Array = skill.get("effects", []) as Array
	for effect_value in effects:
		var effect: Dictionary = effect_value as Dictionary
		if str(effect.get("type", "")) == "damage":
			total += calculate_damage(attacker, defender, effect)

	return total


func skill_has_effect(skill_id: String, effect_type: String) -> bool:
	var skill: Dictionary = get_skill(skill_id)
	if skill.is_empty():
		return false

	var effects: Array = skill.get("effects", []) as Array
	for effect_value in effects:
		var effect: Dictionary = effect_value as Dictionary
		if str(effect.get("type", "")) == effect_type:
			return true

	return false


func estimate_heal(source: BattleUnitState, skill_id: String) -> int:
	var skill: Dictionary = get_skill(skill_id)
	if skill.is_empty():
		return 0

	var total: int = 0
	var effects: Array = skill.get("effects", []) as Array
	for effect_value in effects:
		var effect: Dictionary = effect_value as Dictionary
		if str(effect.get("type", "")) == "heal":
			total += calculate_heal(source, effect)

	return total


func can_target_empty_cell(skill_id: String) -> bool:
	return _can_target_empty_cell(get_skill(skill_id))


func format_feedback(template: String, actor_name: String, target_name: String) -> String:
	var result: String = template
	result = result.replace("{actor}", actor_name)
	result = result.replace("{target}", target_name)
	return result


func _load_skill_definitions() -> void:
	skill_definitions.clear()
	for skill_path in SKILL_PATHS:
		var skill: Dictionary = DefinitionLoader.load_skill(skill_path)
		if skill.is_empty():
			continue

		var skill_id: String = str(skill.get("id", ""))
		if skill_id.is_empty():
			push_error("SkillSystem skill has no id: %s" % skill_path)
			continue

		skill_definitions[skill_id] = skill

	skills_loaded.emit(skill_definitions.size())


func _manhattan(a: Vector2i, b: Vector2i) -> int:
	return abs(a.x - b.x) + abs(a.y - b.y)


func _append_unit_target_cells(result: Array[Vector2i], unit: BattleUnitState, battle_state: BattleState, skill_range: int, mode: String) -> void:
	for target_unit in battle_state.units:
		if target_unit == null or not target_unit.is_active():
			continue
		if mode == "enemy" and target_unit.team == unit.team:
			continue
		if mode == "ally" and target_unit.team != unit.team:
			continue
		if _manhattan(unit.character.grid_position, target_unit.character.grid_position) <= skill_range:
			if _has_line_of_sight(unit, target_unit.character.grid_position, battle_state):
				result.append(target_unit.character.grid_position)


func _resolve_target_unit(unit: BattleUnitState, target_type: String, target_cell: Vector2i, battle_state: BattleState) -> BattleUnitState:
	if target_type == "self":
		return unit

	var target_unit: BattleUnitState = battle_state.get_unit_at(target_cell)
	if target_unit != null and _unit_matches_target_type(unit, target_unit, target_type):
		return target_unit

	return null


func _unit_matches_target_type(unit: BattleUnitState, target_unit: BattleUnitState, target_type: String) -> bool:
	match target_type:
		"self":
			return target_unit.character_id == unit.character_id
		"enemy":
			return target_unit.team != unit.team
		"ally", "ally_or_self":
			return target_unit.team == unit.team
		_:
			return false


func _can_target_empty_cell(skill: Dictionary) -> bool:
	if skill.is_empty():
		return false
	if str(skill.get("target_type", "enemy")) != "enemy":
		return false

	var effects: Array = skill.get("effects", []) as Array
	for effect_value in effects:
		var effect: Dictionary = effect_value as Dictionary
		if str(effect.get("type", "")) == "damage":
			return true

	return false


func _has_line_of_sight(unit: BattleUnitState, target_cell: Vector2i, battle_state: BattleState) -> bool:
	if unit == null or battle_state == null or battle_state.grid == null:
		return false

	if target_cell == unit.character.grid_position:
		return true

	if battle_state.grid.has_method("has_line_of_sight"):
		return bool(battle_state.grid.has_line_of_sight(unit.character.grid_position, target_cell))

	return true

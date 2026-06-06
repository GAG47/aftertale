extends Node

signal skills_loaded(count: int)

const BattleEffectResolverScript := preload("res://scripts/systems/battle/battle_effect_resolver.gd")
const SKILL_DIRECTORY := "res://data/skills"
const TARGET_POLICY_UNIT_REQUIRED := "unit_required"
const TARGET_POLICY_EMPTY_REQUIRED := "empty_required"
const TARGET_POLICY_CELL := "cell"
const PATH_BLOCKING_TERRAIN_AND_UNITS := "terrain_and_units"
const PATH_BLOCKING_TERRAIN_ONLY := "terrain_only"
const VALID_TARGET_POLICIES := [
	TARGET_POLICY_UNIT_REQUIRED,
	TARGET_POLICY_EMPTY_REQUIRED,
	TARGET_POLICY_CELL,
]
const VALID_PATH_BLOCKING := [
	PATH_BLOCKING_TERRAIN_AND_UNITS,
	PATH_BLOCKING_TERRAIN_ONLY,
]
const VALID_TARGET_TYPES := ["self", "enemy", "ally", "ally_or_self"]
const VALID_AREAS := ["single", "radius", "line"]
const VALID_ELEMENTS := ["fire", "water", "ice", "lightning"]
const VALID_EFFECT_TYPES := [
	"damage_unit",
	"heal_unit",
	"apply_unit_status",
	"remove_unit_status",
	"apply_tile_state",
	"remove_tile_state",
	"apply_element",
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
		summary["mp_cost"] = max(0, int(skill.get("mp_cost", 0)))
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
	var target_policy: String = get_target_policy(skill)
	if target_policy != TARGET_POLICY_UNIT_REQUIRED:
		for cell in get_range_cells(unit, skill_id, battle_state):
			if target_policy == TARGET_POLICY_EMPTY_REQUIRED and not _is_empty_target_cell(cell, battle_state):
				continue
			result.append(cell)
		return result

	match target_type:
		"self":
			result.append(unit.character.grid_position)
		"enemy":
			_append_unit_target_cells(result, unit, battle_state, skill, skill_range, "enemy")
		"ally":
			_append_unit_target_cells(result, unit, battle_state, skill, skill_range, "ally")
		"ally_or_self":
			_append_unit_target_cells(result, unit, battle_state, skill, skill_range, "ally")
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
	var target_policy: String = get_target_policy(skill)
	var skill_range: int = max(0, int(skill.get("range", 1)))
	if target_type == "self":
		result.append(origin)
		return result

	if str(skill.get("area", "single")) == "line":
		var directions: Array[Vector2i] = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
		for direction in directions:
			for distance in range(1, skill_range + 1):
				var cell: Vector2i = origin + direction * distance
				if not battle_state.grid.in_bounds(cell):
					break
				if not _has_skill_path(skill, origin, cell, battle_state):
					break
				if target_policy == TARGET_POLICY_EMPTY_REQUIRED and not _is_empty_target_cell(cell, battle_state):
					continue
				result.append(cell)
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
			if not _has_skill_path(skill, origin, cell, battle_state):
				continue
			if target_policy == TARGET_POLICY_EMPTY_REQUIRED and not _is_empty_target_cell(cell, battle_state):
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
	var mp_cost: int = max(0, int(skill.get("mp_cost", 0)))
	if unit.magic_points < mp_cost:
		return "%s 需要 %d MP。" % [str(skill.get("display_name", skill_id)), mp_cost]
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
	if str(skill.get("area", "single")) == "line" and not _is_cardinal_line(unit.character.grid_position, target_cell):
		return "%s requires a straight line target." % str(skill.get("display_name", skill_id))
	if not _has_skill_path(skill, unit.character.grid_position, target_cell, battle_state):
		return "%s 的视线被阻挡。" % str(skill.get("display_name", skill_id))

	var target_unit: BattleUnitState = battle_state.get_unit_at(target_cell)
	var target_policy: String = get_target_policy(skill)
	if target_policy == TARGET_POLICY_EMPTY_REQUIRED:
		if not _is_empty_target_cell(target_cell, battle_state):
			return "%s requires an empty walkable cell." % str(skill.get("display_name", skill_id))
		return ""
	if target_policy == TARGET_POLICY_CELL:
		return ""

	if target_type == "enemy":
		if target_unit == null:
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

	if area == "line":
		var area_cells: Array[Vector2i] = get_area_cells(skill_id, target_cell, battle_state, unit.character.grid_position)
		for possible_target in battle_state.units:
			if possible_target == null or not possible_target.is_active():
				continue
			if not area_cells.has(possible_target.character.grid_position):
				continue
			if _unit_matches_target_type(unit, possible_target, target_type):
				result.append(possible_target)
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


func get_area_cells(skill_id: String, target_cell: Vector2i, battle_state: BattleState, origin_cell: Variant = null) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if battle_state == null or battle_state.grid == null:
		return result

	var skill: Dictionary = get_skill(skill_id)
	if skill.is_empty():
		return result

	var area: String = str(skill.get("area", "single"))
	if area == "line":
		if origin_cell is Vector2i:
			return _line_area_cells(origin_cell as Vector2i, target_cell, battle_state)
		if battle_state.grid.in_bounds(target_cell):
			result.append(target_cell)
		return result

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
		if BattleEffectResolverScript.is_unit_damage_effect(effect):
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
		if BattleEffectResolverScript.is_unit_heal_effect(effect):
			total += calculate_heal(source, effect)

	return total


func get_target_policy(skill: Dictionary) -> String:
	return str(skill.get("target_policy", ""))


func get_path_blocking(skill: Dictionary) -> String:
	return str(skill.get("path_blocking", ""))


func format_feedback(template: String, actor_name: String, target_name: String) -> String:
	var result: String = template
	result = result.replace("{actor}", actor_name)
	result = result.replace("{target}", target_name)
	return result


func _load_skill_definitions() -> void:
	skill_definitions.clear()
	for skill_path in _get_skill_paths():
		var skill: Dictionary = DefinitionLoader.load_skill(skill_path)
		if skill.is_empty():
			continue

		var skill_id: String = str(skill.get("id", ""))
		if skill_id.is_empty():
			push_error("SkillSystem skill has no id: %s" % skill_path)
			continue

		var validation_error: String = _get_skill_definition_error(skill)
		if not validation_error.is_empty():
			push_error("SkillSystem invalid skill %s (%s): %s" % [skill_id, skill_path, validation_error])
			continue
		skill_definitions[skill_id] = skill

	skills_loaded.emit(skill_definitions.size())


func _get_skill_paths() -> Array[String]:
	var result: Array[String] = []
	var directory: DirAccess = DirAccess.open(SKILL_DIRECTORY)
	if directory == null:
		push_error("SkillSystem could not open skill directory: %s" % SKILL_DIRECTORY)
		return result

	directory.list_dir_begin()
	var file_name: String = directory.get_next()
	while not file_name.is_empty():
		if not directory.current_is_dir() and file_name.ends_with(".json"):
			result.append("%s/%s" % [SKILL_DIRECTORY, file_name])
		file_name = directory.get_next()
	directory.list_dir_end()
	result.sort()
	return result


func _get_skill_definition_error(skill: Dictionary) -> String:
	var target_type: String = str(skill.get("target_type", ""))
	if not VALID_TARGET_TYPES.has(target_type):
		return "target_type must be one of: %s" % ", ".join(VALID_TARGET_TYPES)

	var target_policy: String = get_target_policy(skill)
	if not VALID_TARGET_POLICIES.has(target_policy):
		return "target_policy must be one of: %s" % ", ".join(VALID_TARGET_POLICIES)

	var path_blocking: String = get_path_blocking(skill)
	if not VALID_PATH_BLOCKING.has(path_blocking):
		return "path_blocking must be one of: %s" % ", ".join(VALID_PATH_BLOCKING)

	var area: String = str(skill.get("area", ""))
	if not VALID_AREAS.has(area):
		return "area must be one of: %s" % ", ".join(VALID_AREAS)
	if area == "radius" and int(skill.get("radius", -1)) < 0:
		return "radius area requires a non-negative radius"

	var effects: Array = skill.get("effects", []) as Array
	if effects.is_empty():
		return "effects must contain at least one effect"
	for effect_index in range(effects.size()):
		var effect: Dictionary = effects[effect_index] as Dictionary
		var effect_type: String = str(effect.get("type", ""))
		if not VALID_EFFECT_TYPES.has(effect_type):
			return "effects[%d].type is unsupported: %s" % [effect_index, effect_type]
		if effect_type == "apply_element":
			var element: String = str(effect.get("element", ""))
			if not VALID_ELEMENTS.has(element):
				return "effects[%d].element must be one of: %s" % [effect_index, ", ".join(VALID_ELEMENTS)]
			if int(effect.get("intensity", 1)) < 1:
				return "effects[%d].intensity must be at least 1" % effect_index

	return ""


func _manhattan(a: Vector2i, b: Vector2i) -> int:
	return abs(a.x - b.x) + abs(a.y - b.y)


func _append_unit_target_cells(result: Array[Vector2i], unit: BattleUnitState, battle_state: BattleState, skill: Dictionary, skill_range: int, mode: String) -> void:
	for target_unit in battle_state.units:
		if target_unit == null or not target_unit.is_active():
			continue
		if mode == "enemy" and target_unit.team == unit.team:
			continue
		if mode == "ally" and target_unit.team != unit.team:
			continue
		if _manhattan(unit.character.grid_position, target_unit.character.grid_position) <= skill_range:
			if _has_skill_path(skill, unit.character.grid_position, target_unit.character.grid_position, battle_state):
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


func _line_area_cells(origin_cell: Vector2i, target_cell: Vector2i, battle_state: BattleState) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if battle_state == null or battle_state.grid == null:
		return result
	if not _is_cardinal_line(origin_cell, target_cell):
		return result

	var direction: Vector2i = Vector2i.ZERO
	if target_cell.x > origin_cell.x:
		direction = Vector2i.RIGHT
	elif target_cell.x < origin_cell.x:
		direction = Vector2i.LEFT
	elif target_cell.y > origin_cell.y:
		direction = Vector2i.DOWN
	elif target_cell.y < origin_cell.y:
		direction = Vector2i.UP

	var cell: Vector2i = origin_cell + direction
	while cell != target_cell + direction:
		if not battle_state.grid.in_bounds(cell):
			break
		result.append(cell)
		cell += direction

	return result


func _is_cardinal_line(origin_cell: Vector2i, target_cell: Vector2i) -> bool:
	return origin_cell != target_cell and (origin_cell.x == target_cell.x or origin_cell.y == target_cell.y)


func _has_skill_path(skill: Dictionary, origin_cell: Vector2i, target_cell: Vector2i, battle_state: BattleState) -> bool:
	if battle_state == null or battle_state.grid == null:
		return false
	if origin_cell == target_cell:
		return true

	var block_units: bool = get_path_blocking(skill) == PATH_BLOCKING_TERRAIN_AND_UNITS
	if battle_state.grid.has_method("has_clear_skill_path"):
		return bool(battle_state.grid.has_clear_skill_path(origin_cell, target_cell, block_units))
	return battle_state.grid.has_line_of_sight(origin_cell, target_cell)


func _is_empty_target_cell(cell: Vector2i, battle_state: BattleState) -> bool:
	if battle_state == null or battle_state.grid == null:
		return false
	if not battle_state.grid.in_bounds(cell) or not battle_state.grid.is_walkable(cell):
		return false
	if battle_state.get_unit_at(cell) != null:
		return false
	return not battle_state.grid.is_occupied(cell)

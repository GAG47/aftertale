class_name BattleAiPlanner
extends RefCounted

const BattleAiProfileRegistryScript := preload("res://scripts/systems/battle/battle_ai_profile_registry.gd")
const MAX_CANDIDATES := 320
const TOP_CANDIDATE_COUNT := 5
const CARDINAL_DIRECTIONS: Array[Vector2i] = [
	Vector2i.UP,
	Vector2i.LEFT,
	Vector2i.RIGHT,
	Vector2i.DOWN,
]
const SCORE_LABELS := {
	"damage": "伤害收益",
	"kill": "击杀收益",
	"control": "控制收益",
	"survival": "生存收益",
	"tile": "地格收益",
	"position": "位置收益",
	"target": "目标优先级",
	"risk": "风险惩罚",
	"resource": "资源消耗",
	"support": "支援收益",
	"reaction": "元素反应",
}


static func plan(unit: BattleUnitState, battle_state: BattleState) -> Dictionary:
	if unit == null or not unit.is_active() or battle_state == null or not battle_state.active:
		return {}

	var profile: Dictionary = BattleAiProfileRegistryScript.get_profile(unit.ai_profile_id)
	var candidates: Array[Dictionary] = []
	var reachable_cells: Array[Dictionary] = _get_reachable_cells(unit, battle_state)
	_append_wait_candidate(candidates, unit, battle_state, profile)
	for reachable in reachable_cells:
		if candidates.size() >= MAX_CANDIDATES:
			break
		var origin: Vector2i = reachable.get("cell", unit.character.grid_position) as Vector2i
		var move_cost: int = int(reachable.get("cost", 0))
		if move_cost > 0:
			_append_scored_candidate(candidates, {
				"action_type": "move",
				"move_cell": origin,
				"move_cost": move_cost,
				"skill_id": "",
				"target_cell": origin,
			}, unit, battle_state, profile)
		_append_skill_candidates(candidates, unit, origin, move_cost, battle_state, profile)

	candidates.sort_custom(_compare_candidates)
	if candidates.is_empty():
		return {}

	var chosen: Dictionary = candidates[0].duplicate(true)
	var top_candidates: Array[Dictionary] = []
	for index in range(mini(TOP_CANDIDATE_COUNT, candidates.size())):
		top_candidates.append(_decision_candidate_summary(candidates[index]))

	return {
		"character_id": unit.character_id,
		"profile_id": str(profile.get("id", "balanced")),
		"candidate_count": candidates.size(),
		"chosen": chosen,
		"top_candidates": top_candidates,
		"summary": "AI选择：%s，总分 %.1f" % [
			str(chosen.get("description", chosen.get("action_type", "wait"))),
			float(chosen.get("total_score", 0.0)),
		],
	}


static func _append_wait_candidate(
	candidates: Array[Dictionary],
	unit: BattleUnitState,
	battle_state: BattleState,
	profile: Dictionary
) -> void:
	_append_scored_candidate(candidates, {
		"action_type": "wait",
		"move_cell": unit.character.grid_position,
		"move_cost": 0,
		"skill_id": "",
		"target_cell": unit.character.grid_position,
	}, unit, battle_state, profile)


static func _append_skill_candidates(
	candidates: Array[Dictionary],
	unit: BattleUnitState,
	origin: Vector2i,
	move_cost: int,
	battle_state: BattleState,
	profile: Dictionary
) -> void:
	for skill_id_value in unit.skills:
		if candidates.size() >= MAX_CANDIDATES:
			return
		var skill_id: String = str(skill_id_value)
		var skill: Dictionary = SkillSystem.get_skill(skill_id)
		if skill.is_empty():
			continue
		var ap_cost: int = max(0, int(skill.get("ap_cost", 0)))
		if move_cost + ap_cost > unit.action_points:
			continue
		if max(0, int(skill.get("mp_cost", 0))) > unit.magic_points:
			continue
		if unit.get_skill_cooldown(skill_id) > 0:
			continue

		var target_cells: Array[Vector2i] = SkillSystem.get_target_cells(unit, skill_id, battle_state, origin)
		for target_cell in target_cells:
			if candidates.size() >= MAX_CANDIDATES:
				return
			var failure: String = SkillSystem.get_skill_failure(unit, skill_id, target_cell, battle_state, origin)
			if not failure.is_empty():
				continue
			_append_scored_candidate(candidates, {
				"action_type": "skill" if move_cost == 0 else "move_and_skill",
				"move_cell": origin,
				"move_cost": move_cost,
				"skill_id": skill_id,
				"target_cell": target_cell,
			}, unit, battle_state, profile)


static func _append_scored_candidate(
	candidates: Array[Dictionary],
	base_candidate: Dictionary,
	unit: BattleUnitState,
	battle_state: BattleState,
	profile: Dictionary
) -> void:
	var candidate: Dictionary = base_candidate.duplicate(true)
	var breakdown: Dictionary = {
		"damage": 0.0,
		"kill": 0.0,
		"control": 0.0,
		"survival": 0.0,
		"tile": 0.0,
		"position": 0.0,
		"target": 0.0,
		"risk": 0.0,
		"resource": 0.0,
		"support": 0.0,
		"reaction": 0.0,
	}
	var destination: Vector2i = candidate.get("move_cell", unit.character.grid_position) as Vector2i
	_score_destination(breakdown, unit, destination, battle_state, profile)

	var action_type: String = str(candidate.get("action_type", "wait"))
	if action_type == "move" or action_type == "move_and_skill":
		breakdown["resource"] = float(breakdown["resource"]) - float(int(candidate.get("move_cost", 0)))
	if action_type == "skill" or action_type == "move_and_skill":
		_score_skill(breakdown, candidate, unit, battle_state)

	var weights: Dictionary = profile.get("weights", {}) as Dictionary
	var score_entries: Array[Dictionary] = []
	var total_score: float = 0.0
	for score_id_value in breakdown.keys():
		var score_id: String = str(score_id_value)
		var raw_score: float = float(breakdown.get(score_id, 0.0))
		if is_zero_approx(raw_score):
			continue
		var weight: float = float(weights.get(score_id, 1.0))
		var weighted_score: float = raw_score * weight
		total_score += weighted_score
		score_entries.append({
			"id": score_id,
			"label": str(SCORE_LABELS.get(score_id, score_id)),
			"raw": snappedf(raw_score, 0.1),
			"weight": snappedf(weight, 0.1),
			"weighted": snappedf(weighted_score, 0.1),
		})
	score_entries.sort_custom(_compare_score_entries)

	candidate["score_breakdown"] = score_entries
	candidate["total_score"] = snappedf(total_score, 0.1)
	candidate["description"] = _describe_candidate(candidate, unit)
	candidate["reasons"] = _format_reasons(score_entries)
	candidates.append(candidate)


static func _score_destination(
	breakdown: Dictionary,
	unit: BattleUnitState,
	destination: Vector2i,
	battle_state: BattleState,
	profile: Dictionary
) -> void:
	var nearest_distance: int = _nearest_opponent_distance(unit, destination, battle_state)
	var preferred_range: int = max(1, int(profile.get("preferred_range", 1)))
	if nearest_distance < 999:
		breakdown["position"] = maxf(0.0, 8.0 - absf(float(nearest_distance - preferred_range)) * 2.0)
		var hp_ratio: float = float(unit.hp) / float(max(1, unit.max_hp))
		if hp_ratio <= 0.5:
			breakdown["survival"] = float(nearest_distance) * (1.0 + (0.5 - hp_ratio) * 2.0)

	var adjacent_opponents: int = 0
	for other_unit in battle_state.units:
		if other_unit == null or not other_unit.is_active() or other_unit.team == unit.team:
			continue
		if _manhattan(destination, other_unit.character.grid_position) == 1:
			adjacent_opponents += 1
	breakdown["risk"] = float(breakdown["risk"]) - float(adjacent_opponents * 4)

	var tile_state = battle_state.get_tile_state_at(destination)
	if tile_state == null:
		return
	var intensity: int = max(1, int(tile_state.intensity))
	match tile_state.id:
		"burning", "electrified":
			breakdown["risk"] = float(breakdown["risk"]) - float(12 * intensity)
		"frozen":
			breakdown["risk"] = float(breakdown["risk"]) - float(5 * intensity)
		"wet":
			breakdown["risk"] = float(breakdown["risk"]) - 1.0


static func _score_skill(
	breakdown: Dictionary,
	candidate: Dictionary,
	unit: BattleUnitState,
	battle_state: BattleState
) -> void:
	var skill_id: String = str(candidate.get("skill_id", ""))
	var skill: Dictionary = SkillSystem.get_skill(skill_id)
	if skill.is_empty():
		return

	var origin: Vector2i = candidate.get("move_cell", unit.character.grid_position) as Vector2i
	var target_cell: Vector2i = candidate.get("target_cell", origin) as Vector2i
	var affected_units: Array[BattleUnitState] = SkillSystem.get_affected_units(unit, skill_id, target_cell, battle_state, origin)
	var affected_cells: Array[Vector2i] = SkillSystem.get_area_cells(skill_id, target_cell, battle_state, origin)
	var element: String = str(skill.get("element", ""))
	var element_intensity: int = _get_element_intensity(skill)
	var damage_effect: bool = SkillSystem.skill_has_effect(skill_id, "damage_unit")
	var heal_effect: bool = SkillSystem.skill_has_effect(skill_id, "heal_unit")

	for target_unit in affected_units:
		if target_unit == null or not target_unit.is_active():
			continue
		if target_unit.team != unit.team:
			var estimated_damage: int = SkillSystem.estimate_damage(unit, target_unit, skill_id) if damage_effect else 0
			var reaction_damage: int = _score_unit_reaction(breakdown, target_unit, element, element_intensity, battle_state)
			var total_damage: int = estimated_damage + reaction_damage
			breakdown["damage"] = float(breakdown["damage"]) + float(total_damage)
			if total_damage >= target_unit.hp and total_damage > 0:
				breakdown["kill"] = float(breakdown["kill"]) + 100.0
			elif total_damage > 0 and target_unit.hp - total_damage <= maxi(1, int(ceil(float(target_unit.max_hp) * 0.25))):
				breakdown["kill"] = float(breakdown["kill"]) + 30.0
			breakdown["target"] = float(breakdown["target"]) + (1.0 - float(target_unit.hp) / float(max(1, target_unit.max_hp))) * 10.0
		elif heal_effect:
			var missing_hp: int = max(0, target_unit.max_hp - target_unit.hp)
			var actual_heal: int = mini(missing_hp, SkillSystem.estimate_heal(unit, skill_id))
			breakdown["support"] = float(breakdown["support"]) + float(actual_heal)
			if target_unit.character_id == unit.character_id:
				breakdown["survival"] = float(breakdown["survival"]) + float(actual_heal)

	var effects: Array = skill.get("effects", []) as Array
	for effect_value in effects:
		var effect: Dictionary = effect_value as Dictionary
		var effect_type: String = str(effect.get("type", ""))
		if effect_type == "apply_unit_status":
			for target_unit in affected_units:
				if target_unit == null:
					continue
				var status_id: String = str(effect.get("status_id", effect.get("id", "")))
				if not status_id.is_empty() and target_unit.has_status_effect(status_id):
					continue
				if target_unit.team != unit.team:
					breakdown["control"] = float(breakdown["control"]) + 8.0
				else:
					var defense_bonus: int = max(0, int(effect.get("defense_bonus", 0)))
					if target_unit.character_id == unit.character_id:
						var missing_hp_ratio: float = 1.0 - float(target_unit.hp) / float(max(1, target_unit.max_hp))
						breakdown["survival"] = float(breakdown["survival"]) + float(defense_bonus * 2) * missing_hp_ratio
					else:
						breakdown["support"] = float(breakdown["support"]) + float(2 + defense_bonus * 2)
		elif effect_type == "remove_unit_status":
			breakdown["support"] = float(breakdown["support"]) + 5.0

	if affected_units.size() > 1:
		breakdown["target"] = float(breakdown["target"]) + float(affected_units.size() - 1) * 4.0
	_score_element_surfaces(breakdown, element, affected_cells, battle_state)

	var ap_cost: int = max(0, int(skill.get("ap_cost", 0)))
	var mp_cost: int = max(0, int(skill.get("mp_cost", 0)))
	var cooldown: int = max(0, int(skill.get("cooldown", 0)))
	breakdown["resource"] = float(breakdown["resource"]) - float(ap_cost + mp_cost * 2 + cooldown)


static func _score_unit_reaction(
	breakdown: Dictionary,
	target_unit: BattleUnitState,
	element: String,
	intensity: int,
	battle_state: BattleState
) -> int:
	if element.is_empty():
		return 0
	var tile_state = battle_state.get_tile_state_at(target_unit.character.grid_position)
	var tile_state_id: String = tile_state.id if tile_state != null else ""
	var is_wet: bool = target_unit.has_status_effect("wet") or tile_state_id == "wet"
	var reaction_damage: int = 0
	match element:
		"lightning":
			if is_wet:
				reaction_damage = max(1, intensity * 2)
				breakdown["reaction"] = float(breakdown["reaction"]) + 15.0
				breakdown["control"] = float(breakdown["control"]) + 8.0
			else:
				breakdown["control"] = float(breakdown["control"]) + 4.0
		"ice":
			if is_wet:
				breakdown["reaction"] = float(breakdown["reaction"]) + 15.0
				breakdown["control"] = float(breakdown["control"]) + 12.0
			else:
				breakdown["control"] = float(breakdown["control"]) + 4.0
		"water":
			if target_unit.has_status_effect("burning") or tile_state_id == "burning":
				breakdown["reaction"] = float(breakdown["reaction"]) + 8.0
		"fire":
			if is_wet:
				breakdown["reaction"] = float(breakdown["reaction"]) + 4.0
			else:
				breakdown["control"] = float(breakdown["control"]) + 4.0
	return reaction_damage


static func _score_element_surfaces(
	breakdown: Dictionary,
	element: String,
	affected_cells: Array[Vector2i],
	battle_state: BattleState
) -> void:
	if element.is_empty():
		return
	for cell in affected_cells:
		var tile_state = battle_state.get_tile_state_at(cell)
		var state_id: String = tile_state.id if tile_state != null else ""
		match element:
			"fire":
				if state_id == "frozen":
					breakdown["reaction"] = float(breakdown["reaction"]) + 6.0
				elif state_id == "wet":
					breakdown["reaction"] = float(breakdown["reaction"]) + 4.0
				elif state_id == "burning":
					breakdown["tile"] = float(breakdown["tile"]) + 2.0
				else:
					breakdown["tile"] = float(breakdown["tile"]) + 3.0
			"water":
				if state_id == "burning":
					breakdown["reaction"] = float(breakdown["reaction"]) + 8.0
				else:
					breakdown["tile"] = float(breakdown["tile"]) + 2.0
			"ice":
				if state_id == "wet":
					breakdown["reaction"] = float(breakdown["reaction"]) + 12.0
				elif state_id == "burning":
					breakdown["reaction"] = float(breakdown["reaction"]) + 5.0
			"lightning":
				if state_id == "wet":
					breakdown["reaction"] = float(breakdown["reaction"]) + 12.0
				elif state_id == "electrified":
					breakdown["tile"] = float(breakdown["tile"]) + 5.0


static func _get_reachable_cells(unit: BattleUnitState, battle_state: BattleState) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var origin: Vector2i = unit.character.grid_position
	var best_cost_by_key: Dictionary = {battle_state.cell_key(origin): 0}
	var cell_by_key: Dictionary = {battle_state.cell_key(origin): origin}
	var queue: Array[Dictionary] = [{"cell": origin, "cost": 0}]

	while not queue.is_empty():
		queue.sort_custom(_compare_path_entries)
		var current: Dictionary = queue.pop_front() as Dictionary
		var current_cell: Vector2i = current.get("cell", origin) as Vector2i
		var current_cost: int = int(current.get("cost", 0))
		if current_cost != int(best_cost_by_key.get(battle_state.cell_key(current_cell), current_cost)):
			continue
		for direction in CARDINAL_DIRECTIONS:
			var next_cell: Vector2i = current_cell + direction
			if not battle_state.grid.in_bounds(next_cell) or not battle_state.grid.can_enter(next_cell):
				continue
			var next_cost: int = current_cost + battle_state.get_battle_cell_move_cost(unit, current_cell, next_cell)
			if next_cost > unit.action_points:
				continue
			var key: String = battle_state.cell_key(next_cell)
			if best_cost_by_key.has(key) and int(best_cost_by_key[key]) <= next_cost:
				continue
			best_cost_by_key[key] = next_cost
			cell_by_key[key] = next_cell
			queue.append({"cell": next_cell, "cost": next_cost})

	for key_value in best_cost_by_key.keys():
		var key: String = str(key_value)
		result.append({
			"cell": cell_by_key[key] as Vector2i,
			"cost": int(best_cost_by_key[key]),
		})
	result.sort_custom(_compare_reachable_cells)
	return result


static func _nearest_opponent_distance(unit: BattleUnitState, cell: Vector2i, battle_state: BattleState) -> int:
	var best_distance: int = 999
	for other_unit in battle_state.units:
		if other_unit == null or not other_unit.is_active() or other_unit.team == unit.team:
			continue
		best_distance = mini(best_distance, _manhattan(cell, other_unit.character.grid_position))
	return best_distance


static func _get_element_intensity(skill: Dictionary) -> int:
	for effect_value in skill.get("effects", []) as Array:
		var effect: Dictionary = effect_value as Dictionary
		if str(effect.get("type", "")) == "apply_element":
			return max(1, int(effect.get("intensity", 1)))
	return 1


static func _describe_candidate(candidate: Dictionary, unit: BattleUnitState) -> String:
	var action_type: String = str(candidate.get("action_type", "wait"))
	var move_cell: Vector2i = candidate.get("move_cell", unit.character.grid_position) as Vector2i
	var target_cell: Vector2i = candidate.get("target_cell", move_cell) as Vector2i
	var skill_id: String = str(candidate.get("skill_id", ""))
	var skill: Dictionary = SkillSystem.get_skill(skill_id)
	var skill_name: String = str(skill.get("display_name", skill_id))
	match action_type:
		"move":
			return "移动到 %s" % move_cell
		"skill":
			return "使用%s，目标 %s" % [skill_name, target_cell]
		"move_and_skill":
			return "移动到 %s 后使用%s，目标 %s" % [move_cell, skill_name, target_cell]
		_:
			return "等待"


static func _format_reasons(score_entries: Array[Dictionary]) -> Array[String]:
	var reasons: Array[String] = []
	for entry in score_entries:
		var weighted: float = float(entry.get("weighted", 0.0))
		reasons.append("%s%s %.1f" % [
			"+" if weighted >= 0.0 else "",
			str(entry.get("label", entry.get("id", ""))),
			weighted,
		])
	return reasons


static func _decision_candidate_summary(candidate: Dictionary) -> Dictionary:
	return {
		"action_type": str(candidate.get("action_type", "wait")),
		"description": str(candidate.get("description", "")),
		"move_cell": candidate.get("move_cell", Vector2i.ZERO),
		"move_cost": int(candidate.get("move_cost", 0)),
		"skill_id": str(candidate.get("skill_id", "")),
		"target_cell": candidate.get("target_cell", Vector2i.ZERO),
		"total_score": float(candidate.get("total_score", 0.0)),
		"reasons": (candidate.get("reasons", []) as Array).duplicate(),
	}


static func _compare_candidates(a: Dictionary, b: Dictionary) -> bool:
	var score_a: float = float(a.get("total_score", 0.0))
	var score_b: float = float(b.get("total_score", 0.0))
	if not is_equal_approx(score_a, score_b):
		return score_a > score_b
	var action_rank := {"skill": 0, "move_and_skill": 1, "move": 2, "wait": 3}
	var rank_a: int = int(action_rank.get(str(a.get("action_type", "wait")), 9))
	var rank_b: int = int(action_rank.get(str(b.get("action_type", "wait")), 9))
	if rank_a != rank_b:
		return rank_a < rank_b
	var skill_compare: int = str(a.get("skill_id", "")).naturalnocasecmp_to(str(b.get("skill_id", "")))
	if skill_compare != 0:
		return skill_compare < 0
	var cell_a: Vector2i = a.get("target_cell", Vector2i.ZERO) as Vector2i
	var cell_b: Vector2i = b.get("target_cell", Vector2i.ZERO) as Vector2i
	if cell_a.y != cell_b.y:
		return cell_a.y < cell_b.y
	return cell_a.x < cell_b.x


static func _compare_score_entries(a: Dictionary, b: Dictionary) -> bool:
	return absf(float(a.get("weighted", 0.0))) > absf(float(b.get("weighted", 0.0)))


static func _compare_path_entries(a: Dictionary, b: Dictionary) -> bool:
	return int(a.get("cost", 0)) < int(b.get("cost", 0))


static func _compare_reachable_cells(a: Dictionary, b: Dictionary) -> bool:
	var cost_a: int = int(a.get("cost", 0))
	var cost_b: int = int(b.get("cost", 0))
	if cost_a != cost_b:
		return cost_a < cost_b
	var cell_a: Vector2i = a.get("cell", Vector2i.ZERO) as Vector2i
	var cell_b: Vector2i = b.get("cell", Vector2i.ZERO) as Vector2i
	if cell_a.y != cell_b.y:
		return cell_a.y < cell_b.y
	return cell_a.x < cell_b.x


static func _manhattan(a: Vector2i, b: Vector2i) -> int:
	return abs(a.x - b.x) + abs(a.y - b.y)

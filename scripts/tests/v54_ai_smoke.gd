extends Node

const BattleAiPlannerScript := preload("res://scripts/systems/battle/battle_ai_planner.gd")


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures: Array[String] = []

	var move_case: Dictionary = _make_case(["basic_attack"], "aggressive", Vector2i(1, 1), Vector2i(3, 1))
	var move_decision: Dictionary = BattleAiPlannerScript.plan(move_case.enemy, move_case.state)
	var move_choice: Dictionary = move_decision.get("chosen", {}) as Dictionary
	if str(move_choice.get("action_type", "")) != "move_and_skill":
		failures.append("Expected move_and_skill, got %s" % str(move_choice.get("action_type", "")))

	var reaction_case: Dictionary = _make_case(
		["basic_attack", "debug_line_beam"],
		"controller",
		Vector2i(1, 1),
		Vector2i(3, 1)
	)
	reaction_case.player.add_status_effect({
		"status_id": "wet",
		"display_name": "Wet",
	})
	var reaction_decision: Dictionary = BattleAiPlannerScript.plan(reaction_case.enemy, reaction_case.state)
	var reaction_choice: Dictionary = reaction_decision.get("chosen", {}) as Dictionary
	if str(reaction_choice.get("skill_id", "")) != "debug_line_beam":
		failures.append("Expected debug_line_beam, got %s" % str(reaction_choice.get("skill_id", "")))
	if not _has_positive_score(reaction_choice, "reaction"):
		failures.append("Expected a positive reaction score")

	var kill_case: Dictionary = _make_case(["basic_attack"], "balanced", Vector2i(1, 1), Vector2i(2, 1))
	kill_case.player.hp = 1
	var kill_decision: Dictionary = BattleAiPlannerScript.plan(kill_case.enemy, kill_case.state)
	var kill_choice: Dictionary = kill_decision.get("chosen", {}) as Dictionary
	if str(kill_choice.get("action_type", "")) != "skill":
		failures.append("Expected immediate skill for a kill, got %s" % str(kill_choice.get("action_type", "")))
	if not _has_positive_score(kill_choice, "kill"):
		failures.append("Expected a positive kill score")

	var danger_case: Dictionary = _make_case(["basic_attack"], "defensive", Vector2i(1, 1), Vector2i(5, 1))
	var burning := BattleTileState.new()
	burning.id = "burning"
	burning.cell = danger_case.enemy.character.grid_position
	burning.intensity = 1
	burning.remaining_rounds = 2
	danger_case.state.apply_tile_state(burning)
	var danger_decision: Dictionary = BattleAiPlannerScript.plan(danger_case.enemy, danger_case.state)
	var danger_choice: Dictionary = danger_decision.get("chosen", {}) as Dictionary
	if str(danger_choice.get("action_type", "")) != "move":
		failures.append("Expected movement away from a burning tile, got %s" % str(danger_choice.get("action_type", "")))

	var support_case: Dictionary = _make_case(
		["basic_attack", "first_aid"],
		"support",
		Vector2i(1, 1),
		Vector2i(5, 1)
	)
	var ally_character: CharacterEntity = _make_character(
		support_case.holder,
		"ally",
		Vector2i(2, 1),
		["basic_attack"],
		"balanced",
		3,
		2
	)
	support_case.grid.register_character("ally", Vector2i(2, 1), ally_character, true)
	var ally_unit: BattleUnitState = BattleUnitState.from_character(ally_character, BattleUnitState.TEAM_ENEMY)
	ally_unit.hp = 1
	support_case.state.units.append(ally_unit)
	var support_decision: Dictionary = BattleAiPlannerScript.plan(support_case.enemy, support_case.state)
	var support_choice: Dictionary = support_decision.get("chosen", {}) as Dictionary
	if str(support_choice.get("skill_id", "")) != "first_aid":
		failures.append("Expected first_aid for an injured ally, got %s" % str(support_choice.get("skill_id", "")))
	if not _has_positive_score(support_choice, "support"):
		failures.append("Expected a positive support score")

	var virtual_path_case: Dictionary = _make_case(
		["quick_shot"],
		"balanced",
		Vector2i(2, 1),
		Vector2i(4, 1)
	)
	var virtual_path_failure: String = SkillSystem.get_skill_failure(
		virtual_path_case.enemy,
		"quick_shot",
		Vector2i(4, 1),
		virtual_path_case.state,
		Vector2i(1, 1)
	)
	if not virtual_path_failure.is_empty():
		failures.append("Virtual-origin path was blocked by the caster's old cell")

	if failures.is_empty():
		print("v54 AI smoke test passed")
		get_tree().quit(0)
		return

	for failure in failures:
		push_error(failure)
	get_tree().quit(1)


func _make_case(
	enemy_skills: Array[String],
	profile_id: String,
	enemy_cell: Vector2i,
	player_cell: Vector2i
) -> Dictionary:
	var holder := Node.new()
	add_child(holder)
	var grid: LocationGrid = LocationGrid.from_dictionary({
		"id": "v54_smoke",
		"display_name": "v54 smoke",
		"size": {"width": 7, "height": 3},
		"tile_size": 32,
		"tiles": [".......", ".......", "......."],
		"terrain": {
			".": {
				"walkable": true,
				"blocks_sight": false,
			},
		},
	})
	var enemy: CharacterEntity = _make_character(holder, "enemy", enemy_cell, enemy_skills, profile_id, 6, 6)
	var player: CharacterEntity = _make_character(holder, "player", player_cell, ["basic_attack"], "balanced", 4, 4)
	grid.register_character(enemy.character_id, enemy_cell, enemy, true)
	grid.register_character(player.character_id, player_cell, player, true)

	var enemy_unit: BattleUnitState = BattleUnitState.from_character(enemy, BattleUnitState.TEAM_ENEMY)
	var player_unit: BattleUnitState = BattleUnitState.from_character(player, BattleUnitState.TEAM_PLAYER)
	var units: Array[BattleUnitState] = [enemy_unit, player_unit]
	var state := BattleState.new()
	state.configure("v54_smoke", holder, grid, units)
	return {
		"state": state,
		"enemy": enemy_unit,
		"player": player_unit,
		"grid": grid,
		"holder": holder,
	}


func _make_character(
	holder: Node,
	character_id: String,
	cell: Vector2i,
	character_skills: Array[String],
	profile_id: String,
	strength: int,
	intellect: int
) -> CharacterEntity:
	var character := CharacterEntity.new()
	holder.add_child(character)
	character.configure({
		"id": character_id,
		"display_name": character_id,
		"character_kind": "enemy" if character_id == "enemy" else "player",
		"ai_profile": profile_id,
		"attributes": {
			"strength": strength,
			"intellect": intellect,
			"vitality": 4,
			"agility": 3,
			"action_points": 2,
			"max_mp": 12,
			"mp": 12,
		},
		"skills": character_skills,
		"blocks_movement": true,
	}, {
		"id": character_id,
		"grid_position": {"x": cell.x, "y": cell.y},
	}, holder)
	return character


func _has_positive_score(candidate: Dictionary, score_id: String) -> bool:
	for entry_value in candidate.get("score_breakdown", []) as Array:
		var entry: Dictionary = entry_value as Dictionary
		if str(entry.get("id", "")) == score_id:
			return float(entry.get("weighted", 0.0)) > 0.0
	return false

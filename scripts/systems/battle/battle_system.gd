extends Node

signal battle_started(battle_id: String)
signal battle_turn_started(character_id: String, round_number: int)
signal battle_ended(battle_id: String, result_status: String)
signal battle_state_changed()

const BattleEffectResolverScript := preload("res://scripts/systems/battle/battle_effect_resolver.gd")
const BattleAiPlannerScript := preload("res://scripts/systems/battle/battle_ai_planner.gd")
const MOVE_AP_COST := 1
const FLEE_AP_COST := 1
const TACTICAL_MODE_COMMAND := "command"
const TACTICAL_MODE_MOVE := "move"
const TACTICAL_MODE_SKILL := "skill"
const ENEMY_JOIN_RADIUS := 6
const MOVE_PRESENTATION_DELAY := 0.08
const SKILL_PRESENTATION_DELAY := 0.42
const WAIT_PRESENTATION_DELAY := 0.12
const ENEMY_FOLLOWUP_DELAY := 0.18
const ENEMY_UNIT_GAP_DELAY := 0.34

var active_state: BattleState
var last_result: ActionResult
var selected_skill_id: String = "basic_attack"
var tactical_mode: String = TACTICAL_MODE_MOVE
var reopen_skill_menu_requested: bool = false
var _battle_counter: int = 0
var _presentation_pending: bool = false
var _presentation_token: int = 0


func start_battle(location_root: Node, initiator: CharacterEntity, opponent: CharacterEntity) -> ActionResult:
	var initiator_id: String = initiator.character_id if initiator != null and is_instance_valid(initiator) else ""
	if active_state != null and active_state.active:
		return ActionResult.failed("BattleStart", initiator_id, "已经处于战斗中。")

	if location_root == null or not is_instance_valid(location_root) or not location_root.has_method("get_location_grid"):
		return ActionResult.failed("BattleStart", initiator_id, "战斗需要有效的场景。")
	if initiator == null or not is_instance_valid(initiator):
		return ActionResult.failed("BattleStart", "", "战斗需要发起者。")
	if opponent == null or not is_instance_valid(opponent):
		return ActionResult.failed("BattleStart", initiator.character_id, "战斗需要目标。")
	if PartySystem.is_member(opponent.character_id):
		return ActionResult.failed("BattleStart", initiator.character_id, "%s is already in the party." % opponent.display_name)
	if not opponent.is_combatable:
		return ActionResult.failed("BattleStart", initiator.character_id, "%s 不能被攻击。" % opponent.display_name)

	var grid: LocationGrid = location_root.get_location_grid() as LocationGrid
	if grid == null:
		return ActionResult.failed("BattleStart", initiator.character_id, "战斗需要有效的格子地图。")

	_battle_counter += 1
	var battle_id: String = "battle_%03d" % _battle_counter
	var player_characters: Array[CharacterEntity] = _collect_player_battle_members(location_root, initiator, grid)
	if player_characters.is_empty():
		return ActionResult.failed("BattleStart", initiator.character_id, "No party member on this map can enter battle.")

	var enemy_characters: Array[CharacterEntity] = _collect_enemy_battle_members(grid, opponent)
	if enemy_characters.is_empty():
		return ActionResult.failed("BattleStart", initiator.character_id, "No enemy on this map can enter battle.")

	var units: Array[BattleUnitState] = []
	for character in player_characters:
		units.append(BattleUnitState.from_character(character, BattleUnitState.TEAM_PLAYER))
	for character in enemy_characters:
		units.append(BattleUnitState.from_character(character, BattleUnitState.TEAM_ENEMY))
	active_state = BattleState.new()
	active_state.configure(battle_id, location_root, grid, units)
	selected_skill_id = "basic_attack"
	tactical_mode = TACTICAL_MODE_MOVE
	reopen_skill_menu_requested = false
	GameState.set_mode(GameState.GameMode.COMBAT)

	var result: ActionResult = ActionResult.succeeded("BattleStart", initiator.character_id, {
		"battle_id": battle_id,
		"opponent_id": opponent.character_id,
		"player_ids": _character_ids(player_characters),
		"enemy_ids": _character_ids(enemy_characters),
	})
	result.add_world_change({
		"type": "battle_started",
		"battle_id": battle_id,
		"location_id": grid.location_id,
		"participants": _participant_ids(),
	})
	result.add_world_change({
		"type": "relation_delta",
		"scope": "character",
		"source_id": opponent.character_id,
		"target_id": initiator.character_id,
		"delta": { "affinity": -10, "trust": -5, "hostility": 25 },
		"reason": "battle_started",
	})
	result.add_feedback("战斗开始：%d 名队伍成员对阵 %d 名敌人。" % [player_characters.size(), enemy_characters.size()])
	last_result = result
	ActionSystem.publish_result(result)
	battle_started.emit(battle_id)
	battle_state_changed.emit()
	_emit_turn_started()
	var first_unit: BattleUnitState = active_state.get_current_unit()
	if first_unit != null and first_unit.team == BattleUnitState.TEAM_ENEMY:
		_run_enemy_turn(first_unit)
	return result


func request_move_current_unit(direction: Vector2i) -> ActionResult:
	var unit: BattleUnitState = _get_player_current_unit()
	if unit == null:
		return _fail("BattleMove", "还没有轮到玩家行动。")
	if _presentation_pending:
		return _fail("BattleMove", "行动演出尚未结束。")
	if tactical_mode != TACTICAL_MODE_MOVE:
		return _fail("BattleMove", "请先选择移动。")
	if direction == Vector2i.ZERO:
		return _fail("BattleMove", "移动需要方向。")

	var character: CharacterEntity = unit.character
	var target_cell: Vector2i = character.grid_position + direction
	character.face_direction(direction)
	var move_cost: int = active_state.get_battle_cell_move_cost(unit, character.grid_position, target_cell) if active_state != null else MOVE_AP_COST
	return _move_unit_to(unit, target_cell, move_cost)


func request_move_current_unit_to(target_cell: Vector2i) -> ActionResult:
	var unit: BattleUnitState = _get_player_current_unit()
	if unit == null:
		return _fail("BattleMove", "还没有轮到玩家行动。")
	if _presentation_pending:
		return _fail("BattleMove", "行动演出尚未结束。")
	if tactical_mode != TACTICAL_MODE_MOVE:
		return _fail("BattleMove", "请先选择移动。")
	if active_state == null or active_state.grid == null:
		return _fail("BattleMove", "移动需要有效的格子地图。")

	var distances: Dictionary = _get_reachable_cell_distances(unit)
	var target_key: String = active_state.grid.cell_key(target_cell)
	if not distances.has(target_key):
		return _fail("BattleMove", "%s 本回合无法移动到 %s。" % [unit.display_name, target_cell])

	var move_cost: int = int(distances[target_key])
	if move_cost <= 0:
		return _fail("BattleMove", "%s 已经在这里。" % unit.display_name)

	unit.character.face_direction(_direction_toward(unit.character.grid_position, target_cell))
	return _move_unit_to(unit, target_cell, move_cost)


func request_attack_current_unit() -> ActionResult:
	var unit: BattleUnitState = _get_player_current_unit()
	if unit == null:
		return _fail("BattleAttack", "还没有轮到玩家行动。")

	return request_use_skill_current_unit("basic_attack", unit.character.get_facing_cell())


func request_attack_current_unit_at(target_cell: Vector2i) -> ActionResult:
	return request_use_skill_current_unit(selected_skill_id, target_cell)


func request_use_skill_current_unit(skill_id: String, target_cell: Vector2i) -> ActionResult:
	var unit: BattleUnitState = _get_player_current_unit()
	if unit == null:
		return _fail("UseSkillAction", "还没有轮到玩家行动。")
	if _presentation_pending:
		return _fail("UseSkillAction", "行动演出尚未结束。")

	var action: GameAction = ActionSystem.create_action("UseSkillAction", unit.character, {
		"skill_id": skill_id,
		"target_cell": target_cell,
	}, {
		"source": "battle",
	})
	return ActionSystem.submit(action)


func select_skill_for_current_unit(skill_id: String) -> bool:
	var unit: BattleUnitState = _get_player_current_unit()
	if unit == null:
		return false
	if _presentation_pending:
		return false
	if not unit.skills.has(skill_id):
		return false
	if SkillSystem.get_skill(skill_id).is_empty():
		return false

	selected_skill_id = skill_id
	tactical_mode = TACTICAL_MODE_SKILL
	reopen_skill_menu_requested = false
	battle_state_changed.emit()
	return true


func select_tactical_mode(mode: String) -> bool:
	if mode != TACTICAL_MODE_COMMAND and mode != TACTICAL_MODE_MOVE and mode != TACTICAL_MODE_SKILL:
		return false
	if _get_player_current_unit() == null:
		return false
	if _presentation_pending:
		return false

	tactical_mode = mode
	if mode == TACTICAL_MODE_SKILL:
		reopen_skill_menu_requested = false
	battle_state_changed.emit()
	return true


func cancel_skill_targeting_to_skill_menu() -> bool:
	if _get_player_current_unit() == null:
		return false
	if tactical_mode != TACTICAL_MODE_SKILL:
		return false

	tactical_mode = TACTICAL_MODE_MOVE
	reopen_skill_menu_requested = true
	battle_state_changed.emit()
	return true


func consume_reopen_skill_menu_requested() -> bool:
	var requested: bool = reopen_skill_menu_requested
	reopen_skill_menu_requested = false
	return requested


func get_tactical_mode() -> String:
	return tactical_mode


func is_move_mode() -> bool:
	return tactical_mode == TACTICAL_MODE_MOVE


func is_presentation_pending() -> bool:
	return _presentation_pending


func get_selected_skill_id() -> String:
	return selected_skill_id


func get_current_unit_skill_summaries() -> Array[Dictionary]:
	var unit: BattleUnitState = _get_player_current_unit()
	if unit == null or active_state == null:
		return []

	return SkillSystem.get_skill_summaries_for_unit(unit, active_state)


func get_selectable_player_turn_units() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if active_state == null or not active_state.active or _presentation_pending:
		return result

	var current_unit: BattleUnitState = active_state.get_current_unit()
	if current_unit == null or current_unit.team != BattleUnitState.TEAM_PLAYER:
		return result

	for unit in active_state.get_contiguous_units_from_current(BattleUnitState.TEAM_PLAYER):
		result.append(unit.get_summary())
	return result


func select_player_turn_unit(character_id: String) -> bool:
	if active_state == null or not active_state.active or _presentation_pending:
		return false
	var current_unit: BattleUnitState = active_state.get_current_unit()
	if current_unit == null or current_unit.team != BattleUnitState.TEAM_PLAYER:
		return false

	var selectable_units: Array[BattleUnitState] = active_state.get_contiguous_units_from_current(BattleUnitState.TEAM_PLAYER)
	var can_select: bool = false
	for unit in selectable_units:
		if unit.character_id == character_id:
			can_select = true
			break
	if not can_select:
		return false
	if not active_state.promote_contiguous_unit_to_current(character_id, BattleUnitState.TEAM_PLAYER):
		return false

	selected_skill_id = "basic_attack"
	tactical_mode = TACTICAL_MODE_MOVE
	reopen_skill_menu_requested = false
	_emit_turn_started()
	battle_state_changed.emit()
	return true


func get_skill_failure_for_actor(actor: CharacterEntity, skill_id: String, target_cell: Vector2i) -> String:
	var unit: BattleUnitState = _get_player_current_unit()
	if unit == null:
		return "还没有轮到玩家行动。"
	if _presentation_pending:
		return "行动演出尚未结束。"
	if actor == null or not is_instance_valid(actor) or actor.character_id != unit.character_id:
		return "只有当前行动单位可以使用技能。"

	return SkillSystem.get_skill_failure(unit, skill_id, target_cell, active_state)


func execute_skill_for_actor(actor: CharacterEntity, skill_id: String, target_cell: Vector2i) -> ActionResult:
	var failed_requirement: String = get_skill_failure_for_actor(actor, skill_id, target_cell)
	if not failed_requirement.is_empty():
		var actor_id: String = ""
		if actor != null and is_instance_valid(actor):
			actor_id = actor.character_id
		return ActionResult.failed("UseSkillAction", actor_id, failed_requirement, {
			"skill_id": skill_id,
			"target_cell": target_cell,
		})

	var unit: BattleUnitState = _get_player_current_unit()
	return _execute_skill_for_unit(unit, skill_id, target_cell)


func get_player_tactical_preview() -> Dictionary:
	var unit: BattleUnitState = _get_player_current_unit()
	if unit == null:
		return {
			"active": is_active(),
			"can_control": false,
			"move_cells": [],
			"attack_cells": [],
			"current_cell": Vector2i.ZERO,
			"tactical_mode": tactical_mode,
			"tile_states": active_state.get_tile_state_summaries() if active_state != null else [],
		}

	var move_cells: Array[Vector2i] = []
	var attack_cells: Array[Vector2i] = []
	if tactical_mode == TACTICAL_MODE_MOVE:
		move_cells = get_reachable_cells_for_current_unit()
	elif tactical_mode == TACTICAL_MODE_SKILL:
		attack_cells = get_range_cells_for_current_skill()

	return {
		"active": true,
		"can_control": true,
		"move_cells": move_cells,
		"attack_cells": attack_cells,
		"current_cell": unit.character.grid_position,
		"selected_skill_id": selected_skill_id,
		"tactical_mode": tactical_mode,
		"tile_states": active_state.get_tile_state_summaries(),
	}


func get_reachable_cells_for_current_unit() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var unit: BattleUnitState = _get_player_current_unit()
	if unit == null or active_state == null or active_state.grid == null:
		return result

	var distances: Dictionary = _get_reachable_cell_distances(unit)
	for key_value in distances.keys():
		var distance: int = int(distances[key_value])
		if distance <= 0:
			continue
		result.append(_cell_from_key(str(key_value)))

	return result


func get_attackable_cells_for_current_unit() -> Array[Vector2i]:
	return get_range_cells_for_current_skill()


func get_range_cells_for_current_skill() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var unit: BattleUnitState = _get_player_current_unit()
	if unit == null or active_state == null:
		return result

	return SkillSystem.get_range_cells(unit, selected_skill_id, active_state)


func get_target_cells_for_current_skill() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var unit: BattleUnitState = _get_player_current_unit()
	if unit == null or active_state == null:
		return result

	return SkillSystem.get_target_cells(unit, selected_skill_id, active_state)


func get_area_cells_for_current_skill(target_cell: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var unit: BattleUnitState = _get_player_current_unit()
	if unit == null or active_state == null:
		return result

	var failed_requirement: String = SkillSystem.get_skill_failure(unit, selected_skill_id, target_cell, active_state)
	if not failed_requirement.is_empty():
		return result

	return SkillSystem.get_area_cells(selected_skill_id, target_cell, active_state, unit.character.grid_position)


func is_player_turn() -> bool:
	return _get_player_current_unit() != null


func wait_current_unit() -> ActionResult:
	var unit: BattleUnitState = _get_current_active_unit()
	if unit == null:
		return _fail("BattleWait", "没有可以等待的行动单位。")
	if _presentation_pending:
		return _fail("BattleWait", "行动演出尚未结束。")

	unit.action_points = 0
	var result: ActionResult = ActionResult.succeeded("BattleWait", unit.character_id, {
		"battle_id": active_state.battle_id,
	})
	result.add_world_change({
		"type": "battle_unit_waited",
		"battle_id": active_state.battle_id,
		"character_id": unit.character_id,
	})
	result.add_feedback("%s 选择等待。" % unit.display_name)
	if unit.team == BattleUnitState.TEAM_PLAYER:
		tactical_mode = TACTICAL_MODE_MOVE
		reopen_skill_menu_requested = false
	_publish_result(result)
	_schedule_after_unit_action(unit, true, WAIT_PRESENTATION_DELAY)
	return result


func flee_current_unit() -> ActionResult:
	var unit: BattleUnitState = _get_player_current_unit()
	if unit == null:
		return _fail("BattleFlee", "只有当前玩家单位可以逃跑。")
	if _presentation_pending:
		return _fail("BattleFlee", "行动演出尚未结束。")
	if unit.action_points < FLEE_AP_COST:
		return _fail("BattleFlee", "%s 没有足够行动点逃跑。" % unit.display_name)

	unit.spend_action_points(FLEE_AP_COST)
	unit.fled = true
	var result: ActionResult = ActionResult.succeeded("BattleFlee", unit.character_id, {
		"battle_id": active_state.battle_id,
	})
	result.add_world_change({
		"type": "battle_unit_fled",
		"battle_id": active_state.battle_id,
		"character_id": unit.character_id,
	})
	result.add_feedback("%s 逃离了战斗。" % unit.display_name)
	tactical_mode = TACTICAL_MODE_MOVE
	reopen_skill_menu_requested = false
	_publish_result(result)
	_end_battle("fled")
	return result


func get_summary() -> Dictionary:
	if active_state == null:
		return {}

	var summary: Dictionary = active_state.get_summary()
	summary["selectable_player_units"] = get_selectable_player_turn_units()
	summary["presentation_pending"] = _presentation_pending
	return summary


func is_active() -> bool:
	return active_state != null and active_state.active


func clear_battle_state() -> void:
	_presentation_pending = false
	_presentation_token += 1
	active_state = null
	battle_state_changed.emit()


func _move_unit_to(unit: BattleUnitState, target_cell: Vector2i, move_cost: int) -> ActionResult:
	var character: CharacterEntity = unit.character
	if unit.action_points < MOVE_AP_COST:
		return _fail("BattleMove", "%s 没有足够行动点移动。" % unit.display_name)
	if active_state.grid == null or not active_state.grid.can_enter(target_cell):
		return _publish_simple_result("BattleMove", unit.character_id, {
			"type": "battle_unit_faced_blocked_cell",
			"battle_id": active_state.battle_id,
			"character_id": unit.character_id,
			"target": target_cell,
			"facing": character.facing,
		}, "%s 转向了%s，但无法移动。" % [unit.display_name, _translate_facing(character.facing)])

	var from_cell: Vector2i = character.grid_position
	if from_cell == target_cell:
		return _fail("BattleMove", "%s 已经在这里。" % unit.display_name)

	var final_cost: int = max(MOVE_AP_COST, move_cost)
	if unit.action_points < final_cost:
		return _fail("BattleMove", "%s 没有足够行动点完成这次移动。" % unit.display_name)
	if not active_state.grid.move_character(unit.character_id, from_cell, target_cell, character.blocks_movement):
		return _fail("BattleMove", "移动失败：格子占用更新失败。")

	unit.spend_action_points(final_cost)
	character.set_grid_position(target_cell)
	var result: ActionResult = ActionResult.succeeded("BattleMove", unit.character_id, {
		"battle_id": active_state.battle_id,
		"target_cell": target_cell,
	})
	result.add_world_change({
		"type": "battle_unit_moved",
		"battle_id": active_state.battle_id,
		"character_id": unit.character_id,
		"from": from_cell,
		"to": target_cell,
		"cost": final_cost,
		"remaining_ap": unit.action_points,
	})
	active_state.on_unit_enters_cell(unit, target_cell, result)
	result.add_feedback("%s 移动到 %s。" % [unit.display_name, target_cell])
	if unit.team == BattleUnitState.TEAM_PLAYER:
		tactical_mode = TACTICAL_MODE_MOVE
		reopen_skill_menu_requested = false
	_publish_result(result)
	var presentation_delay: float = MOVE_PRESENTATION_DELAY if unit.team == BattleUnitState.TEAM_PLAYER else ENEMY_FOLLOWUP_DELAY
	_schedule_after_unit_action(unit, false, presentation_delay)
	return result


func _attack_facing_target(unit: BattleUnitState) -> ActionResult:
	var attacker: CharacterEntity = unit.character
	var target_cell: Vector2i = attacker.get_facing_cell()
	return _execute_skill_for_unit(unit, "basic_attack", target_cell)


func _execute_skill_for_unit(unit: BattleUnitState, skill_id: String, target_cell: Vector2i) -> ActionResult:
	var skill: Dictionary = SkillSystem.get_skill(skill_id)
	var failed_requirement: String = SkillSystem.get_skill_failure(unit, skill_id, target_cell, active_state)
	if not failed_requirement.is_empty():
		return _fail("UseSkillAction", failed_requirement)

	var ap_cost: int = max(0, int(skill.get("ap_cost", 0)))
	var mp_cost: int = max(0, int(skill.get("mp_cost", 0)))
	unit.spend_action_points(ap_cost)
	unit.spend_magic_points(mp_cost)
	var cooldown: int = max(0, int(skill.get("cooldown", 0)))
	if cooldown > 0:
		unit.set_skill_cooldown(skill_id, cooldown)
	if target_cell != unit.character.grid_position:
		unit.character.face_direction(_direction_toward(unit.character.grid_position, target_cell))

	var affected_units: Array[BattleUnitState] = SkillSystem.get_affected_units(unit, skill_id, target_cell, active_state)
	var target_name: String = _get_skill_target_name(unit, affected_units, target_cell)
	var pre_hit_tile_states: Dictionary = {}
	for affected_unit in affected_units:
		if affected_unit == null or affected_unit.character == null:
			continue
		var affected_tile_state = active_state.get_tile_state_at(affected_unit.character.grid_position)
		pre_hit_tile_states[affected_unit.character_id] = affected_tile_state.id if affected_tile_state != null else ""

	var result: ActionResult = ActionResult.succeeded("UseSkillAction", unit.character_id, {
		"battle_id": active_state.battle_id,
		"skill_id": skill_id,
		"target_cell": target_cell,
		"target_id": str(affected_units[0].character_id) if not affected_units.is_empty() else unit.character_id,
		"ap_cost": ap_cost,
		"mp_cost": mp_cost,
	})
	result.add_world_change({
		"type": "battle_skill_used",
		"battle_id": active_state.battle_id,
		"character_id": unit.character_id,
		"skill_id": skill_id,
		"target_cell": target_cell,
		"ap_cost": ap_cost,
		"mp_cost": mp_cost,
		"remaining_ap": unit.action_points,
		"remaining_mp": unit.magic_points,
	})

	var effect_context: Dictionary = {
		"battle_state": active_state,
		"caster": unit,
		"skill": skill,
		"skill_id": skill_id,
		"target_cell": target_cell,
		"affected_units": affected_units,
		"affected_cells": SkillSystem.get_area_cells(skill_id, target_cell, active_state, unit.character.grid_position),
	}
	BattleEffectResolverScript.resolve_skill_effects(effect_context, result)
	for affected_unit in affected_units:
		if affected_unit == null:
			continue
		active_state.on_unit_hit_by_skill(
			affected_unit,
			unit,
			skill,
			str(pre_hit_tile_states.get(affected_unit.character_id, "")),
			result
		)

	var feedback_template: String = str(skill.get("feedback", ""))
	if feedback_template.is_empty():
		feedback_template = "%s used %s." % [unit.display_name, str(skill.get("display_name", skill_id))]
		result.add_feedback(feedback_template)
	else:
		result.add_feedback(SkillSystem.format_feedback(feedback_template, unit.display_name, target_name))

	if unit.team == BattleUnitState.TEAM_PLAYER:
		tactical_mode = TACTICAL_MODE_MOVE
		reopen_skill_menu_requested = false
	_publish_result(result)
	_schedule_after_unit_action(unit, unit.team == BattleUnitState.TEAM_ENEMY or bool(skill.get("ends_turn", false)), SKILL_PRESENTATION_DELAY)
	return result


func _get_skill_target_name(unit: BattleUnitState, affected_units: Array[BattleUnitState], target_cell: Vector2i) -> String:
	if affected_units.is_empty():
		return "empty cell %s" % target_cell
	if affected_units.size() == 1:
		return affected_units[0].display_name

	return "%d targets" % affected_units.size()


func _after_unit_action(unit: BattleUnitState, force_end_turn: bool) -> void:
	if active_state == null or not active_state.active:
		return

	if not active_state.has_active_team(BattleUnitState.TEAM_ENEMY):
		_end_battle("won")
		return
	if not active_state.has_active_team(BattleUnitState.TEAM_PLAYER):
		_end_battle("lost")
		return

	if not force_end_turn and unit.is_active() and unit.action_points > 0:
		return

	var turn_end_result: ActionResult = ActionResult.succeeded("BattleTurnEnd", unit.character_id, {
		"battle_id": active_state.battle_id,
		"round": active_state.round_number,
	})
	turn_end_result.add_world_change({
		"type": "battle_turn_ended",
		"battle_id": active_state.battle_id,
		"character_id": unit.character_id,
		"round": active_state.round_number,
	})
	active_state.on_unit_ends_turn_on_cell(unit, turn_end_result)
	_publish_result(turn_end_result)

	if not active_state.has_active_team(BattleUnitState.TEAM_ENEMY):
		_end_battle("won")
		return
	if not active_state.has_active_team(BattleUnitState.TEAM_PLAYER):
		_end_battle("lost")
		return

	_advance_turn_or_finish()


func _schedule_after_unit_action(unit: BattleUnitState, force_end_turn: bool, delay: float = SKILL_PRESENTATION_DELAY) -> void:
	if active_state == null or not active_state.active:
		return

	_presentation_token += 1
	var token: int = _presentation_token
	_presentation_pending = true
	battle_state_changed.emit()

	var tree: SceneTree = get_tree()
	if tree == null:
		_finish_scheduled_after_unit_action(token, unit, force_end_turn)
		return

	await tree.create_timer(maxf(0.0, delay)).timeout
	_finish_scheduled_after_unit_action(token, unit, force_end_turn)


func _finish_scheduled_after_unit_action(token: int, unit: BattleUnitState, force_end_turn: bool) -> void:
	if token != _presentation_token:
		return
	_presentation_pending = false
	if active_state == null or not active_state.active:
		battle_state_changed.emit()
		return

	_after_unit_action(unit, force_end_turn)
	battle_state_changed.emit()


func _advance_turn_or_finish() -> void:
	if active_state == null or not active_state.active:
		return

	var completed_round: int = active_state.round_number
	var current_unit: BattleUnitState = active_state.get_current_unit()
	var round_end_result: ActionResult = ActionResult.succeeded(
		"BattleRoundEnd",
		current_unit.character_id if current_unit != null else "",
		{
			"battle_id": active_state.battle_id,
			"round": completed_round,
		}
	)
	round_end_result.add_world_change({
		"type": "battle_round_ended",
		"battle_id": active_state.battle_id,
		"round": completed_round,
	})
	var next_unit: BattleUnitState = active_state.advance_turn(round_end_result)
	if next_unit == null:
		_end_battle("ended")
		return

	if active_state.round_number > completed_round:
		round_end_result.add_feedback("第 %d 回合结束。" % completed_round)
		_publish_result(round_end_result)

	_emit_turn_started()
	if not active_state.has_active_team(BattleUnitState.TEAM_ENEMY):
		_end_battle("won")
		return
	if not active_state.has_active_team(BattleUnitState.TEAM_PLAYER):
		_end_battle("lost")
		return
	if not next_unit.is_active():
		_advance_turn_or_finish()
		return
	if next_unit.team == BattleUnitState.TEAM_ENEMY:
		await _delay_enemy_unit_start()
		_run_enemy_turn(next_unit)


func _run_enemy_turn(unit: BattleUnitState) -> void:
	if active_state == null or not active_state.active or not unit.is_active():
		return

	if active_state.get_active_units_for_team(BattleUnitState.TEAM_PLAYER).is_empty():
		_end_battle("lost")
		return

	var decision: Dictionary = BattleAiPlannerScript.plan(unit, active_state)
	if decision.is_empty():
		wait_current_unit()
		return

	var decision_result: ActionResult = ActionResult.succeeded("BattleAiDecision", unit.character_id, {
		"battle_id": active_state.battle_id,
		"profile_id": str(decision.get("profile_id", "balanced")),
		"candidate_count": int(decision.get("candidate_count", 0)),
	})
	active_state.record_ai_decision(decision, decision_result)
	_publish_result(decision_result)

	var chosen: Dictionary = decision.get("chosen", {}) as Dictionary
	var action_type: String = str(chosen.get("action_type", "wait"))
	if action_type == "wait":
		wait_current_unit()
		return

	if action_type == "move" or action_type == "move_and_skill":
		var move_cell: Vector2i = chosen.get("move_cell", unit.character.grid_position) as Vector2i
		var move_cost: int = int(chosen.get("move_cost", 0))
		if not _execute_enemy_planned_move(unit, move_cell, move_cost):
			if active_state != null and active_state.active and unit.is_active():
				wait_current_unit()
			return
		await _delay_enemy_followup()
		if active_state == null or not active_state.active or not unit.is_active():
			return
		if action_type == "move":
			wait_current_unit()
			return

	var skill_id: String = str(chosen.get("skill_id", ""))
	var target_cell: Vector2i = chosen.get("target_cell", unit.character.grid_position) as Vector2i
	var skill_result: ActionResult = _execute_skill_for_unit(unit, skill_id, target_cell)
	if not skill_result.success and active_state != null and active_state.active and unit.is_active():
		wait_current_unit()


func _execute_enemy_planned_move(unit: BattleUnitState, target_cell: Vector2i, planned_cost: int) -> bool:
	if active_state == null or not active_state.active or active_state.grid == null:
		return false
	if unit == null or not unit.is_active():
		return false

	var from_cell: Vector2i = unit.character.grid_position
	if from_cell == target_cell:
		return true
	if not active_state.grid.can_enter(target_cell):
		return false

	var move_cost: int = max(1, planned_cost)
	if move_cost > unit.action_points:
		return false
	if not active_state.grid.move_character(unit.character_id, from_cell, target_cell, unit.character.blocks_movement):
		return false

	unit.spend_action_points(move_cost)
	unit.character.face_direction(_direction_toward(from_cell, target_cell))
	unit.character.set_grid_position(target_cell)
	var result: ActionResult = ActionResult.succeeded("BattleMove", unit.character_id, {
		"battle_id": active_state.battle_id,
		"ai": true,
	})
	result.add_world_change({
		"type": "battle_unit_moved",
		"battle_id": active_state.battle_id,
		"character_id": unit.character_id,
		"from": from_cell,
		"to": target_cell,
		"cost": move_cost,
		"remaining_ap": unit.action_points,
		"planned": true,
	})
	active_state.on_unit_enters_cell(unit, target_cell, result)
	result.add_feedback("%s 移动到 %s。" % [unit.display_name, target_cell])
	_publish_result(result)
	if not unit.is_active():
		_schedule_after_unit_action(unit, true, ENEMY_FOLLOWUP_DELAY)
		return false
	return true


func _delay_enemy_followup(delay: float = ENEMY_FOLLOWUP_DELAY) -> void:
	await _run_presentation_gap(delay)


func _delay_enemy_unit_start(delay: float = ENEMY_UNIT_GAP_DELAY) -> void:
	await _run_presentation_gap(delay)


func _run_presentation_gap(delay: float) -> void:
	_presentation_token += 1
	var token: int = _presentation_token
	_presentation_pending = true
	battle_state_changed.emit()
	var tree: SceneTree = get_tree()
	if tree != null:
		await tree.create_timer(maxf(0.0, delay)).timeout
	if token != _presentation_token:
		return
	_presentation_pending = false
	battle_state_changed.emit()


func _collect_player_battle_members(location_root: Node, initiator: CharacterEntity, grid: LocationGrid) -> Array[CharacterEntity]:
	var members: Array[CharacterEntity] = PartySystem.get_battle_members(location_root, initiator)
	if not members.is_empty():
		return members
	if initiator == null or not is_instance_valid(initiator):
		return members
	var live_initiator: CharacterEntity = grid.get_character_by_id(initiator.character_id)
	if live_initiator != null:
		members.append(live_initiator)
	return members


func _collect_enemy_battle_members(grid: LocationGrid, opponent: CharacterEntity) -> Array[CharacterEntity]:
	var enemies: Array[CharacterEntity] = []
	if grid == null or opponent == null or not is_instance_valid(opponent):
		return enemies

	enemies.append(opponent)
	var candidates: Array[Dictionary] = []
	for character_value in grid.characters_by_id.values():
		if typeof(character_value) != TYPE_OBJECT or not is_instance_valid(character_value):
			continue
		var character: CharacterEntity = character_value as CharacterEntity
		if character == null or character.character_id == opponent.character_id:
			continue
		if not character.is_combatable or character.is_defeated:
			continue
		if PartySystem.is_member(character.character_id):
			continue
		if character.character_kind != CharacterEntity.KIND_ENEMY:
			continue

		var distance: int = _manhattan(opponent.grid_position, character.grid_position)
		if distance > ENEMY_JOIN_RADIUS:
			continue
		candidates.append({
			"character": character,
			"distance": distance,
		})

	candidates.sort_custom(Callable(self, "_compare_enemy_candidate"))
	for candidate in candidates:
		enemies.append(candidate.get("character") as CharacterEntity)
	return enemies


func _compare_enemy_candidate(a: Dictionary, b: Dictionary) -> bool:
	var a_distance: int = int(a.get("distance", 0))
	var b_distance: int = int(b.get("distance", 0))
	if a_distance == b_distance:
		var a_character: CharacterEntity = a.get("character") as CharacterEntity
		var b_character: CharacterEntity = b.get("character") as CharacterEntity
		var a_id: String = a_character.character_id if a_character != null else ""
		var b_id: String = b_character.character_id if b_character != null else ""
		return a_id < b_id
	return a_distance < b_distance


func _end_battle(status: String) -> void:
	if active_state == null or not active_state.active:
		return

	_presentation_pending = false
	_presentation_token += 1
	tactical_mode = TACTICAL_MODE_MOVE
	reopen_skill_menu_requested = false
	active_state.active = false
	active_state.result_status = status
	var result: ActionResult = ActionResult.succeeded("BattleEnd", "", {
		"battle_id": active_state.battle_id,
		"status": status,
	})
	result.add_world_change({
		"type": "battle_ended",
		"battle_id": active_state.battle_id,
		"status": status,
		"participants": _participant_ids(),
	})

	for unit in active_state.units:
		if unit.defeated and unit.character != null and unit.team == BattleUnitState.TEAM_ENEMY:
			unit.character.is_combatable = false
			unit.character.is_interactable = false
			if active_state.location_root != null and is_instance_valid(active_state.location_root) and active_state.location_root.has_method("mark_character_defeated"):
				active_state.location_root.mark_character_defeated(unit.character_id)
			result.add_world_change({
				"type": "world_character_defeated",
				"battle_id": active_state.battle_id,
				"character_id": unit.character_id,
				"location_id": active_state.grid.location_id,
			})
		elif unit.defeated and unit.team == BattleUnitState.TEAM_PLAYER:
			if unit.character_id == GameState.player_id:
				GameState.set_flag("player_defeated", true)
			result.add_world_change({
				"type": "party_unit_defeated",
				"battle_id": active_state.battle_id,
				"character_id": unit.character_id,
			})

	result.add_feedback("战斗结束：%s。" % _translate_battle_status(status))
	_publish_result(result)
	GameState.set_mode(GameState.GameMode.EXPLORATION)
	battle_ended.emit(active_state.battle_id, status)
	battle_state_changed.emit()


func _get_player_current_unit() -> BattleUnitState:
	var unit: BattleUnitState = _get_current_active_unit()
	if unit == null or unit.team != BattleUnitState.TEAM_PLAYER:
		return null

	return unit


func _get_current_active_unit() -> BattleUnitState:
	if active_state == null or not active_state.active:
		return null

	var unit: BattleUnitState = active_state.get_current_unit()
	if unit == null or not unit.is_active():
		return null

	return unit


func _get_nearest_active_player_unit(enemy_unit: BattleUnitState) -> BattleUnitState:
	var player_units: Array[BattleUnitState] = active_state.get_active_units_for_team(BattleUnitState.TEAM_PLAYER)
	if player_units.is_empty():
		return null

	if enemy_unit == null or not enemy_unit.is_active():
		return player_units[0]

	var best_unit: BattleUnitState = player_units[0]
	var best_distance: int = _manhattan(enemy_unit.character.grid_position, best_unit.character.grid_position)
	for player_unit in player_units:
		var distance: int = _manhattan(enemy_unit.character.grid_position, player_unit.character.grid_position)
		if distance < best_distance:
			best_distance = distance
			best_unit = player_unit

	return best_unit


func _direction_toward(from_cell: Vector2i, to_cell: Vector2i) -> Vector2i:
	var delta: Vector2i = to_cell - from_cell
	if abs(delta.x) >= abs(delta.y):
		return Vector2i.RIGHT if delta.x > 0 else Vector2i.LEFT

	return Vector2i.DOWN if delta.y > 0 else Vector2i.UP


func _translate_facing(facing: String) -> String:
	match facing:
		"up":
			return "上方"
		"down":
			return "下方"
		"left":
			return "左侧"
		"right":
			return "右侧"
		_:
			return facing


func _translate_battle_status(status: String) -> String:
	match status:
		"won":
			return "胜利"
		"lost":
			return "失败"
		"fled":
			return "逃跑"
		"ended":
			return "结束"
		_:
			return status


func _manhattan(a: Vector2i, b: Vector2i) -> int:
	return abs(a.x - b.x) + abs(a.y - b.y)


func _get_reachable_cell_distances(unit: BattleUnitState) -> Dictionary:
	var distances: Dictionary = {}
	if unit == null or not unit.is_active() or active_state == null or active_state.grid == null:
		return distances

	var start_cell: Vector2i = unit.character.grid_position
	var start_key: String = active_state.grid.cell_key(start_cell)
	distances[start_key] = 0
	var frontier: Array[Dictionary] = [{ "cell": start_cell, "cost": 0 }]
	var directions: Array[Vector2i] = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]

	while not frontier.is_empty():
		frontier.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.get("cost", 0)) < int(b.get("cost", 0)))
		var entry: Dictionary = frontier.pop_front() as Dictionary
		var current_cell: Vector2i = entry.get("cell", start_cell) as Vector2i
		var current_distance: int = int(entry.get("cost", 0))
		var current_key: String = active_state.grid.cell_key(current_cell)
		if current_distance != int(distances.get(current_key, current_distance)):
			continue
		if current_distance >= unit.action_points:
			continue

		for direction in directions:
			var next_cell: Vector2i = current_cell + direction
			var next_key: String = active_state.grid.cell_key(next_cell)
			if not active_state.grid.can_enter(next_cell):
				continue

			var step_cost: int = active_state.get_battle_cell_move_cost(unit, current_cell, next_cell)
			var next_distance: int = current_distance + step_cost
			if next_distance > unit.action_points:
				continue
			if distances.has(next_key) and int(distances[next_key]) <= next_distance:
				continue
			distances[next_key] = next_distance
			frontier.append({ "cell": next_cell, "cost": next_distance })

	return distances


func _cell_from_key(key: String) -> Vector2i:
	var parts: PackedStringArray = key.split(",")
	if parts.size() != 2:
		return Vector2i.ZERO

	return Vector2i(int(parts[0]), int(parts[1]))


func _participant_ids() -> Array[String]:
	var ids: Array[String] = []
	if active_state == null:
		return ids

	for unit in active_state.units:
		ids.append(unit.character_id)

	return ids


func _character_ids(characters: Array[CharacterEntity]) -> Array[String]:
	var ids: Array[String] = []
	for character in characters:
		if character == null or not is_instance_valid(character):
			continue
		ids.append(character.character_id)
	return ids


func _emit_turn_started() -> void:
	var unit: BattleUnitState = active_state.get_current_unit() if active_state != null else null
	if unit == null:
		return
	if unit.team == BattleUnitState.TEAM_PLAYER:
		_select_default_skill_for_unit(unit)
		tactical_mode = TACTICAL_MODE_MOVE
		reopen_skill_menu_requested = false

	var result: ActionResult = ActionResult.succeeded("BattleTurnStart", unit.character_id, {
		"battle_id": active_state.battle_id,
		"round": active_state.round_number,
	})
	result.add_world_change({
		"type": "battle_turn_started",
		"battle_id": active_state.battle_id,
		"character_id": unit.character_id,
		"round": active_state.round_number,
		"action_points": unit.action_points,
	})
	active_state.on_unit_starts_turn_on_cell(unit, result)
	result.add_feedback("轮到 %s 行动。" % unit.display_name)
	_publish_result(result)
	battle_turn_started.emit(unit.character_id, active_state.round_number)


func _select_default_skill_for_unit(unit: BattleUnitState) -> void:
	if unit.skills.has(selected_skill_id) and not SkillSystem.get_skill(selected_skill_id).is_empty():
		return
	if unit.skills.has("basic_attack"):
		selected_skill_id = "basic_attack"
		return
	if not unit.skills.is_empty():
		selected_skill_id = str(unit.skills[0])


func _publish_simple_result(action_type: String, actor_id: String, change: Dictionary, feedback: String) -> ActionResult:
	var result: ActionResult = ActionResult.succeeded(action_type, actor_id, {
		"battle_id": active_state.battle_id if active_state != null else "",
	})
	result.add_world_change(change)
	result.add_feedback(feedback)
	return _publish_result(result)


func _publish_result(result: ActionResult) -> ActionResult:
	last_result = result
	result.already_published = true
	ActionSystem.publish_result(result)
	battle_state_changed.emit()
	return result


func _fail(action_type: String, reason: String) -> ActionResult:
	var actor_id: String = ""
	var unit: BattleUnitState = _get_current_active_unit()
	if unit != null:
		actor_id = unit.character_id
	var result: ActionResult = ActionResult.failed(action_type, actor_id, reason)
	last_result = result
	ActionSystem.publish_result(result)
	return result

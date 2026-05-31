class_name UseSkillAction
extends GameAction


func _init() -> void:
	action_type = "UseSkillAction"


func check() -> ActionResult:
	var base_result: ActionResult = super.check()
	if not base_result.success:
		return base_result

	var skill_id: String = str(target.get("skill_id", ""))
	if skill_id.is_empty():
		return _failure("使用技能需要 skill_id。")

	var target_cell: Vector2i = target.get("target_cell", actor.grid_position) as Vector2i
	var failed_requirement: String = BattleSystem.get_skill_failure_for_actor(actor, skill_id, target_cell)
	if not failed_requirement.is_empty():
		return _failure(failed_requirement)

	return _success()


func execute() -> ActionResult:
	var check_result: ActionResult = check()
	if not check_result.success:
		return check_result

	return BattleSystem.execute_skill_for_actor(
		actor,
		str(target.get("skill_id", "")),
		target.get("target_cell", actor.grid_position) as Vector2i
	)

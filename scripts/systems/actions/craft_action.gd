class_name CraftAction
extends GameAction


func _init() -> void:
	action_type = "CraftAction"


func check() -> ActionResult:
	var base_result: ActionResult = super.check()
	if not base_result.success:
		return base_result

	var recipe_id: String = str(target.get("recipe_id", ""))
	if recipe_id.is_empty():
		return _failure("CraftAction requires a recipe_id.")

	var failed_requirement: String = CraftSystem.get_failed_requirement(actor, recipe_id)
	if not failed_requirement.is_empty():
		return _failure(failed_requirement)

	return _success()


func execute() -> ActionResult:
	var check_result: ActionResult = check()
	if not check_result.success:
		return check_result

	return CraftSystem.execute_craft(actor, str(target.get("recipe_id", "")))

class_name WaterAction
extends GameAction


func _init() -> void:
	action_type = "WaterAction"


func check() -> ActionResult:
	var base_result: ActionResult = super.check()
	if not base_result.success:
		return base_result

	var location_root: Node = _get_location_root()
	if location_root == null:
		return _failure("WaterAction requires a location root.")

	var cell: Vector2i = target.get("cell", actor.grid_position) as Vector2i
	var failed_requirement: String = CropSystem.get_water_failure(actor, location_root, cell)
	if not failed_requirement.is_empty():
		return _failure(failed_requirement)

	return _success()


func execute() -> ActionResult:
	var check_result: ActionResult = check()
	if not check_result.success:
		return check_result

	return CropSystem.execute_water(actor, _get_location_root(), target.get("cell", actor.grid_position) as Vector2i)


func _get_location_root() -> Node:
	var root_value: Variant = context.get("location_root", null)
	if typeof(root_value) != TYPE_OBJECT or not is_instance_valid(root_value):
		return null

	return root_value as Node

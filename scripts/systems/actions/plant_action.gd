class_name PlantAction
extends GameAction


func _init() -> void:
	action_type = "PlantAction"


func check() -> ActionResult:
	var base_result: ActionResult = super.check()
	if not base_result.success:
		return base_result

	var location_root: Node = _get_location_root()
	if location_root == null:
		return _failure("PlantAction requires a location root.")

	var cell: Vector2i = target.get("cell", actor.grid_position) as Vector2i
	var seed_item_id: String = str(target.get("seed_item_id", ""))
	var failed_requirement: String = CropSystem.get_plant_failure(actor, location_root, cell, seed_item_id)
	if not failed_requirement.is_empty():
		return _failure(failed_requirement)

	return _success()


func execute() -> ActionResult:
	var check_result: ActionResult = check()
	if not check_result.success:
		return check_result

	return CropSystem.execute_plant(actor, _get_location_root(), target.get("cell", actor.grid_position) as Vector2i, str(target.get("seed_item_id", "")))


func _get_location_root() -> Node:
	var root_value: Variant = context.get("location_root", null)
	if typeof(root_value) != TYPE_OBJECT or not is_instance_valid(root_value):
		return null

	return root_value as Node

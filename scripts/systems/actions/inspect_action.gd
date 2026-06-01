class_name InspectAction
extends GameAction


func _init() -> void:
	action_type = "InspectAction"


func check() -> ActionResult:
	var base_result: ActionResult = super.check()
	if not base_result.success:
		return base_result

	if bool(target.get("empty", false)):
		return _success()

	var object: LocationObject = _get_target_object()
	if object == null:
		return _failure("调查需要指定目标物体。")

	if not object.is_inspectable:
		return _failure("%s 不能调查。" % object.display_name)

	return _success()


func execute() -> ActionResult:
	var check_result: ActionResult = check()
	if not check_result.success:
		return check_result

	var result: ActionResult = _success()
	if bool(target.get("empty", false)):
		var target_cell: Vector2i = target.get("target_cell", Vector2i.ZERO) as Vector2i
		result.add_feedback("%s 没有什么值得注意的东西。" % target_cell)
		return result

	var object: LocationObject = _get_target_object()
	result.add_feedback(object.inspect_text)
	result.add_world_change({
		"type": "object_inspected",
		"character_id": actor.character_id,
		"object_id": object.object_id,
		"location_id": _get_location_id(),
	})
	return result


func _get_location_id() -> String:
	var location_root: Node = _get_location_root()
	if location_root == null or not location_root.has_method("get_location_grid"):
		return ""

	var grid: LocationGrid = location_root.get_location_grid() as LocationGrid
	if grid == null:
		return ""

	return grid.location_id


func _get_target_object() -> LocationObject:
	var object_value: Variant = target.get("object", null)
	if typeof(object_value) != TYPE_OBJECT or not is_instance_valid(object_value):
		return null

	return object_value as LocationObject


func _get_location_root() -> Node:
	var root_value: Variant = context.get("location_root", null)
	if typeof(root_value) != TYPE_OBJECT or not is_instance_valid(root_value):
		return null

	return root_value as Node

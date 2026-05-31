class_name UseItemAction
extends GameAction


func _init() -> void:
	action_type = "UseItemAction"


func check() -> ActionResult:
	var base_result: ActionResult = super.check()
	if not base_result.success:
		return base_result

	if target.has("object"):
		var object: LocationObject = _get_target_object()
		if object == null:
			return _failure("UseItemAction requires a target object.")

		if not object.is_usable:
			return _failure("%s cannot be used." % object.display_name)

		return _success()

	var item_id: String = str(target.get("item_id", ""))
	if item_id.is_empty():
		return _failure("UseItemAction requires an item_id or a target object.")

	if actor.inventory == null:
		return _failure("%s has no inventory." % actor.display_name)

	var stack: ItemStack = actor.inventory.get_first_stack(item_id)
	if stack == null:
		return _failure("%s does not have %s." % [actor.display_name, item_id])

	if not stack.is_usable:
		return _failure("%s cannot be used." % stack.display_name)

	return _success()


func execute() -> ActionResult:
	var check_result: ActionResult = check()
	if not check_result.success:
		return check_result

	var result: ActionResult = _success()
	if target.has("object"):
		var object: LocationObject = _get_target_object()
		result.add_world_change({
			"type": "location_object_used",
			"character_id": actor.character_id,
			"object_id": object.object_id,
		})
		result.add_feedback(object.use_feedback)
		return result

	var item_id: String = str(target.get("item_id", ""))
	var stack: ItemStack = actor.inventory.get_first_stack(item_id)
	result.add_world_change({
		"type": "inventory_item_used",
		"character_id": actor.character_id,
		"item_id": item_id,
	})
	result.add_feedback(stack.use_feedback)
	return result


func _get_target_object() -> LocationObject:
	var object_value: Variant = target.get("object", null)
	if typeof(object_value) != TYPE_OBJECT or not is_instance_valid(object_value):
		return null

	return object_value as LocationObject

class_name PickUpAction
extends GameAction


func _init() -> void:
	action_type = "PickUpAction"


func check() -> ActionResult:
	var base_result: ActionResult = super.check()
	if not base_result.success:
		return base_result

	var object: LocationObject = _get_target_object()
	if object == null:
		return _failure("PickUpAction requires a target object.")

	if not object.is_pickable:
		return _failure("%s cannot be picked up." % object.display_name)

	if object.item_definition.is_empty() or object.item_quantity <= 0:
		return _failure("%s has no item stack to pick up." % object.display_name)

	if actor.inventory == null:
		return _failure("%s has no inventory." % actor.display_name)

	if not actor.inventory.can_add_item(object.item_definition, object.item_quantity):
		return _failure("%s cannot carry %s." % [actor.display_name, object.display_name])

	var location_root: Node = _get_location_root()
	if location_root == null or not location_root.has_method("remove_location_object"):
		return _failure("PickUpAction requires a location root that can remove objects.")

	return _success()


func execute() -> ActionResult:
	var check_result: ActionResult = check()
	if not check_result.success:
		return check_result

	var object: LocationObject = _get_target_object()
	var location_root: Node = _get_location_root()
	var item_id: String = str(object.item_definition.get("id", ""))
	var item_name: String = str(object.item_definition.get("display_name", item_id))
	var quantity: int = object.item_quantity

	actor.inventory.add_item(object.item_definition, quantity)
	GameState.save_character_runtime(actor)
	location_root.remove_location_object(object.object_id)

	var result: ActionResult = _success()
	result.add_world_change({
		"type": "item_picked_up",
		"character_id": actor.character_id,
		"item_id": item_id,
		"quantity": quantity,
	})
	result.add_world_change({
		"type": "location_object_removed",
		"object_id": object.object_id,
	})
	result.add_feedback("%s picked up %d x %s." % [actor.display_name, quantity, item_name])
	return result


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

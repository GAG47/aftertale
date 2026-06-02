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
			return _failure("使用需要指定目标物体。")

		if not object.is_usable:
			return _failure("%s 不能使用。" % object.display_name)

		return _success()

	var item_id: String = str(target.get("item_id", ""))
	if item_id.is_empty():
		return _failure("使用需要指定物品或目标物体。")

	if actor.inventory == null:
		return _failure("%s 没有背包。" % actor.display_name)

	var stack: ItemStack = actor.inventory.get_first_stack(item_id)
	if stack == null:
		return _failure("%s 没有 %s。" % [actor.display_name, item_id])

	if not stack.is_usable:
		return _failure("%s 不能使用。" % stack.display_name)
	if not _is_consumable_item(stack.definition):
		return _failure("%s 现在不能从背包直接使用。" % stack.display_name)
	if _get_item_target() == null:
		return _failure("请选择当前队伍中的使用对象。")

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
	var item_target: CharacterEntity = _get_item_target()
	var item_definition: Dictionary = stack.definition.duplicate(true)
	var heal_amount: int = _get_item_heal_amount(item_definition)
	var actual_heal: int = 0
	if heal_amount > 0 and item_target != null:
		actual_heal = _apply_item_heal(item_target, heal_amount)
	actor.inventory.remove_item(item_id, 1)
	GameState.save_character_runtime(actor)
	if item_target != actor and item_target != null:
		GameState.save_character_runtime(item_target)

	result.add_world_change({
		"type": "inventory_item_used",
		"character_id": item_target.character_id if item_target != null else actor.character_id,
		"source_character_id": actor.character_id,
		"item_id": item_id,
		"heal_amount": actual_heal,
	})
	if actual_heal > 0:
		result.add_feedback("%s 给 %s 使用了 %s，恢复 %d 点生命。" % [
			actor.display_name,
			item_target.display_name,
			stack.display_name,
			actual_heal,
		])
	elif not stack.use_feedback.is_empty():
		result.add_feedback("%s 给 %s 使用了 %s。%s" % [
			actor.display_name,
			item_target.display_name if item_target != null else actor.display_name,
			stack.display_name,
			stack.use_feedback,
		])
	else:
		result.add_feedback("%s 给 %s 使用了 %s。" % [
			actor.display_name,
			item_target.display_name if item_target != null else actor.display_name,
			stack.display_name,
		])
	return result


func _get_target_object() -> LocationObject:
	var object_value: Variant = target.get("object", null)
	if typeof(object_value) != TYPE_OBJECT or not is_instance_valid(object_value):
		return null

	return object_value as LocationObject


func _is_consumable_item(item_definition: Dictionary) -> bool:
	var item_type: String = str(item_definition.get("item_type", ""))
	return item_type == "consumable" or item_type == "food"


func _get_item_target() -> CharacterEntity:
	var target_character_id: String = str(target.get("target_character_id", actor.character_id))
	if target_character_id.is_empty() or target_character_id == actor.character_id:
		return actor
	if not PartySystem.is_member(target_character_id):
		return null
	if SceneLoader.current_scene == null or not is_instance_valid(SceneLoader.current_scene):
		return null
	if not SceneLoader.current_scene.has_method("get_location_grid"):
		return null

	var grid: LocationGrid = SceneLoader.current_scene.get_location_grid() as LocationGrid
	if grid == null:
		return null
	return grid.get_character_by_id(target_character_id)


func _get_item_heal_amount(item_definition: Dictionary) -> int:
	if item_definition.has("heal_amount"):
		return max(0, int(item_definition.get("heal_amount", 0)))

	var effects: Array = item_definition.get("effects", []) as Array
	for effect_value in effects:
		var effect: Dictionary = effect_value as Dictionary
		if str(effect.get("type", "")) == "heal":
			return max(0, int(effect.get("amount", effect.get("value", 0))))

	var item_type: String = str(item_definition.get("item_type", ""))
	if item_type == "consumable" or item_type == "food":
		return 6
	return 0


func _apply_item_heal(character: CharacterEntity, amount: int) -> int:
	var before_hp: int = character.hp
	character.set_combat_stats(character.hp + amount, character.max_hp, false)
	return max(0, character.hp - before_hp)

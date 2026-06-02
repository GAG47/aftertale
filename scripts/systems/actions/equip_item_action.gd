class_name EquipItemAction
extends GameAction


func _init() -> void:
	action_type = "EquipItemAction"


func check() -> ActionResult:
	var base_result: ActionResult = super.check()
	if not base_result.success:
		return base_result

	var failed_requirement: String = _get_failed_requirement()
	if not failed_requirement.is_empty():
		return _failure(failed_requirement)

	return _success()


func execute() -> ActionResult:
	var check_result: ActionResult = check()
	if not check_result.success:
		return check_result

	var item_id: String = str(target.get("item_id", ""))
	var stack: ItemStack = actor.inventory.get_first_stack(item_id)
	var item_definition: Dictionary = stack.definition.duplicate(true)
	var equipment_owner: CharacterEntity = _get_equipment_owner()
	var slot_id: String = str(target.get("slot_id", item_definition.get("equipment_slot", "")))
	var previous_assignment: Dictionary = _get_existing_assignment(item_id)
	if not previous_assignment.is_empty():
		var previous_owner: CharacterEntity = previous_assignment.get("character", null) as CharacterEntity
		var previous_slot_id: String = str(previous_assignment.get("slot_id", ""))
		if previous_owner != null and is_instance_valid(previous_owner) and previous_slot_id != "":
			previous_owner.equipment_slots.unequip_item(previous_slot_id)
			GameState.save_character_runtime(previous_owner)

	var previous_item: Dictionary = equipment_owner.equipment_slots.equip_item(item_definition, slot_id)

	GameState.save_character_runtime(actor)
	if equipment_owner != actor:
		GameState.save_character_runtime(equipment_owner)

	var result: ActionResult = _success()
	result.add_world_change({
		"type": "item_equipped",
		"character_id": equipment_owner.character_id,
		"source_character_id": actor.character_id,
		"item_id": item_id,
		"slot_id": slot_id,
		"previous_item_id": str(previous_item.get("id", "")),
		"previous_character_id": str(previous_assignment.get("character_id", "")),
	})
	result.add_feedback("%s 为 %s 装备了 %s。" % [
		actor.display_name,
		equipment_owner.display_name,
		str(item_definition.get("display_name", item_id)),
	])
	return result


func _get_failed_requirement() -> String:
	if actor.inventory == null:
		return "%s 没有背包。" % actor.display_name

	var item_id: String = str(target.get("item_id", ""))
	if item_id.is_empty():
		return "装备需要指定物品。"

	var stack: ItemStack = actor.inventory.get_first_stack(item_id)
	if stack == null:
		return "%s 没有 %s。" % [actor.display_name, item_id]

	var item_definition: Dictionary = stack.definition
	var equipment_owner: CharacterEntity = _get_equipment_owner()
	if equipment_owner == null:
		return "请选择当前队伍中的装备对象。"
	if equipment_owner.equipment_slots == null:
		return "%s 没有装备栏。" % equipment_owner.display_name

	var slot_id: String = str(target.get("slot_id", item_definition.get("equipment_slot", "")))
	if not equipment_owner.equipment_slots.can_equip_item(item_definition, slot_id):
		return "%s 不能装备到这个槽位。" % stack.display_name

	return ""


func _get_equipment_owner() -> CharacterEntity:
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


func _get_existing_assignment(item_id: String) -> Dictionary:
	if item_id.is_empty():
		return {}
	if SceneLoader.current_scene == null or not is_instance_valid(SceneLoader.current_scene):
		return {}
	if not SceneLoader.current_scene.has_method("get_location_grid"):
		return {}

	var grid: LocationGrid = SceneLoader.current_scene.get_location_grid() as LocationGrid
	if grid == null:
		return {}

	for member_id in PartySystem.get_member_ids():
		var character: CharacterEntity = grid.get_character_by_id(member_id)
		if character == null or character.equipment_slots == null:
			continue
		var slot_id: String = character.equipment_slots.get_player_override_slot_for_item(item_id)
		if slot_id.is_empty():
			continue
		return {
			"character": character,
			"character_id": character.character_id,
			"slot_id": slot_id,
		}
	return {}

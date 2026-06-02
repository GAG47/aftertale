class_name UnequipItemAction
extends GameAction


func _init() -> void:
	action_type = "UnequipItemAction"


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

	var slot_id: String = str(target.get("slot_id", ""))
	var equipment_owner: CharacterEntity = _get_equipment_owner()
	var item_definition: Dictionary = equipment_owner.equipment_slots.unequip_item(slot_id)
	GameState.save_character_runtime(actor)
	GameState.save_character_runtime(equipment_owner)

	var result: ActionResult = _success()
	result.add_world_change({
		"type": "item_unequipped",
		"character_id": equipment_owner.character_id,
		"source_character_id": actor.character_id,
		"item_id": str(item_definition.get("id", "")),
		"slot_id": slot_id,
	})
	result.add_feedback("%s 从 %s 身上取回了 %s。" % [
		actor.display_name,
		equipment_owner.display_name,
		str(item_definition.get("display_name", item_definition.get("id", ""))),
	])
	return result


func _get_failed_requirement() -> String:
	var equipment_owner: CharacterEntity = _get_equipment_owner()
	if equipment_owner == null:
		return "请选择当前队伍中的装备对象。"
	if equipment_owner.equipment_slots == null:
		return "%s 没有装备栏。" % equipment_owner.display_name

	var slot_id: String = str(target.get("slot_id", ""))
	if slot_id.is_empty():
		return "取回装备需要指定槽位。"
	if not equipment_owner.equipment_slots.can_equip(slot_id):
		return "未知装备槽位：%s。" % slot_id

	var item_definition: Dictionary = equipment_owner.equipment_slots.get_player_override_item(slot_id)
	if item_definition.is_empty():
		return "这个槽位没有可取回的玩家装备。"

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

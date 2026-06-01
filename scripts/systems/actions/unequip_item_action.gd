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
	var item_definition: Dictionary = actor.equipment_slots.unequip_item(slot_id)
	actor.inventory.add_item(item_definition, 1)
	GameState.save_character_runtime(actor)

	var result: ActionResult = _success()
	result.add_world_change({
		"type": "item_unequipped",
		"character_id": actor.character_id,
		"item_id": str(item_definition.get("id", "")),
		"slot_id": slot_id,
	})
	result.add_feedback("%s 卸下了 %s。" % [
		actor.display_name,
		str(item_definition.get("display_name", item_definition.get("id", ""))),
	])
	return result


func _get_failed_requirement() -> String:
	if actor.inventory == null:
		return "%s 没有背包。" % actor.display_name
	if actor.equipment_slots == null:
		return "%s 没有装备栏。" % actor.display_name

	var slot_id: String = str(target.get("slot_id", ""))
	if slot_id.is_empty():
		return "卸下装备需要指定槽位。"
	if not actor.equipment_slots.can_equip(slot_id):
		return "未知装备槽位：%s。" % slot_id

	var item_definition: Dictionary = actor.equipment_slots.get_equipped_item(slot_id)
	if item_definition.is_empty():
		return "这个槽位没有装备。"
	if not actor.inventory.can_add_item(item_definition, 1):
		return "%s 的背包装不下卸下的装备。" % actor.display_name

	return ""

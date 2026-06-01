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
	var slot_id: String = str(target.get("slot_id", item_definition.get("equipment_slot", "")))
	var previous_item: Dictionary = actor.equipment_slots.equip_item(item_definition, slot_id)

	actor.inventory.remove_item(item_id, 1)
	if not previous_item.is_empty():
		actor.inventory.add_item(previous_item, 1)

	GameState.save_character_runtime(actor)

	var result: ActionResult = _success()
	result.add_world_change({
		"type": "item_equipped",
		"character_id": actor.character_id,
		"item_id": item_id,
		"slot_id": slot_id,
		"previous_item_id": str(previous_item.get("id", "")),
	})
	result.add_feedback("%s 装备了 %s。" % [
		actor.display_name,
		str(item_definition.get("display_name", item_id)),
	])
	return result


func _get_failed_requirement() -> String:
	if actor.inventory == null:
		return "%s 没有背包。" % actor.display_name
	if actor.equipment_slots == null:
		return "%s 没有装备栏。" % actor.display_name

	var item_id: String = str(target.get("item_id", ""))
	if item_id.is_empty():
		return "装备需要指定物品。"

	var stack: ItemStack = actor.inventory.get_first_stack(item_id)
	if stack == null:
		return "%s 没有 %s。" % [actor.display_name, item_id]

	var item_definition: Dictionary = stack.definition
	var slot_id: String = str(target.get("slot_id", item_definition.get("equipment_slot", "")))
	if not actor.equipment_slots.can_equip_item(item_definition, slot_id):
		return "%s 不能装备到这个槽位。" % stack.display_name

	var previous_item: Dictionary = actor.equipment_slots.get_equipped_item(slot_id)
	if not previous_item.is_empty() and not _inventory_accepts_replaced_item(actor.inventory, item_id, previous_item):
		return "%s 的背包装不下替换下来的装备。" % actor.display_name

	return ""


func _inventory_accepts_replaced_item(inventory: Inventory, equipped_item_id: String, replacement_item: Dictionary) -> bool:
	var simulated_inventory: Inventory = Inventory.new()
	simulated_inventory.apply_runtime_state(inventory.get_runtime_state())
	if not simulated_inventory.remove_item(equipped_item_id, 1):
		return false

	return simulated_inventory.can_add_item(replacement_item, 1)

class_name Inventory
extends RefCounted

var owner_id: String = ""
var capacity: int = 24
var stacks: Array[ItemStack] = []


func configure(new_owner_id: String, new_capacity: int = 24) -> void:
	owner_id = new_owner_id
	capacity = max(new_capacity, 1)


func can_add_item(item_definition: Dictionary, quantity: int) -> bool:
	if quantity <= 0:
		return false

	var remaining: int = quantity
	for stack in stacks:
		if stack.can_merge(item_definition):
			remaining -= stack.available_space()
			if remaining <= 0:
				return true

	var item_stackable: bool = bool(item_definition.get("stackable", true))
	var item_max_stack: int = int(item_definition.get("max_stack", 1))
	if not item_stackable:
		item_max_stack = 1

	var empty_slots: int = capacity - stacks.size()
	while empty_slots > 0 and remaining > 0:
		remaining -= item_max_stack
		empty_slots -= 1

	return remaining <= 0


func add_item(item_definition: Dictionary, quantity: int) -> bool:
	if not can_add_item(item_definition, quantity):
		return false

	var remaining: int = quantity
	for stack in stacks:
		if stack.can_merge(item_definition):
			remaining = stack.add_quantity(remaining)
			if remaining <= 0:
				return true

	while remaining > 0:
		var new_stack: ItemStack = ItemStack.from_definition(item_definition, remaining)
		stacks.append(new_stack)
		remaining -= new_stack.quantity

	return true


func remove_item(item_id: String, quantity: int) -> bool:
	if count_item(item_id) < quantity:
		return false

	var remaining: int = quantity
	for stack in stacks.duplicate():
		if stack.item_id != item_id:
			continue

		var removed: int = stack.remove_quantity(remaining)
		remaining -= removed
		if stack.is_empty():
			stacks.erase(stack)

		if remaining <= 0:
			return true

	return true


func get_first_stack(item_id: String) -> ItemStack:
	for stack in stacks:
		if stack.item_id == item_id:
			return stack

	return null


func count_item(item_id: String) -> int:
	var total: int = 0
	for stack in stacks:
		if stack.item_id == item_id:
			total += stack.quantity

	return total


func is_empty() -> bool:
	return stacks.is_empty()


func get_summary() -> Array[Dictionary]:
	var summary: Array[Dictionary] = []
	for stack in stacks:
		summary.append(stack.to_dictionary())

	return summary


func get_runtime_state() -> Dictionary:
	var item_rows: Array[Dictionary] = []
	for stack in stacks:
		item_rows.append({
			"definition": stack.definition.duplicate(true),
			"quantity": stack.quantity,
		})

	return {
		"owner_id": owner_id,
		"capacity": capacity,
		"items": item_rows,
	}


func apply_runtime_state(state: Dictionary) -> void:
	capacity = max(1, int(state.get("capacity", capacity)))
	stacks.clear()

	var item_rows: Array = state.get("items", []) as Array
	for item_value in item_rows:
		var item_data: Dictionary = item_value as Dictionary
		var definition: Dictionary = item_data.get("definition", {}) as Dictionary
		if definition.is_empty():
			continue

		add_item(definition, int(item_data.get("quantity", 1)))

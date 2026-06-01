class_name ItemStack
extends RefCounted

var item_id: String = ""
var display_name: String = ""
var item_type: String = ""
var quantity: int = 0
var stackable: bool = true
var max_stack: int = 1
var is_usable: bool = false
var use_feedback: String = ""
var definition: Dictionary = {}


static func from_definition(item_definition: Dictionary, amount: int) -> ItemStack:
	var stack: ItemStack = ItemStack.new()
	stack.item_id = str(item_definition.get("id", ""))
	stack.display_name = str(item_definition.get("display_name", stack.item_id))
	stack.item_type = str(item_definition.get("item_type", "misc"))
	stack.stackable = bool(item_definition.get("stackable", true))
	stack.max_stack = int(item_definition.get("max_stack", 1))
	stack.is_usable = bool(item_definition.get("is_usable", false))
	stack.use_feedback = str(item_definition.get("use_feedback", ""))
	stack.definition = item_definition.duplicate(true)
	stack.quantity = clampi(amount, 0, stack.max_stack)
	return stack


func can_merge(item_definition: Dictionary) -> bool:
	if not stackable:
		return false

	return item_id == str(item_definition.get("id", ""))


func available_space() -> int:
	return max_stack - quantity


func add_quantity(amount: int) -> int:
	if amount <= 0:
		return 0

	var accepted: int = min(amount, available_space())
	quantity += accepted
	return amount - accepted


func remove_quantity(amount: int) -> int:
	if amount <= 0:
		return 0

	var removed: int = min(amount, quantity)
	quantity -= removed
	return removed


func is_empty() -> bool:
	return quantity <= 0


func to_dictionary() -> Dictionary:
	return {
		"item_id": item_id,
		"display_name": display_name,
		"item_type": item_type,
		"quantity": quantity,
		"stackable": stackable,
		"max_stack": max_stack,
		"is_usable": is_usable,
		"equippable": bool(definition.get("equippable", false)),
		"equipment_slot": str(definition.get("equipment_slot", "")),
		"attribute_bonuses": (definition.get("attribute_bonuses", {}) as Dictionary).duplicate(true),
		"description": str(definition.get("description", "")),
		"use_feedback": use_feedback,
	}

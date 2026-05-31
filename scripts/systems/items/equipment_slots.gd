class_name EquipmentSlots
extends RefCounted

var owner_id: String = ""
var slots: Dictionary = {
	"weapon": "",
	"offhand": "",
	"head": "",
	"body": "",
	"accessory": "",
	"tool": "",
}


func configure(new_owner_id: String) -> void:
	owner_id = new_owner_id


func can_equip(slot_id: String) -> bool:
	return slots.has(slot_id)


func equip(slot_id: String, item_id: String) -> bool:
	if not can_equip(slot_id):
		return false

	slots[slot_id] = item_id
	return true


func unequip(slot_id: String) -> String:
	if not can_equip(slot_id):
		return ""

	var previous_item_id: String = str(slots[slot_id])
	slots[slot_id] = ""
	return previous_item_id


func get_summary() -> Dictionary:
	return slots.duplicate(true)

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
# Character definition equipment. These are defaults, not movable items.
var default_items: Dictionary = {}
# Player-provided equipment that temporarily overrides defaults.
var equipped_items: Dictionary = {}


func configure(new_owner_id: String) -> void:
	owner_id = new_owner_id
	for slot_id in slots.keys():
		default_items[slot_id] = {}
		equipped_items[slot_id] = {}
		_sync_slot(slot_id)


func can_equip(slot_id: String) -> bool:
	return slots.has(slot_id)


func can_equip_item(item_definition: Dictionary, slot_id: String = "") -> bool:
	if item_definition.is_empty():
		return false
	if not bool(item_definition.get("equippable", false)):
		return false

	var target_slot: String = slot_id
	if target_slot.is_empty():
		target_slot = str(item_definition.get("equipment_slot", ""))
	if target_slot.is_empty():
		return false

	return can_equip(target_slot)


func equip(slot_id: String, item_id: String) -> bool:
	if not can_equip(slot_id):
		return false

	slots[slot_id] = item_id
	return true


func equip_item(item_definition: Dictionary, slot_id: String = "") -> Dictionary:
	var target_slot: String = slot_id
	if target_slot.is_empty():
		target_slot = str(item_definition.get("equipment_slot", ""))
	if not can_equip_item(item_definition, target_slot):
		return {}

	var previous_item: Dictionary = get_player_override_item(target_slot)
	slots[target_slot] = str(item_definition.get("id", ""))
	equipped_items[target_slot] = item_definition.duplicate(true)
	return previous_item


func unequip(slot_id: String) -> String:
	if not can_equip(slot_id):
		return ""

	var previous_item_id: String = str(slots[slot_id])
	slots[slot_id] = ""
	equipped_items[slot_id] = {}
	return previous_item_id


func unequip_item(slot_id: String) -> Dictionary:
	if not can_equip(slot_id):
		return {}

	var previous_item: Dictionary = get_player_override_item(slot_id)
	equipped_items[slot_id] = {}
	_sync_slot(slot_id)
	return previous_item


func get_player_override_slot_for_item(item_id: String) -> String:
	if item_id.is_empty():
		return ""
	for slot_id_value in slots.keys():
		var slot_id: String = str(slot_id_value)
		var item_definition: Dictionary = get_player_override_item(slot_id)
		if str(item_definition.get("id", "")) == item_id:
			return slot_id
	return ""


func get_equipped_item(slot_id: String) -> Dictionary:
	var player_item: Dictionary = get_player_override_item(slot_id)
	if not player_item.is_empty():
		return player_item
	return get_default_item(slot_id)


func get_player_override_item(slot_id: String) -> Dictionary:
	if not equipped_items.has(slot_id):
		return {}

	return (equipped_items.get(slot_id, {}) as Dictionary).duplicate(true)


func get_default_item(slot_id: String) -> Dictionary:
	if not default_items.has(slot_id):
		return {}

	return (default_items.get(slot_id, {}) as Dictionary).duplicate(true)


func has_player_override(slot_id: String) -> bool:
	return not get_player_override_item(slot_id).is_empty()


func set_default_item(item_definition: Dictionary, slot_id: String = "") -> bool:
	var target_slot: String = slot_id
	if target_slot.is_empty():
		target_slot = str(item_definition.get("equipment_slot", ""))
	if not can_equip_item(item_definition, target_slot):
		return false

	default_items[target_slot] = item_definition.duplicate(true)
	_sync_slot(target_slot)
	return true


func clear_default_item(slot_id: String) -> void:
	if not can_equip(slot_id):
		return
	default_items[slot_id] = {}
	_sync_slot(slot_id)


func take_player_override_items() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for item_definition in get_player_override_items():
		result.append(item_definition)
	for slot_id_value in slots.keys():
		var slot_id: String = str(slot_id_value)
		equipped_items[slot_id] = {}
		_sync_slot(slot_id)
	return result


func get_player_override_items() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for slot_id_value in slots.keys():
		var slot_id: String = str(slot_id_value)
		var item_definition: Dictionary = get_player_override_item(slot_id)
		if item_definition.is_empty():
			continue
		result.append(item_definition)
	return result


func get_attribute_bonuses() -> Dictionary:
	var bonuses: Dictionary = {}
	for slot_id_value in slots.keys():
		var item_definition: Dictionary = get_equipped_item(str(slot_id_value))
		var item_bonuses: Dictionary = item_definition.get("attribute_bonuses", {}) as Dictionary
		for key in item_bonuses.keys():
			var attribute_id: String = str(key)
			bonuses[attribute_id] = int(bonuses.get(attribute_id, 0)) + int(item_bonuses[key])

	return bonuses


func get_summary() -> Dictionary:
	return slots.duplicate(true)


func get_detailed_summary() -> Dictionary:
	var summary: Dictionary = {}
	for slot_id_value in slots.keys():
		var slot_id: String = str(slot_id_value)
		var item_definition: Dictionary = get_equipped_item(slot_id)
		summary[slot_id] = {
			"item_id": str(slots.get(slot_id, "")),
			"display_name": str(item_definition.get("display_name", "")),
			"description": str(item_definition.get("description", "")),
			"attribute_bonuses": (item_definition.get("attribute_bonuses", {}) as Dictionary).duplicate(true),
			"is_player_override": has_player_override(slot_id),
			"is_default_equipment": not item_definition.is_empty() and not has_player_override(slot_id),
		}

	return summary


func get_runtime_state() -> Dictionary:
	var items: Dictionary = {}
	var defaults: Dictionary = {}
	for slot_id_value in slots.keys():
		var slot_id: String = str(slot_id_value)
		items[slot_id] = get_player_override_item(slot_id)
		defaults[slot_id] = get_default_item(slot_id)

	return {
		"owner_id": owner_id,
		"slots": slots.duplicate(true),
		"default_items": defaults,
		"equipped_items": items,
	}


func apply_runtime_state(state: Dictionary) -> void:
	var saved_slots: Dictionary = state.get("slots", {}) as Dictionary
	if not saved_slots.is_empty():
		slots.merge(saved_slots, true)

	if state.has("default_items"):
		default_items.clear()
		var defaults: Dictionary = state.get("default_items", {}) as Dictionary
		for slot_id_value in slots.keys():
			var slot_id: String = str(slot_id_value)
			var item_definition: Dictionary = defaults.get(slot_id, {}) as Dictionary
			default_items[slot_id] = item_definition.duplicate(true)

	equipped_items.clear()
	var items: Dictionary = state.get("equipped_items", {}) as Dictionary
	for slot_id_value in slots.keys():
		var slot_id: String = str(slot_id_value)
		var item_definition: Dictionary = items.get(slot_id, {}) as Dictionary
		equipped_items[slot_id] = item_definition.duplicate(true)
		if not default_items.has(slot_id):
			default_items[slot_id] = {}
		_sync_slot(slot_id)


func _sync_slot(slot_id: String) -> void:
	if not can_equip(slot_id):
		return
	var item_definition: Dictionary = get_player_override_item(slot_id)
	if item_definition.is_empty():
		item_definition = get_default_item(slot_id)
	slots[slot_id] = str(item_definition.get("id", ""))

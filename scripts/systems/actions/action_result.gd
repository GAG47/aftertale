class_name ActionResult
extends RefCounted

var action_type: String = ""
var actor_id: String = ""
var target: Dictionary = {}
var success: bool = false
var failure_reason: String = ""
var world_changes: Array[Dictionary] = []
var feedback: Array[String] = []
var already_published: bool = false


static func succeeded(action_type_value: String, actor_id_value: String, target_value: Dictionary = {}) -> ActionResult:
	var result: ActionResult = ActionResult.new()
	result.action_type = action_type_value
	result.actor_id = actor_id_value
	result.target = target_value.duplicate(true)
	result.success = true
	return result


static func failed(action_type_value: String, actor_id_value: String, reason: String, target_value: Dictionary = {}) -> ActionResult:
	var result: ActionResult = ActionResult.new()
	result.action_type = action_type_value
	result.actor_id = actor_id_value
	result.target = target_value.duplicate(true)
	result.success = false
	result.failure_reason = reason
	result.feedback.append(reason)
	return result


func add_world_change(change: Dictionary) -> void:
	world_changes.append(change.duplicate(true))


func add_feedback(message: String) -> void:
	if not message.is_empty():
		feedback.append(message)


func to_dictionary() -> Dictionary:
	return {
		"action_type": action_type,
		"actor_id": actor_id,
		"target": _safe_dictionary(target),
		"success": success,
		"failure_reason": failure_reason,
		"world_changes": _safe_array(world_changes),
		"feedback": feedback,
	}


func _safe_dictionary(source: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for key in source.keys():
		result[key] = _safe_value(source[key])

	return result


func _safe_array(source: Array) -> Array:
	var result: Array = []
	for value in source:
		result.append(_safe_value(value))

	return result


func _safe_value(value: Variant) -> Variant:
	match typeof(value):
		TYPE_DICTIONARY:
			return _safe_dictionary(value as Dictionary)
		TYPE_ARRAY:
			return _safe_array(value as Array)
		TYPE_OBJECT:
			if not is_instance_valid(value):
				return { "object": "freed" }
			var object: Object = value as Object
			return {
				"object_class": object.get_class(),
				"instance_id": object.get_instance_id(),
			}
		_:
			return value

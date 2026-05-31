class_name QuestState
extends RefCounted

const STATUS_INACTIVE := "inactive"
const STATUS_ACTIVE := "active"
const STATUS_COMPLETED := "completed"
const STATUS_FAILED := "failed"

var quest_id: String = ""
var display_name: String = ""
var status: String = STATUS_INACTIVE
var source: Dictionary = {}
var objectives: Dictionary = {}
var started_at: String = ""
var completed_at: String = ""
var failed_reason: String = ""


static func from_definition(definition: Dictionary) -> QuestState:
	var state: QuestState = QuestState.new()
	state.quest_id = str(definition.get("id", ""))
	state.display_name = str(definition.get("display_name", state.quest_id))
	state.status = STATUS_INACTIVE
	state.source = (definition.get("source", {}) as Dictionary).duplicate(true)

	var objective_rows: Array = definition.get("objectives", []) as Array
	for objective_value in objective_rows:
		var objective: Dictionary = objective_value as Dictionary
		var objective_id: String = str(objective.get("id", ""))
		if objective_id.is_empty():
			continue

		state.objectives[objective_id] = {
			"id": objective_id,
			"description": str(objective.get("description", objective_id)),
			"completed": false,
		}

	return state


func activate() -> void:
	status = STATUS_ACTIVE
	started_at = Time.get_datetime_string_from_system(false, true)


func complete() -> void:
	status = STATUS_COMPLETED
	completed_at = Time.get_datetime_string_from_system(false, true)


func fail(reason: String) -> void:
	status = STATUS_FAILED
	failed_reason = reason


func mark_objective_completed(objective_id: String) -> bool:
	if not objectives.has(objective_id):
		return false

	var objective: Dictionary = objectives[objective_id] as Dictionary
	if bool(objective.get("completed", false)):
		return false

	objective["completed"] = true
	objectives[objective_id] = objective
	return true


func is_all_objectives_completed() -> bool:
	for objective_value in objectives.values():
		var objective: Dictionary = objective_value as Dictionary
		if not bool(objective.get("completed", false)):
			return false

	return true


func get_completed_count() -> int:
	var count: int = 0
	for objective_value in objectives.values():
		var objective: Dictionary = objective_value as Dictionary
		if bool(objective.get("completed", false)):
			count += 1

	return count


func get_total_count() -> int:
	return objectives.size()


func to_dictionary() -> Dictionary:
	return {
		"quest_id": quest_id,
		"display_name": display_name,
		"status": status,
		"source": source,
		"objectives": objectives,
		"started_at": started_at,
		"completed_at": completed_at,
		"failed_reason": failed_reason,
		"completed_count": get_completed_count(),
		"total_count": get_total_count(),
	}


func apply_save_state(state: Dictionary) -> void:
	status = str(state.get("status", status))
	source = (state.get("source", source) as Dictionary).duplicate(true)
	objectives = (state.get("objectives", objectives) as Dictionary).duplicate(true)
	started_at = str(state.get("started_at", started_at))
	completed_at = str(state.get("completed_at", completed_at))
	failed_reason = str(state.get("failed_reason", failed_reason))

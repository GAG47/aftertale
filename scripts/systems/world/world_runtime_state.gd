class_name WorldRuntimeState
extends RefCounted

var world_id: String = ""
var current_location_id: String = ""
var generated_locations_by_id: Dictionary = {}
var generated_metadata_by_id: Dictionary = {}
var generation_counts_by_id: Dictionary = {}
var transition_history: Array = []


func configure(new_world_id: String, start_location_id: String = "") -> void:
	world_id = new_world_id
	current_location_id = start_location_id
	generated_locations_by_id.clear()
	generated_metadata_by_id.clear()
	generation_counts_by_id.clear()
	transition_history.clear()


func has_location(location_id: String) -> bool:
	return generated_locations_by_id.has(location_id)


func get_location_data(location_id: String) -> Dictionary:
	return (generated_locations_by_id.get(location_id, {}) as Dictionary).duplicate(true)


func register_location(location_id: String, location_data: Dictionary, metadata: Dictionary = {}, generated: bool = false) -> void:
	if location_id.is_empty() or location_data.is_empty():
		return
	generated_locations_by_id[location_id] = location_data.duplicate(true)
	generated_metadata_by_id[location_id] = metadata.duplicate(true)
	if generated:
		generation_counts_by_id[location_id] = int(generation_counts_by_id.get(location_id, 0)) + 1


func get_location_metadata(location_id: String) -> Dictionary:
	return (generated_metadata_by_id.get(location_id, {}) as Dictionary).duplicate(true)


func get_generation_count(location_id: String) -> int:
	return int(generation_counts_by_id.get(location_id, 0))


func record_transition(summary: Dictionary) -> void:
	transition_history.append(summary.duplicate(true))
	if transition_history.size() > 20:
		transition_history.pop_front()


func get_save_state() -> Dictionary:
	return {
		"world_id": world_id,
		"current_location_id": current_location_id,
		"generated_locations_by_id": generated_locations_by_id.duplicate(true),
		"generated_metadata_by_id": generated_metadata_by_id.duplicate(true),
		"generation_counts_by_id": generation_counts_by_id.duplicate(true),
		"transition_history": transition_history.duplicate(true),
	}


func apply_save_state(state: Dictionary) -> void:
	world_id = str(state.get("world_id", ""))
	current_location_id = str(state.get("current_location_id", ""))
	generated_locations_by_id = (state.get("generated_locations_by_id", {}) as Dictionary).duplicate(true)
	generated_metadata_by_id = (state.get("generated_metadata_by_id", {}) as Dictionary).duplicate(true)
	generation_counts_by_id = (state.get("generation_counts_by_id", {}) as Dictionary).duplicate(true)
	transition_history = (state.get("transition_history", []) as Array).duplicate(true)

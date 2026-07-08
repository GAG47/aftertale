extends Node

signal region_graph_loaded(region_id: String)
signal region_travel_completed(summary: Dictionary)
signal region_travel_failed(summary: Dictionary)

const RegionLocationGraphValidatorScript := preload("res://scripts/systems/regions/region_location_graph_validator.gd")

var _snapshot: Dictionary = {}
var _locations_by_id: Dictionary = {}
var _edges_by_id: Dictionary = {}
var _edges_from_location_id: Dictionary = {}
var current_location_id: String = ""
var last_travel_summary: Dictionary = {}


func reset_graph() -> void:
	_snapshot.clear()
	_locations_by_id.clear()
	_edges_by_id.clear()
	_edges_from_location_id.clear()
	current_location_id = ""
	last_travel_summary.clear()


func load_snapshot(snapshot: Dictionary) -> Dictionary:
	reset_graph()
	var validator: RefCounted = RegionLocationGraphValidatorScript.new()
	var errors: Array[String] = validator.validate(snapshot)
	if not errors.is_empty():
		return _fail("RegionGraphRuntimeService snapshot validation failed: %s" % str(errors), {})
	_snapshot = snapshot.duplicate(true)
	for location_value in (_snapshot.get("locations", []) as Array):
		var location: Dictionary = location_value as Dictionary
		_locations_by_id[str(location.get("location_id", ""))] = location.duplicate(true)
	for edge_value in (_snapshot.get("edges", []) as Array):
		var edge: Dictionary = edge_value as Dictionary
		var edge_id := str(edge.get("edge_id", ""))
		var from_location_id := str(edge.get("from_location_id", ""))
		_edges_by_id[edge_id] = edge.duplicate(true)
		var rows: Array = _edges_from_location_id.get(from_location_id, []) as Array
		rows.append(edge.duplicate(true))
		_edges_from_location_id[from_location_id] = rows
	region_graph_loaded.emit(str(_snapshot.get("region_id", "")))
	return {
		"success": true,
		"errors": [],
		"warnings": [],
		"region_id": str(_snapshot.get("region_id", "")),
		"location_count": _locations_by_id.size(),
		"edge_count": _edges_by_id.size(),
	}


func start_graph(update_game_state: bool = true) -> Dictionary:
	if not is_graph_active():
		return _fail("No active Region Location Graph is loaded.", {})
	var start_location_id := str(_snapshot.get("start_location_id", ""))
	if not _locations_by_id.has(start_location_id):
		return _fail("Region Location Graph start_location_id is missing: %s" % start_location_id, {})
	current_location_id = start_location_id
	if update_game_state:
		GameState.set_scene_context(current_location_id, current_location_id)
	last_travel_summary = {
		"success": true,
		"region_id": str(_snapshot.get("region_id", "")),
		"edge_id": "__start__",
		"from_location_id": "",
		"target_location_id": current_location_id,
		"travel_type": "enter",
		"direction_hint": "start",
		"access_rule": "always",
		"exit_style": "none",
		"reverse_traversal": false,
	}
	region_travel_completed.emit(last_travel_summary.duplicate(true))
	return last_travel_summary.duplicate(true)


func travel_by_edge_id(edge_id: String, update_game_state: bool = true) -> Dictionary:
	if not is_graph_active():
		return _fail("No active Region Location Graph is loaded.", { "edge_id": edge_id })
	if current_location_id.is_empty():
		return _fail("Region Location Graph has no current_location_id.", { "edge_id": edge_id })
	if not _edges_by_id.has(edge_id):
		return _fail("Unknown Region Graph edge_id: %s" % edge_id, { "edge_id": edge_id })
	var edge: Dictionary = _edges_by_id.get(edge_id, {}) as Dictionary
	var from_location_id := str(edge.get("from_location_id", ""))
	var to_location_id := str(edge.get("to_location_id", ""))
	var reverse_traversal := false
	if from_location_id != current_location_id:
		if not bool(edge.get("bidirectional", true)) or to_location_id != current_location_id:
			return _fail("Region Graph edge is not reachable from current location: %s" % edge_id, {
				"edge_id": edge_id,
				"current_location_id": current_location_id,
			})
		reverse_traversal = true
		to_location_id = from_location_id
	if not _locations_by_id.has(to_location_id):
		return _fail("Region Graph edge target location is missing: %s" % edge_id, { "edge_id": edge_id })
	return _complete_travel(edge, current_location_id, to_location_id, reverse_traversal, update_game_state)


func enter_location(location_id: String, update_game_state: bool = true) -> Dictionary:
	if not is_graph_active():
		return _fail("No active Region Location Graph is loaded.", { "target_location_id": location_id })
	if location_id.is_empty():
		return _fail("Region Graph enter_location requires a location_id.", {})
	if not _locations_by_id.has(location_id):
		return _fail("Unknown Region Graph location_id: %s" % location_id, {
			"target_location_id": location_id,
		})
	var previous_location_id := current_location_id
	current_location_id = location_id
	if update_game_state:
		GameState.set_scene_context(current_location_id, current_location_id)
	last_travel_summary = {
		"success": true,
		"region_id": str(_snapshot.get("region_id", "")),
		"edge_id": "__enter__",
		"from_location_id": previous_location_id,
		"target_location_id": current_location_id,
		"travel_type": "enter",
		"direction_hint": "direct",
		"access_rule": "always",
		"exit_style": "none",
		"reverse_traversal": false,
	}
	region_travel_completed.emit(last_travel_summary.duplicate(true))
	return last_travel_summary.duplicate(true)


func has_location(location_id: String) -> bool:
	return _locations_by_id.has(location_id)


func get_current_location() -> Dictionary:
	return get_location(current_location_id)


func get_edge(edge_id: String) -> Dictionary:
	return (_edges_by_id.get(edge_id, {}) as Dictionary).duplicate(true)


func get_adjacent_locations(location_id: String = "") -> Array[Dictionary]:
	var source_location_id := location_id
	if source_location_id.is_empty():
		source_location_id = current_location_id
	var result: Array[Dictionary] = []
	for edge_value in get_edges_from(source_location_id):
		var edge: Dictionary = edge_value as Dictionary
		var target_location_id := str(edge.get("traversal_to_location_id", ""))
		var location := get_location(target_location_id)
		if location.is_empty():
			continue
		location["via_edge_id"] = str(edge.get("edge_id", ""))
		location["travel_type"] = str(edge.get("travel_type", ""))
		location["direction_hint"] = str(edge.get("direction_hint", ""))
		location["access_rule"] = str(edge.get("access_rule", ""))
		location["exit_style"] = str(edge.get("exit_style", ""))
		result.append(location)
	return result


func validate_location_reference(location_id: String, source_label: String = "location_reference") -> Dictionary:
	var label := source_label if not source_label.is_empty() else "location_reference"
	if not is_graph_active():
		return _fail("Cannot validate %s because no Region Location Graph is loaded." % label, {
			"location_id": location_id,
			"source_label": label,
		})
	if location_id.is_empty():
		return _fail("%s is missing location_id." % label, {
			"source_label": label,
		})
	if not _locations_by_id.has(location_id):
		return _fail("%s references unknown Region Graph location_id: %s" % [label, location_id], {
			"location_id": location_id,
			"source_label": label,
		})
	return {
		"success": true,
		"errors": [],
		"warnings": [],
		"location_id": location_id,
		"source_label": label,
	}


func validate_location_references(references: Array) -> Dictionary:
	var errors: Array[String] = []
	for index in range(references.size()):
		if not (references[index] is Dictionary):
			errors.append("location reference row must be an object: %d" % index)
			continue
		var reference: Dictionary = references[index] as Dictionary
		var source_label := str(reference.get("source_label", reference.get("source", "location_reference")))
		var validation := validate_location_reference(str(reference.get("location_id", "")), source_label)
		if not bool(validation.get("success", false)):
			errors.append_array(validation.get("errors", []) as Array[String])
	if not errors.is_empty():
		return {
			"success": false,
			"errors": errors,
			"warnings": [],
		}
	return {
		"success": true,
		"errors": [],
		"warnings": [],
		"reference_count": references.size(),
	}


func _complete_travel(edge: Dictionary, from_location_id: String, target_location_id: String, reverse_traversal: bool, update_game_state: bool) -> Dictionary:
	current_location_id = target_location_id
	if update_game_state:
		GameState.set_scene_context(current_location_id, current_location_id)
	last_travel_summary = {
		"success": true,
		"region_id": str(_snapshot.get("region_id", "")),
		"edge_id": str(edge.get("edge_id", "")),
		"from_location_id": from_location_id,
		"target_location_id": current_location_id,
		"travel_type": str(edge.get("travel_type", "")),
		"direction_hint": str(edge.get("direction_hint", "")),
		"access_rule": str(edge.get("access_rule", "")),
		"exit_style": str(edge.get("exit_style", "")),
		"reverse_traversal": reverse_traversal,
	}
	region_travel_completed.emit(last_travel_summary.duplicate(true))
	return last_travel_summary.duplicate(true)


func is_graph_active() -> bool:
	return not _snapshot.is_empty() and not str(_snapshot.get("region_id", "")).is_empty()


func get_region_id() -> String:
	return str(_snapshot.get("region_id", "")) if is_graph_active() else ""


func get_snapshot() -> Dictionary:
	return _snapshot.duplicate(true)


func get_location(location_id: String) -> Dictionary:
	return (_locations_by_id.get(location_id, {}) as Dictionary).duplicate(true)


func get_edges_from(location_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for edge_value in (_edges_from_location_id.get(location_id, []) as Array):
		var edge: Dictionary = edge_value as Dictionary
		result.append(_edge_for_traversal(edge, location_id, str(edge.get("to_location_id", "")), false))
	for edge_value in (_snapshot.get("edges", []) as Array):
		var edge: Dictionary = edge_value as Dictionary
		if bool(edge.get("bidirectional", true)) and str(edge.get("to_location_id", "")) == location_id:
			result.append(_edge_for_traversal(edge, location_id, str(edge.get("from_location_id", "")), true))
	return result


func get_save_state() -> Dictionary:
	if not is_graph_active():
		return {}
	return {
		"snapshot": _snapshot.duplicate(true),
		"current_location_id": current_location_id,
	}


func apply_save_state(state: Dictionary) -> Dictionary:
	if state.is_empty():
		reset_graph()
		return {
			"success": true,
			"errors": [],
			"warnings": [],
			"graph_restored": false,
		}
	var load_result := load_snapshot(state.get("snapshot", {}) as Dictionary)
	if not bool(load_result.get("success", false)):
		push_error("RegionGraphRuntimeService could not restore snapshot: %s" % str(load_result.get("errors", [])))
		return load_result
	var saved_location_id := str(state.get("current_location_id", ""))
	if saved_location_id.is_empty():
		return _fail("RegionGraphRuntimeService save state is missing current_location_id.", {})
	if not _locations_by_id.has(saved_location_id):
		return _fail("RegionGraphRuntimeService save state references unknown current_location_id: %s" % saved_location_id, {
			"current_location_id": saved_location_id,
		})
	current_location_id = saved_location_id
	GameState.set_scene_context(current_location_id, current_location_id)
	return {
		"success": true,
		"errors": [],
		"warnings": [],
		"graph_restored": true,
		"current_location_id": current_location_id,
	}


func _edge_for_traversal(edge: Dictionary, traversal_from_location_id: String, traversal_to_location_id: String, reverse_traversal: bool) -> Dictionary:
	var result := edge.duplicate(true)
	result["traversal_from_location_id"] = traversal_from_location_id
	result["traversal_to_location_id"] = traversal_to_location_id
	result["target_location_id"] = traversal_to_location_id
	result["reverse_traversal"] = reverse_traversal
	return result


func _fail(reason: String, summary: Dictionary) -> Dictionary:
	var failed_summary := summary.duplicate(true)
	failed_summary["success"] = false
	failed_summary["error"] = reason
	failed_summary["errors"] = [reason]
	last_travel_summary = failed_summary.duplicate(true)
	push_error(reason)
	region_travel_failed.emit(failed_summary.duplicate(true))
	return failed_summary

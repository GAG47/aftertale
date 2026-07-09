class_name LocationGraphRuntimeAdapter
extends RefCounted

signal location_changed(view: Dictionary)

const LocationGraphSnapshotValidatorScript := preload("res://scripts/systems/regions/location_graph_snapshot_validator.gd")

var _snapshot: Dictionary = {}
var _locations_by_id: Dictionary = {}
var _edges_by_location_id: Dictionary = {}
var current_location_id: String = ""
var _loaded := false


func load_snapshot(snapshot_value: Variant) -> Dictionary:
	reset()
	if not (snapshot_value is Dictionary):
		return _failure("validate_snapshot", ["LocationGraphRuntimeAdapter requires a Dictionary snapshot"])
	var snapshot: Dictionary = snapshot_value as Dictionary
	var validator: RefCounted = LocationGraphSnapshotValidatorScript.new()
	var validation_errors: Array[String] = validator.validate(snapshot)
	if not validation_errors.is_empty():
		return _failure("validate_snapshot", validation_errors)
	var nodes: Array = snapshot.get("location_nodes", []) as Array
	if nodes.is_empty():
		return _failure("build_location_index", ["LocationGraphSnapshot.location_nodes must not be empty for Runtime"])
	var locations_by_id: Dictionary = {}
	for index in range(nodes.size()):
		if not (nodes[index] is Dictionary):
			return _failure("build_location_index", ["LocationGraphSnapshot.location_nodes[%d] must be an object" % index])
		var node: Dictionary = nodes[index] as Dictionary
		var location_id := str(node.get("location_id", ""))
		if location_id.is_empty():
			return _failure("build_location_index", ["LocationGraphSnapshot.location_nodes[%d].location_id is missing" % index])
		if locations_by_id.has(location_id):
			return _failure("build_location_index", ["LocationGraphSnapshot contains duplicate location_id: %s" % location_id])
		locations_by_id[location_id] = node.duplicate(true)
	var edges_by_location_id: Dictionary = {}
	for location_id_value in locations_by_id.keys():
		edges_by_location_id[str(location_id_value)] = []
	var edges: Array = snapshot.get("edge_contracts", []) as Array
	for index in range(edges.size()):
		if not (edges[index] is Dictionary):
			return _failure("build_edge_index", ["LocationGraphSnapshot.edge_contracts[%d] must be an object" % index])
		var edge: Dictionary = edges[index] as Dictionary
		var edge_id := str(edge.get("edge_id", ""))
		var from_location_id := str(edge.get("from_location_id", ""))
		var to_location_id := str(edge.get("to_location_id", ""))
		if not locations_by_id.has(from_location_id):
			return _failure("build_edge_index", ["EdgeContract references unknown from_location_id: %s (%s)" % [from_location_id, edge_id]])
		if not locations_by_id.has(to_location_id):
			return _failure("build_edge_index", ["EdgeContract references unknown to_location_id: %s (%s)" % [to_location_id, edge_id]])
		(edges_by_location_id.get(from_location_id, []) as Array).append(
			_runtime_edge_view(edge, to_location_id, locations_by_id, false)
		)
		if bool(edge.get("bidirectional", false)):
			(edges_by_location_id.get(to_location_id, []) as Array).append(
				_runtime_edge_view(edge, from_location_id, locations_by_id, true)
			)
	for location_id_value in edges_by_location_id.keys():
		var location_id := str(location_id_value)
		var neighbor_views: Array = edges_by_location_id.get(location_id, []) as Array
		neighbor_views.sort_custom(_sort_neighbor_views)
		edges_by_location_id[location_id] = neighbor_views
	var location_ids: Array[String] = []
	for location_id_value in locations_by_id.keys():
		location_ids.append(str(location_id_value))
	location_ids.sort()
	if location_ids.is_empty():
		return _failure("select_start_location", ["Runtime could not select a current location"])
	_snapshot = snapshot.duplicate(true)
	_locations_by_id = locations_by_id
	_edges_by_location_id = edges_by_location_id
	current_location_id = location_ids[0]
	_loaded = true
	return {
		"success": true,
		"errors": [],
		"warnings": [],
		"graph_id": str(_snapshot.get("graph_id", "")),
		"snapshot_id": str(_snapshot.get("snapshot_id", "")),
		"current_location_id": current_location_id,
		"location_count": _locations_by_id.size(),
		"edge_contract_count": edges.size(),
	}


func reset() -> void:
	_snapshot.clear()
	_locations_by_id.clear()
	_edges_by_location_id.clear()
	current_location_id = ""
	_loaded = false


func is_loaded() -> bool:
	return _loaded


func has_location(location_id: String) -> bool:
	return _loaded and _locations_by_id.has(location_id)


func get_location_count() -> int:
	return _locations_by_id.size() if _loaded else 0


func get_indexed_neighbor_count(location_id: String) -> int:
	if not _loaded or not _edges_by_location_id.has(location_id):
		return 0
	return (_edges_by_location_id.get(location_id, []) as Array).size()


func get_neighbors_for_location(location_id: String) -> Dictionary:
	if not _loaded:
		return _failure("get_neighbors", ["LocationGraphRuntimeAdapter has not loaded a snapshot"])
	if not _locations_by_id.has(location_id):
		return _failure("get_neighbors", ["Runtime location does not exist: %s" % location_id])
	return {
		"success": true,
		"errors": [],
		"warnings": [],
		"location_id": location_id,
		"neighbors": (_edges_by_location_id.get(location_id, []) as Array).duplicate(true),
	}


func get_current_location_view() -> Dictionary:
	if not _loaded:
		return _failure("get_current_location_view", ["LocationGraphRuntimeAdapter has not loaded a snapshot"])
	if not _locations_by_id.has(current_location_id):
		return _failure("get_current_location_view", ["Runtime current_location_id does not exist: %s" % current_location_id])
	var location: Dictionary = _locations_by_id.get(current_location_id, {}) as Dictionary
	var neighbors_result := get_neighbors_for_location(current_location_id)
	if not bool(neighbors_result.get("success", false)):
		return neighbors_result
	return {
		"success": true,
		"errors": [],
		"warnings": [],
		"view": {
			"graph_id": str(_snapshot.get("graph_id", "")),
			"snapshot_id": str(_snapshot.get("snapshot_id", "")),
			"current_location_id": current_location_id,
			"current_location_name": _location_name(location),
			"current_location_type": str(location.get("location_type", "")),
			"current_source_role_type": str(location.get("source_role_type", "")),
			"current_source_role_slug": str(location.get("source_role_slug", "")),
			"current_location_tags": (location.get("node_tags", []) as Array).duplicate(),
			"neighbors": neighbors_result.get("neighbors", []),
		},
	}


func travel_to_location(target_location_id: String) -> Dictionary:
	if not _loaded:
		return _failure("travel", ["LocationGraphRuntimeAdapter has not loaded a snapshot"])
	if not _locations_by_id.has(current_location_id):
		return _failure("travel", ["Runtime current_location_id does not exist: %s" % current_location_id])
	var selected_edge: Dictionary = {}
	for edge_value in (_edges_by_location_id.get(current_location_id, []) as Array):
		var edge_view: Dictionary = edge_value as Dictionary
		if str(edge_view.get("target_location_id", "")) == target_location_id:
			selected_edge = edge_view
			break
	if selected_edge.is_empty():
		return _failure("travel", ["Target location is not adjacent to current location: %s -> %s" % [
			current_location_id,
			target_location_id,
		]])
	var access_rule := str(selected_edge.get("access_rule", ""))
	if access_rule != "always":
		return _failure("travel", ["Runtime adapter does not support access_rule: %s" % access_rule])
	var previous_location_id := current_location_id
	current_location_id = target_location_id
	var view_result := get_current_location_view()
	if not bool(view_result.get("success", false)):
		current_location_id = previous_location_id
		return view_result
	var view: Dictionary = view_result.get("view", {}) as Dictionary
	location_changed.emit(view.duplicate(true))
	return {
		"success": true,
		"errors": [],
		"warnings": [],
		"edge_id": str(selected_edge.get("edge_id", "")),
		"previous_location_id": previous_location_id,
		"current_location_id": current_location_id,
		"view": view,
	}


func get_snapshot_copy() -> Dictionary:
	return _snapshot.duplicate(true) if _loaded else {}


func _runtime_edge_view(edge: Dictionary, target_location_id: String, locations_by_id: Dictionary, reverse_traversal: bool) -> Dictionary:
	var target: Dictionary = locations_by_id.get(target_location_id, {}) as Dictionary
	var target_name := _location_name(target)
	var edge_type := str(edge.get("edge_type", ""))
	return {
		"edge_id": str(edge.get("edge_id", "")),
		"from_location_id": str(edge.get("from_location_id", "")),
		"to_location_id": str(edge.get("to_location_id", "")),
		"target_location_id": target_location_id,
		"target_location_name": target_name,
		"target_location_type": str(target.get("location_type", "")),
		"target_location_tags": (target.get("node_tags", []) as Array).duplicate(),
		"edge_type": edge_type,
		"bidirectional": bool(edge.get("bidirectional", false)),
		"reverse_traversal": reverse_traversal,
		"access_rule": str(edge.get("access_rule", "")),
		"traversal_tags": (edge.get("traversal_tags", []) as Array).duplicate(),
		"source_rule_id": str(edge.get("source_rule_id", "")),
		"display_label": "%s [%s]" % [target_name, edge_type],
	}


static func _location_name(location: Dictionary) -> String:
	for key in ["source_role_slug", "node_slug", "location_type", "location_id"]:
		var value := str(location.get(key, ""))
		if not value.is_empty():
			return value
	return "unknown_location"


static func _sort_neighbor_views(first: Dictionary, second: Dictionary) -> bool:
	var first_key := "%s::%s" % [str(first.get("target_location_id", "")), str(first.get("edge_id", ""))]
	var second_key := "%s::%s" % [str(second.get("target_location_id", "")), str(second.get("edge_id", ""))]
	return first_key < second_key


static func _failure(stage: String, errors: Array[String]) -> Dictionary:
	return {
		"success": false,
		"stage": stage,
		"errors": errors.duplicate(),
		"warnings": [],
	}

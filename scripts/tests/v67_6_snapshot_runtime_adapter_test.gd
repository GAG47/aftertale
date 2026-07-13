extends SceneTree

const CanonicalDataSerializerScript := preload("res://scripts/systems/regions/canonical_data_serializer.gd")
const LocationGraphRuntimeAdapterScript := preload("res://scripts/systems/regions/location_graph_runtime_adapter.gd")
const RegionLocationGraphCompilerScript := preload("res://scripts/systems/regions/region_location_graph_compiler.gd")
const RUNTIME_SCENE := preload("res://scenes/locations/snapshot_runtime_location.tscn")

const TOWN_REGION_INPUT_PATH := "res://data/regions/frontier_town_region.json"
const FOREST_REGION_INPUT_PATH := "res://data/regions/frontier_forest_region.json"
const EDGE_PROFILE_PATH := "res://data/location_graph/edge_contract_profiles/default.json"
const GRAPH_ID := "graph.frontier.runtime_test.lg_0001"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var snapshot_result := _compile_snapshot()
	if not bool(snapshot_result.get("success", false)):
		_fail("v67.6 snapshot setup failed: %s" % str(snapshot_result.get("errors", [])))
		return
	var snapshot: Dictionary = snapshot_result.get("location_graph_snapshot", {}) as Dictionary
	if not _assert_valid_load_and_indexes(snapshot):
		return
	if not _assert_view_and_travel(snapshot):
		return
	if not _assert_invalid_snapshot_errors(snapshot):
		return
	if not _assert_empty_nodes_reach_adapter_defense(snapshot):
		return
	if not _assert_repeated_load_resets_state(snapshot):
		return
	if not _assert_directed_edge_index(snapshot):
		return
	if not _assert_placeholder_scene_binding(snapshot):
		return
	print("v67.6 snapshot runtime adapter test passed")
	quit(0)


func _assert_valid_load_and_indexes(snapshot: Dictionary) -> bool:
	var adapter: RefCounted = LocationGraphRuntimeAdapterScript.new()
	var load_result: Dictionary = adapter.load_snapshot(snapshot)
	if not bool(load_result.get("success", false)):
		return _fail("v67.6 adapter could not load a valid snapshot: %s" % str(load_result.get("errors", [])))
	var nodes: Array = snapshot.get("location_nodes", []) as Array
	if adapter.get_location_count() != nodes.size():
		return _fail("v67.6 locations_by_id has the wrong size")
	var location_ids: Array[String] = []
	for node_value in nodes:
		location_ids.append(str((node_value as Dictionary).get("location_id", "")))
	location_ids.sort()
	if str(adapter.current_location_id) != location_ids[0]:
		return _fail("v67.6 start location is not the stable first location_id")
	var expected_counts: Dictionary = {}
	for location_id in location_ids:
		expected_counts[location_id] = 0
	for edge_value in (snapshot.get("edge_contracts", []) as Array):
		var edge: Dictionary = edge_value as Dictionary
		var from_id := str(edge.get("from_location_id", ""))
		var to_id := str(edge.get("to_location_id", ""))
		expected_counts[from_id] = int(expected_counts.get(from_id, 0)) + 1
		if bool(edge.get("bidirectional", false)):
			expected_counts[to_id] = int(expected_counts.get(to_id, 0)) + 1
	for location_id in location_ids:
		if adapter.get_indexed_neighbor_count(location_id) != int(expected_counts.get(location_id, 0)):
			return _fail("v67.6 edges_by_location_id has the wrong size for %s" % location_id)
	return true


func _assert_view_and_travel(snapshot: Dictionary) -> bool:
	var snapshot_before := CanonicalDataSerializerScript.serialize(snapshot)
	var adapter: RefCounted = LocationGraphRuntimeAdapterScript.new()
	if not bool(adapter.load_snapshot(snapshot).get("success", false)):
		return _fail("v67.6 travel setup failed")
	var initial_location_id := str(adapter.current_location_id)
	var view_result: Dictionary = adapter.get_current_location_view()
	if not bool(view_result.get("success", false)):
		return _fail("v67.6 current location view failed")
	var view: Dictionary = view_result.get("view", {}) as Dictionary
	if str(view.get("current_location_id", "")) != initial_location_id:
		return _fail("v67.6 current location view has the wrong location")
	if str(view.get("current_source_archetype_id", "")).is_empty() or str(view.get("current_source_form_id", "")).is_empty():
		return _fail("v67.8 runtime view dropped archetype/form identity")
	if not (view.get("current_gameplay_affordances", null) is Array) or not (view.get("current_narrative_affordances", null) is Array):
		return _fail("v67.8 runtime view dropped location affordances")
	var neighbors: Array = view.get("neighbors", []) as Array
	if neighbors.is_empty():
		return _fail("v67.6 initial location has no indexed neighbors")
	var non_neighbor := _find_non_neighbor_id(snapshot, initial_location_id, neighbors)
	if non_neighbor.is_empty():
		return _fail("v67.6 non-adjacent travel test could not find a candidate")
	var rejected: Dictionary = adapter.travel_to_location(non_neighbor)
	if bool(rejected.get("success", false)):
		return _fail("v67.6 adapter allowed travel to a non-adjacent location")
	if str(adapter.current_location_id) != initial_location_id:
		return _fail("v67.6 rejected travel changed current_location_id")
	var target_id := str((neighbors[0] as Dictionary).get("target_location_id", ""))
	var travel_result: Dictionary = adapter.travel_to_location(target_id)
	if not bool(travel_result.get("success", false)):
		return _fail("v67.6 adjacent travel failed: %s" % str(travel_result.get("errors", [])))
	if str(adapter.current_location_id) != target_id:
		return _fail("v67.6 adjacent travel did not update current_location_id")
	if CanonicalDataSerializerScript.serialize(snapshot) != snapshot_before:
		return _fail("v67.6 travel modified the caller's Snapshot")
	if CanonicalDataSerializerScript.serialize(adapter.get_snapshot_copy()) != snapshot_before:
		return _fail("v67.6 travel modified the Adapter's Snapshot copy")
	return true


func _assert_invalid_snapshot_errors(snapshot: Dictionary) -> bool:
	var adapter: RefCounted = LocationGraphRuntimeAdapterScript.new()
	var wrong_type: Dictionary = adapter.load_snapshot("not_a_snapshot")
	if bool(wrong_type.get("success", false)) or str(wrong_type.get("stage", "")) != "validate_snapshot":
		return _fail("v67.6 adapter did not reject a non-Dictionary snapshot")
	var invalid_edge := snapshot.duplicate(true)
	var edges: Array = invalid_edge.get("edge_contracts", []) as Array
	var edge: Dictionary = edges[0] as Dictionary
	edge["to_location_id"] = "loc.frontier.unknown_region.unknown.unknown.ln_9999"
	edges[0] = edge
	invalid_edge["edge_contracts"] = edges
	var edge_result: Dictionary = adapter.load_snapshot(invalid_edge)
	if bool(edge_result.get("success", false)):
		return _fail("v67.6 adapter accepted an invalid edge reference")
	if not str(edge_result.get("errors", [])).contains("unknown node"):
		return _fail("v67.6 adapter did not propagate SnapshotValidator edge errors: %s" % str(edge_result.get("errors", [])))
	if bool(adapter.get_current_location_view().get("success", false)):
		return _fail("v67.6 unloaded Adapter returned a current location view")
	if bool(adapter.travel_to_location("anything").get("success", false)):
		return _fail("v67.6 unloaded Adapter allowed travel")
	return true


func _assert_empty_nodes_reach_adapter_defense(snapshot: Dictionary) -> bool:
	var empty_snapshot := snapshot.duplicate(true)
	empty_snapshot["location_nodes"] = []
	empty_snapshot["edge_contracts"] = []
	empty_snapshot["node_sources"] = []
	_recalculate_snapshot_identity(empty_snapshot)
	var adapter: RefCounted = LocationGraphRuntimeAdapterScript.new()
	var result: Dictionary = adapter.load_snapshot(empty_snapshot)
	if bool(result.get("success", false)):
		return _fail("v67.6 adapter accepted an empty location node set")
	if str(result.get("stage", "")) != "build_location_index":
		return _fail("v67.6 empty node test did not reach Adapter defense: %s" % str(result))
	return true


func _assert_repeated_load_resets_state(snapshot: Dictionary) -> bool:
	var adapter: RefCounted = LocationGraphRuntimeAdapterScript.new()
	if not bool(adapter.load_snapshot(snapshot).get("success", false)):
		return _fail("v67.6 repeated-load setup failed")
	var stable_start := str(adapter.current_location_id)
	var view: Dictionary = (adapter.get_current_location_view().get("view", {}) as Dictionary)
	var neighbors: Array = view.get("neighbors", []) as Array
	if neighbors.is_empty():
		return _fail("v67.6 repeated-load setup has no neighbor")
	if not bool(adapter.travel_to_location(str((neighbors[0] as Dictionary).get("target_location_id", ""))).get("success", false)):
		return _fail("v67.6 repeated-load travel setup failed")
	if str(adapter.current_location_id) == stable_start:
		return _fail("v67.6 repeated-load setup did not leave the start location")
	if not bool(adapter.load_snapshot(snapshot).get("success", false)):
		return _fail("v67.6 repeated valid load failed")
	if str(adapter.current_location_id) != stable_start:
		return _fail("v67.6 repeated load did not reset current_location_id")
	var failed_reload: Dictionary = adapter.load_snapshot("invalid")
	if bool(failed_reload.get("success", false)):
		return _fail("v67.6 invalid reload unexpectedly succeeded")
	if adapter.is_loaded() or not str(adapter.current_location_id).is_empty() or adapter.get_location_count() != 0:
		return _fail("v67.6 failed reload retained stale Runtime state")
	return true


func _assert_directed_edge_index(snapshot: Dictionary) -> bool:
	var directed_snapshot := snapshot.duplicate(true)
	var edges: Array = directed_snapshot.get("edge_contracts", []) as Array
	var directed_edge: Dictionary = edges[0] as Dictionary
	directed_edge["bidirectional"] = false
	edges[0] = directed_edge
	directed_snapshot["edge_contracts"] = edges
	_recalculate_snapshot_identity(directed_snapshot)
	var adapter: RefCounted = LocationGraphRuntimeAdapterScript.new()
	var load_result: Dictionary = adapter.load_snapshot(directed_snapshot)
	if not bool(load_result.get("success", false)):
		return _fail("v67.6 directed edge setup failed: %s" % str(load_result.get("errors", [])))
	var edge_id := str(directed_edge.get("edge_id", ""))
	var from_id := str(directed_edge.get("from_location_id", ""))
	var to_id := str(directed_edge.get("to_location_id", ""))
	var from_neighbors: Dictionary = adapter.get_neighbors_for_location(from_id)
	var to_neighbors: Dictionary = adapter.get_neighbors_for_location(to_id)
	if not _neighbors_contain_edge_to(from_neighbors.get("neighbors", []) as Array, edge_id, to_id):
		return _fail("v67.6 directed edge is missing its forward traversal")
	if _neighbors_contain_edge_to(to_neighbors.get("neighbors", []) as Array, edge_id, from_id):
		return _fail("v67.6 directed edge incorrectly created reverse traversal")
	return true


func _assert_placeholder_scene_binding(snapshot: Dictionary) -> bool:
	var adapter: RefCounted = LocationGraphRuntimeAdapterScript.new()
	if not bool(adapter.load_snapshot(snapshot).get("success", false)):
		return _fail("v67.6 placeholder scene setup failed")
	var runtime_scene := RUNTIME_SCENE.instantiate() as Control
	if runtime_scene == null:
		return _fail("v67.6 placeholder scene could not be instantiated")
	root.add_child(runtime_scene)
	var bind_result: Dictionary = runtime_scene.bind_adapter(adapter)
	if not bool(bind_result.get("success", false)):
		runtime_scene.queue_free()
		return _fail("v67.6 placeholder scene could not bind Adapter")
	if runtime_scene.get_displayed_current_location_id() != str(adapter.current_location_id):
		runtime_scene.queue_free()
		return _fail("v67.6 placeholder scene displays the wrong current location")
	var view: Dictionary = adapter.get_current_location_view().get("view", {}) as Dictionary
	if runtime_scene.get_neighbor_button_count() != (view.get("neighbors", []) as Array).size():
		runtime_scene.queue_free()
		return _fail("v67.6 placeholder scene displays the wrong neighbor count")
	var initial_location_id := str(adapter.current_location_id)
	var neighbors_container := runtime_scene.get_node("RuntimePanel/MarginContainer/Content/NeighborsScroll/Neighbors")
	var first_button: Button
	for child in neighbors_container.get_children():
		if child is Button and not (child as Button).disabled:
			first_button = child as Button
			break
	if first_button == null:
		runtime_scene.queue_free()
		return _fail("v67.6 placeholder scene has no usable neighbor button")
	first_button.pressed.emit()
	if str(adapter.current_location_id) == initial_location_id:
		runtime_scene.queue_free()
		return _fail("v67.6 placeholder neighbor button did not travel")
	if runtime_scene.get_displayed_current_location_id() != str(adapter.current_location_id):
		runtime_scene.queue_free()
		return _fail("v67.6 placeholder scene did not refresh after button travel")
	runtime_scene.queue_free()
	return true


func _compile_snapshot() -> Dictionary:
	var compiler: RefCounted = RegionLocationGraphCompilerScript.new()
	return compiler.compile_location_graph_snapshot_result([
		_load_json(TOWN_REGION_INPUT_PATH),
		_load_json(FOREST_REGION_INPUT_PATH),
	], EDGE_PROFILE_PATH, GRAPH_ID)


func _recalculate_snapshot_identity(snapshot: Dictionary) -> void:
	snapshot["content_hash"] = ""
	snapshot["snapshot_id"] = ""
	snapshot["content_hash"] = CanonicalDataSerializerScript.snapshot_content_hash(snapshot)
	snapshot["snapshot_id"] = CanonicalDataSerializerScript.snapshot_id(
		str(snapshot.get("graph_id", "")),
		str(snapshot.get("content_hash", ""))
	)


func _find_non_neighbor_id(snapshot: Dictionary, current_id: String, neighbors: Array) -> String:
	var adjacent: Dictionary = {}
	for neighbor_value in neighbors:
		adjacent[str((neighbor_value as Dictionary).get("target_location_id", ""))] = true
	for node_value in (snapshot.get("location_nodes", []) as Array):
		var location_id := str((node_value as Dictionary).get("location_id", ""))
		if location_id != current_id and not adjacent.has(location_id):
			return location_id
	return ""


func _neighbors_contain_edge_to(neighbors: Array, edge_id: String, target_id: String) -> bool:
	for neighbor_value in neighbors:
		var neighbor: Dictionary = neighbor_value as Dictionary
		if str(neighbor.get("edge_id", "")) == edge_id and str(neighbor.get("target_location_id", "")) == target_id:
			return true
	return false


func _load_json(resource_path: String) -> Dictionary:
	var file := FileAccess.open(resource_path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed as Dictionary if parsed is Dictionary else {}


func _fail(message: String) -> bool:
	push_error(message)
	quit(1)
	return false

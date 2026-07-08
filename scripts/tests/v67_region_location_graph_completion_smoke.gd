extends Node

const RegionLocationGraphCompilerScript := preload("res://scripts/systems/regions/region_location_graph_compiler.gd")
const RegionLocationGraphValidatorScript := preload("res://scripts/systems/regions/region_location_graph_validator.gd")
const RegionGraphSnapshotStoreScript := preload("res://scripts/systems/regions/region_graph_snapshot_store.gd")

const TOWN_REGION_INPUT_PATH := "res://data/regions/frontier_town_region.json"
const FOREST_REGION_INPUT_PATH := "res://data/regions/frontier_forest_region.json"
const SMOKE_SNAPSHOT_PATH := "user://region_graph_snapshots/v67_completion_smoke.json"
const SMOKE_SAVE_PATH := "user://saves/v67_region_graph_only_smoke.json"


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	if not _assert_compile_and_validate_multiple_region_types():
		return
	if not _assert_snapshot_save_load():
		return
	if not _assert_runtime_adapter_start_and_travel():
		return
	if not _assert_graph_only_save_load():
		return
	if not _assert_invalid_graphs_fail():
		return
	print("v67 Region Location Graph completion smoke test passed")
	get_tree().quit(0)


func _assert_compile_and_validate_multiple_region_types() -> bool:
	var compiler: RefCounted = RegionLocationGraphCompilerScript.new()
	for path in [TOWN_REGION_INPUT_PATH, FOREST_REGION_INPUT_PATH]:
		var result: Dictionary = compiler.compile_to_location_graph_result(_load_json(path))
		if not bool(result.get("success", false)):
			_fail("v67 graph compile failed for %s: %s" % [path, str(result.get("errors", []))])
			return false
		var graph: Dictionary = result.get("location_graph", {}) as Dictionary
		if not _assert_graph_shape(graph):
			return false
	return true


func _assert_snapshot_save_load() -> bool:
	var graph := _town_graph()
	if graph.is_empty():
		return false
	var store: RefCounted = RegionGraphSnapshotStoreScript.new()
	var save_result: Dictionary = store.save_snapshot_to_path(graph, SMOKE_SNAPSHOT_PATH)
	if not bool(save_result.get("success", false)):
		_fail("v67 graph snapshot save failed: %s" % str(save_result.get("errors", [])))
		return false
	var load_result: Dictionary = store.load_snapshot_from_path(SMOKE_SNAPSHOT_PATH)
	if not bool(load_result.get("success", false)):
		_fail("v67 graph snapshot load failed: %s" % str(load_result.get("errors", [])))
		return false
	var loaded: Dictionary = load_result.get("snapshot", {}) as Dictionary
	if _graph_signature(graph) != _graph_signature(loaded):
		_fail("v67 graph snapshot changed across save/load")
		return false
	return true


func _assert_runtime_adapter_start_and_travel() -> bool:
	var graph := _town_graph()
	if graph.is_empty():
		return false
	RegionGraphRuntimeService.reset_graph()
	var load_result: Dictionary = RegionGraphRuntimeService.load_snapshot(graph)
	if not bool(load_result.get("success", false)):
		_fail("v67 runtime adapter load failed: %s" % str(load_result.get("errors", [])))
		return false
	var start_result: Dictionary = RegionGraphRuntimeService.start_graph(false)
	if not bool(start_result.get("success", false)):
		_fail("v67 runtime adapter start failed: %s" % str(start_result.get("errors", [])))
		return false
	var start_location_id := str(graph.get("start_location_id", ""))
	if RegionGraphRuntimeService.current_location_id != start_location_id:
		_fail("v67 runtime adapter did not enter start location")
		return false
	var edges := RegionGraphRuntimeService.get_edges_from(start_location_id)
	if edges.is_empty():
		_fail("v67 runtime adapter start location has no edges")
		return false
	var adjacent := RegionGraphRuntimeService.get_adjacent_locations(start_location_id)
	if adjacent.is_empty():
		_fail("v67 runtime adapter did not expose adjacent locations")
		return false
	var travel_result: Dictionary = RegionGraphRuntimeService.travel_by_edge_id(str((edges[0] as Dictionary).get("edge_id", "")), false)
	if not bool(travel_result.get("success", false)):
		_fail("v67 runtime adapter travel failed: %s" % str(travel_result.get("errors", [])))
		return false
	if str(travel_result.get("target_location_id", "")).is_empty() or str(travel_result.get("target_location_id", "")) == start_location_id:
		_fail("v67 runtime adapter did not move to a different location")
		return false
	var enter_result: Dictionary = RegionGraphRuntimeService.enter_location(start_location_id, false)
	if not bool(enter_result.get("success", false)):
		_fail("v67 runtime adapter direct enter_location failed: %s" % str(enter_result.get("errors", [])))
		return false
	var reference_result: Dictionary = RegionGraphRuntimeService.validate_location_reference(start_location_id, "v67_smoke.player_location")
	if not bool(reference_result.get("success", false)):
		_fail("v67 runtime adapter rejected a valid snapshot location reference")
		return false
	return true


func _assert_graph_only_save_load() -> bool:
	var graph := _town_graph()
	if graph.is_empty():
		return false
	RegionGraphRuntimeService.reset_graph()
	var load_result: Dictionary = RegionGraphRuntimeService.load_snapshot(graph)
	if not bool(load_result.get("success", false)):
		_fail("v67 graph-only save setup could not load graph: %s" % str(load_result.get("errors", [])))
		return false
	GameState.start_new_session("v67_region_graph_only_smoke")
	var start_result: Dictionary = RegionGraphRuntimeService.start_graph(true)
	if not bool(start_result.get("success", false)):
		_fail("v67 graph-only save setup could not start graph: %s" % str(start_result.get("errors", [])))
		return false
	var saved_location_id := RegionGraphRuntimeService.current_location_id
	var save_result: ActionResult = SaveManager.save_game(SMOKE_SAVE_PATH)
	if save_result == null or not save_result.success:
		_fail("v67 graph-only SaveManager.save_game failed")
		return false
	RegionGraphRuntimeService.reset_graph()
	GameState.set_scene_context("", "")
	var load_save_result: ActionResult = SaveManager.load_game(SMOKE_SAVE_PATH)
	if load_save_result == null or not load_save_result.success:
		_fail("v67 graph-only SaveManager.load_game failed")
		return false
	if RegionGraphRuntimeService.current_location_id != saved_location_id:
		_fail("v67 graph-only load did not restore current_location_id")
		return false
	if GameState.current_location_id != saved_location_id:
		_fail("v67 graph-only load did not restore GameState.current_location_id")
		return false
	return true


func _assert_invalid_graphs_fail() -> bool:
	var validator: RefCounted = RegionLocationGraphValidatorScript.new()
	var missing_target := _town_graph()
	if missing_target.is_empty():
		return false
	var edges: Array = missing_target.get("edges", []) as Array
	var first_edge: Dictionary = edges[0] as Dictionary
	first_edge["to_location_id"] = "loc.missing.target"
	edges[0] = first_edge
	missing_target["edges"] = edges
	if validator.validate(missing_target).is_empty():
		_fail("v67 validator accepted edge pointing at missing location")
		return false
	var scene_field := _town_graph()
	var locations: Array = scene_field.get("locations", []) as Array
	var first_location: Dictionary = locations[0] as Dictionary
	first_location["scene_path"] = "res://invalid_scene.tscn"
	locations[0] = first_location
	scene_field["locations"] = locations
	if validator.validate(scene_field).is_empty():
		_fail("v67 validator accepted scene field in structural graph")
		return false
	var illegal_travel := _town_graph()
	var travel_edges: Array = illegal_travel.get("edges", []) as Array
	var illegal_travel_edge: Dictionary = travel_edges[0] as Dictionary
	illegal_travel_edge["travel_type"] = "teleport"
	travel_edges[0] = illegal_travel_edge
	illegal_travel["edges"] = travel_edges
	if validator.validate(illegal_travel).is_empty():
		_fail("v67 validator accepted illegal travel_type")
		return false
	var illegal_access := _town_graph()
	var access_edges: Array = illegal_access.get("edges", []) as Array
	var illegal_access_edge: Dictionary = access_edges[0] as Dictionary
	illegal_access_edge["access_rule"] = "silent_default"
	access_edges[0] = illegal_access_edge
	illegal_access["edges"] = access_edges
	if validator.validate(illegal_access).is_empty():
		_fail("v67 validator accepted illegal access_rule")
		return false
	return true


func _assert_graph_shape(graph: Dictionary) -> bool:
	var validator: RefCounted = RegionLocationGraphValidatorScript.new()
	var errors: Array[String] = validator.validate(graph)
	if not errors.is_empty():
		_fail("v67 graph validation failed: %s" % str(errors))
		return false
	if str(graph.get("stage", "")) != "location_graph":
		_fail("v67 graph has wrong stage: %s" % str(graph.get("stage", "")))
		return false
	for key in ["locations", "edges", "selected_roles", "start_location_id"]:
		if not graph.has(key):
			_fail("v67 graph missing key: %s" % key)
			return false
	return true


func _town_graph() -> Dictionary:
	var compiler: RefCounted = RegionLocationGraphCompilerScript.new()
	var result: Dictionary = compiler.compile_to_location_graph_result(_load_json(TOWN_REGION_INPUT_PATH))
	if not bool(result.get("success", false)):
		_fail("v67 could not compile town graph: %s" % str(result.get("errors", [])))
		return {}
	return result.get("location_graph", {}) as Dictionary


func _graph_signature(graph: Dictionary) -> String:
	var parts: Array[String] = [
		str(graph.get("region_id", "")),
		str(graph.get("start_location_id", "")),
	]
	for location_value in (graph.get("locations", []) as Array):
		var location: Dictionary = location_value as Dictionary
		parts.append("%s:%s:%s" % [
			str(location.get("location_id", "")),
			str(location.get("location_type", "")),
			str(location.get("role_id", "")),
		])
	for edge_value in (graph.get("edges", []) as Array):
		var edge: Dictionary = edge_value as Dictionary
		parts.append("%s:%s:%s:%s" % [
			str(edge.get("edge_id", "")),
			str(edge.get("from_location_id", "")),
			str(edge.get("to_location_id", "")),
			str(edge.get("travel_type", "")),
		])
	parts.sort()
	return "|".join(parts)


func _load_json(resource_path: String) -> Dictionary:
	var file := FileAccess.open(resource_path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		return parsed as Dictionary
	return {}


func _fail(message: String) -> void:
	push_error(message)
	get_tree().quit(1)

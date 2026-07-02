extends Node

signal world_loaded(world_id: String)
signal transition_completed(summary: Dictionary)
signal transition_failed(summary: Dictionary)

const WorldLocationGraphScript := preload("res://scripts/systems/world/world_location_graph.gd")
const WorldRuntimeStateScript := preload("res://scripts/systems/world/world_runtime_state.gd")
const WorldLocationRegistryScript := preload("res://scripts/systems/world/world_location_registry.gd")

var _graph
var _runtime
var _registry
var _world_resource_path: String = ""
var _world_data: Dictionary = {}
var last_transition_summary: Dictionary = {}


func _ready() -> void:
	_reset_instances()


func load_world(resource_path: String) -> Dictionary:
	var data: Dictionary = DefinitionLoader.load_json_resource(resource_path, "world definition")
	if data.is_empty():
		return _fail("WorldTransitionService could not load world: %s" % resource_path, {})
	var result := load_world_from_data(data, resource_path)
	return result


func load_world_from_data(data: Dictionary, resource_path: String = "") -> Dictionary:
	_reset_instances()
	_world_resource_path = resource_path
	_world_data = data.duplicate(true)
	var errors: Array[String] = _graph.configure(data)
	if not errors.is_empty():
		return _fail("World graph validation failed: %s" % str(errors), { "warnings": errors })
	_runtime.configure(_graph.world_id, _graph.start_location_id)
	world_loaded.emit(_graph.world_id)
	return {
		"success": true,
		"world_id": _graph.world_id,
		"location_count": _graph.location_count(),
	}


func start_world(load_scene: bool = true, spawn_id: String = "") -> Dictionary:
	if not is_world_active():
		return _fail("No active world is loaded.", {})
	var target_spawn_id := spawn_id
	if target_spawn_id.is_empty():
		target_spawn_id = _graph.start_spawn_id
	if target_spawn_id.is_empty():
		return _fail("World start requires an explicit start_spawn_id.", {
			"target_location_id": _graph.start_location_id,
		})
	return _enter_location(_graph.start_location_id, target_spawn_id, {
		"from_location_id": "",
		"exit_id": "__start__",
	}, load_scene)


func transition_by_exit_data(exit_data: Dictionary, load_scene: bool = true) -> Dictionary:
	var exit_id := str(exit_data.get("world_exit_id", exit_data.get("exit_id", exit_data.get("id", ""))))
	return transition_by_exit_id(exit_id, load_scene)


func transition_by_exit_id(exit_id: String, load_scene: bool = true) -> Dictionary:
	if not is_world_active():
		return _fail("No active world is loaded.", { "exit_id": exit_id })
	var from_location_id := _current_location_id()
	if from_location_id.is_empty():
		return _fail("World has no current_location_id.", { "exit_id": exit_id })
	if exit_id.is_empty():
		return _fail("Exit id is empty.", { "from_location_id": from_location_id })
	var exit_spec: Dictionary = _graph.get_exit_spec(from_location_id, exit_id)
	if exit_spec.is_empty():
		return _fail("Unknown world exit: %s from %s" % [exit_id, from_location_id], {
			"from_location_id": from_location_id,
			"exit_id": exit_id,
		})
	if not bool(exit_spec.get("enabled", true)):
		return _fail("World exit is disabled: %s" % exit_id, {
			"from_location_id": from_location_id,
			"exit_id": exit_id,
		})
	var target_location_id := str(exit_spec.get("target_location_id", ""))
	var target_spawn_id := str(exit_spec.get("target_spawn_id", ""))
	return _enter_location(target_location_id, target_spawn_id, {
		"from_location_id": from_location_id,
		"exit_id": exit_id,
		"transition_type": str(exit_spec.get("transition_type", "walk")),
	}, load_scene)


func prepare_scene_load_for_location(location_id: String) -> Dictionary:
	if not is_world_active() or location_id.is_empty():
		return {}
	var resolved: Dictionary = _registry.resolve_location(_graph, _runtime, location_id)
	if not bool(resolved.get("success", false)):
		return {}
	var location_data: Dictionary = resolved.get("location_data", {}) as Dictionary
	if not location_data.is_empty():
		SceneLoader.set_pending_location_data(location_data)
	return {
		"scene_path": str(resolved.get("scene_path", "")),
		"location_id": location_id,
	}


func is_world_active() -> bool:
	return _graph != null and _runtime != null and not _graph.world_id.is_empty()


func get_world_id() -> String:
	return _graph.world_id if is_world_active() else ""


func get_current_location_id() -> String:
	return _runtime.current_location_id if _runtime != null else ""


func get_location_spec(location_id: String) -> Dictionary:
	if not is_world_active():
		return {}
	return _graph.get_location_spec(location_id)


func get_all_location_specs() -> Array[Dictionary]:
	if not is_world_active():
		return []
	return _graph.get_all_locations()


func get_all_edge_specs() -> Array[Dictionary]:
	if not is_world_active():
		return []
	return _graph.get_all_edges()


func get_region_map() -> Dictionary:
	if not is_world_active():
		return {}
	return _graph.get_region_map()


func get_region_map_view_data() -> Dictionary:
	if not is_world_active():
		return {}
	var current_location_id := get_current_location_id()
	return {
		"world_id": get_world_id(),
		"region_map": get_region_map(),
		"locations": get_all_location_specs(),
		"edges": get_all_edge_specs(),
		"current_location_id": current_location_id,
		"display_current_location_id": _region_map_display_location_id(current_location_id),
	}


func get_spawn_spec(location_id: String, spawn_id: String) -> Dictionary:
	if not is_world_active():
		return {}
	return _graph.get_spawn_spec(location_id, spawn_id)


func get_exit_spec(from_location_id: String, exit_id: String) -> Dictionary:
	if not is_world_active():
		return {}
	return _graph.get_exit_spec(from_location_id, exit_id)


func get_child_locations(parent_location_id: String) -> Array[Dictionary]:
	if not is_world_active():
		return []
	return _graph.get_child_locations(parent_location_id)


func get_edges_from(location_id: String) -> Array[Dictionary]:
	if not is_world_active():
		return []
	return _graph.get_edges_from(location_id)


func get_edges_to(location_id: String) -> Array[Dictionary]:
	if not is_world_active():
		return []
	return _graph.get_edges_to(location_id)


func get_parent_location_id(location_id: String) -> String:
	if not is_world_active():
		return ""
	return _graph.get_parent_location_id(location_id)


func is_child_location(location_id: String) -> bool:
	if not is_world_active():
		return false
	return _graph.is_child_location(location_id)


func get_world_debug_summary() -> Dictionary:
	if not is_world_active():
		return {}
	var summary: Dictionary = _graph.get_debug_summary()
	summary["current_location_id"] = get_current_location_id()
	return summary


func get_generation_count(location_id: String) -> int:
	if _runtime == null:
		return 0
	return _runtime.get_generation_count(location_id)


func get_registered_location_data(location_id: String) -> Dictionary:
	if _runtime == null:
		return {}
	return _runtime.get_location_data(location_id)


func get_save_state() -> Dictionary:
	if not is_world_active():
		return {}
	return {
		"world_resource_path": _world_resource_path,
		"world_data": _graph.to_dictionary(),
		"runtime": _runtime.get_save_state(),
	}


func apply_save_state(state: Dictionary) -> void:
	if state.is_empty():
		_reset_instances()
		return
	var data: Dictionary = state.get("world_data", {}) as Dictionary
	if data.is_empty():
		var resource_path := str(state.get("world_resource_path", ""))
		data = DefinitionLoader.load_json_resource(resource_path, "world definition")
	_world_resource_path = str(state.get("world_resource_path", ""))
	_world_data = data.duplicate(true)
	_reset_instances()
	var errors: Array[String] = _graph.configure(data)
	if not errors.is_empty():
		push_error("WorldTransitionService could not restore world graph: %s" % str(errors))
		return
	_runtime.apply_save_state(state.get("runtime", {}) as Dictionary)
	_registry.synchronize_graph_from_runtime(_graph, _runtime)


func reset_world() -> void:
	_world_resource_path = ""
	_world_data.clear()
	last_transition_summary.clear()
	_reset_instances()


func _enter_location(target_location_id: String, target_spawn_id: String, base_summary: Dictionary, load_scene: bool) -> Dictionary:
	var warnings: Array = []
	var summary := base_summary.duplicate(true)
	summary["target_location_id"] = target_location_id
	summary["target_spawn_id"] = target_spawn_id
	if target_location_id.is_empty():
		return _fail("Target location id is empty.", summary)
	var target_spec: Dictionary = _graph.get_location_spec(target_location_id)
	if target_spec.is_empty():
		return _fail("Unknown target location: %s" % target_location_id, summary)
	var spawn_spec: Dictionary = _graph.get_spawn_spec(target_location_id, target_spawn_id)
	if spawn_spec.is_empty():
		return _fail("Unknown target spawn: %s/%s" % [target_location_id, target_spawn_id], summary)
	var entrance_id := _entrance_id_for_spawn(spawn_spec)
	if entrance_id.is_empty():
		summary["warnings"] = warnings
		return _fail("Target spawn has no explicit entrance_id: %s/%s" % [target_location_id, target_spawn_id], summary)

	var resolved: Dictionary = _registry.resolve_location(_graph, _runtime, target_location_id)
	if not bool(resolved.get("success", false)):
		summary["warnings"] = resolved.get("warnings", []) as Array
		return _fail(str(resolved.get("error", "Could not resolve target location.")), summary)
	warnings.append_array(resolved.get("warnings", []) as Array)

	var scene_path := str(resolved.get("scene_path", ""))
	var location_data: Dictionary = resolved.get("location_data", {}) as Dictionary
	var entrance_errors: Array[String] = _validate_location_entrance(location_data, entrance_id)
	if not entrance_errors.is_empty():
		summary["warnings"] = warnings
		return _fail("Target entrance is invalid for %s/%s: %s" % [target_location_id, entrance_id, str(entrance_errors)], summary)
	if load_scene:
		if scene_path.is_empty():
			summary["warnings"] = warnings
			return _fail("Target location has no scene_path: %s" % target_location_id, summary)
		if not location_data.is_empty():
			SceneLoader.set_pending_location_data(location_data)
		var load_error: Error = SceneLoader.load_location(scene_path, entrance_id)
		if load_error != OK:
			summary["warnings"] = warnings
			return _fail("SceneLoader failed to load location scene: %s" % scene_path, summary)

	_runtime.current_location_id = target_location_id
	GameState.set_scene_context(target_location_id, target_location_id)

	summary["success"] = true
	summary["world_id"] = _graph.world_id
	summary["target_location_source_type"] = str(target_spec.get("source_type", ""))
	summary["target_location_kind"] = str(target_spec.get("location_kind", ""))
	summary["parent_location_id"] = str(target_spec.get("parent_location_id", ""))
	summary["generated_or_loaded"] = str(resolved.get("generated_or_loaded", "loaded"))
	summary["seed"] = int(resolved.get("seed", 0))
	summary["scene_path"] = scene_path
	summary["entrance_id"] = entrance_id
	summary["warnings"] = warnings
	last_transition_summary = summary.duplicate(true)
	_runtime.record_transition(summary)
	transition_completed.emit(summary.duplicate(true))
	return summary


func _entrance_id_for_spawn(spawn_spec: Dictionary) -> String:
	return str(spawn_spec.get("entrance_id", ""))


func _validate_location_entrance(location_data: Dictionary, entrance_id: String) -> Array[String]:
	var errors: Array[String] = []
	if location_data.is_empty():
		errors.append("location data is empty")
		return errors
	var location_grid: LocationGrid = LocationGrid.from_dictionary(location_data)
	if not location_grid.is_valid():
		errors.append("location grid is invalid")
		return errors
	var entrance: Dictionary = location_grid.get_entrance(entrance_id)
	if entrance.is_empty():
		errors.append("entrance is missing")
		return errors
	var entrance_cell: Vector2i = location_grid.get_entrance_cell(entrance_id)
	if not location_grid.in_bounds(entrance_cell):
		errors.append("entrance cell is out of bounds: %s" % str(entrance_cell))
	elif not location_grid.is_walkable(entrance_cell):
		errors.append("entrance cell is blocked: %s" % str(entrance_cell))
	return errors


func _current_location_id() -> String:
	if _runtime != null and not _runtime.current_location_id.is_empty():
		return _runtime.current_location_id
	return GameState.current_location_id


func _region_map_display_location_id(location_id: String) -> String:
	var cursor := location_id
	var visited := {}
	while not cursor.is_empty() and not visited.has(cursor):
		visited[cursor] = true
		var spec: Dictionary = _graph.get_location_spec(cursor)
		if _location_has_region_position(spec):
			return cursor
		cursor = str(spec.get("parent_location_id", ""))
	return ""


func _location_has_region_position(location_spec: Dictionary) -> bool:
	var position: Dictionary = location_spec.get("region_position", {}) as Dictionary
	return position.has("x") and position.has("y")


func _reset_instances() -> void:
	_graph = WorldLocationGraphScript.new()
	_runtime = WorldRuntimeStateScript.new()
	_registry = WorldLocationRegistryScript.new()


func _fail(reason: String, summary: Dictionary) -> Dictionary:
	var failed_summary := summary.duplicate(true)
	failed_summary["success"] = false
	failed_summary["error"] = reason
	if not failed_summary.has("warnings"):
		failed_summary["warnings"] = []
	(failed_summary["warnings"] as Array).append(reason)
	last_transition_summary = failed_summary.duplicate(true)
	push_warning(reason)
	transition_failed.emit(failed_summary.duplicate(true))
	return failed_summary

extends SceneTree

const WorldGraphGeneratorScript := preload("res://scripts/systems/world/world_graph_generator.gd")
const WorldGraphBlueprintScript := preload("res://scripts/systems/world/world_graph_blueprint.gd")
const WorldGraphCompilerScript := preload("res://scripts/systems/world/world_graph_compiler.gd")

const PROFILE_ID := "temperate_frontier"
const WORLD_SEED := 6501


func _initialize() -> void:
	_run()


func _run() -> void:
	var input := {
		"world_id": "generated_test_world",
		"world_seed": WORLD_SEED,
		"region_profile_id": PROFILE_ID,
	}
	var generator: RefCounted = WorldGraphGeneratorScript.new()
	var first_blueprint: RefCounted = generator.generate_blueprint(input)
	var first_data: Dictionary = first_blueprint.to_dictionary()
	if not _assert_blueprint(first_blueprint, first_data):
		return

	var second_generator: RefCounted = WorldGraphGeneratorScript.new()
	var second_data: Dictionary = second_generator.generate_world_data(input)
	if _world_signature(first_data) != _world_signature(second_data):
		_fail("v65 same seed did not reproduce the same generated world graph")
		return

	var third_generator: RefCounted = WorldGraphGeneratorScript.new()
	var different_data: Dictionary = third_generator.generate_world_data({
		"world_id": "generated_test_world",
		"world_seed": WORLD_SEED + 7,
		"region_profile_id": PROFILE_ID,
	})
	if _world_signature(first_data) == _world_signature(different_data):
		_fail("v65 different seed produced the same generated world graph signature")
		return

	var compiler: RefCounted = WorldGraphCompilerScript.new()
	var compile_result: Dictionary = compiler.compile_to_graph(first_blueprint)
	if not bool(compile_result.get("success", false)):
		_fail("v65 generated world graph did not compile: %s" % str(compile_result.get("errors", [])))
		return

	var world_service: Variant = _world_service()
	if world_service == null:
		_fail("v65 WorldTransitionService autoload is missing")
		return
	world_service.reset_world()
	var load_result: Dictionary = world_service.load_world_from_data(first_data)
	if not bool(load_result.get("success", false)):
		_fail("v65 generated world graph could not load into WorldTransitionService: %s" % str(load_result.get("error", "")))
		return
	var start_result: Dictionary = world_service.start_world(false)
	if not bool(start_result.get("success", false)):
		_fail("v65 generated world could not start: %s" % str(start_result.get("error", "")))
		return

	var start_location_id := str(first_data.get("start_location_id", ""))
	if GameState.current_scene_id != start_location_id:
		_fail("v65 generated world should expose the world node id as scene context, got %s" % GameState.current_scene_id)
		return
	var generated_edge: Dictionary = _first_generated_wild_edge_from(world_service, first_data, start_location_id)
	if generated_edge.is_empty():
		_fail("v65 generated graph has no generated_wild edge reachable from start")
		return
	if str(generated_edge.get("exit_id", "")) != "wild_gate":
		_fail("v65 generated start edge must use the village wild_gate exit, got %s" % str(generated_edge.get("exit_id", "")))
		return
	if _generated_wild_edge_count_from(world_service, first_data, start_location_id) != 1:
		_fail("v65 generated start village should expose exactly one generated_wild edge until multiple village gates exist")
		return

	var enter_result: Dictionary = world_service.transition_by_exit_id(str(generated_edge.get("exit_id", "")), false)
	if not bool(enter_result.get("success", false)):
		_fail("v65 generated edge transition failed: %s" % str(enter_result.get("error", "")))
		return
	var wild_location_id := str(enter_result.get("target_location_id", ""))
	if GameState.current_scene_id != wild_location_id:
		_fail("v65 generated wild entry should expose the generated node id as scene context, got %s" % GameState.current_scene_id)
		return
	if str(enter_result.get("target_location_kind", "")) != "generated_wild":
		_fail("v65 generated edge did not target generated_wild")
		return
	if str(enter_result.get("generated_or_loaded", "")) != "generated":
		_fail("v65 generated_wild first entry should materialize, got %s" % str(enter_result.get("generated_or_loaded", "")))
		return
	if world_service.get_generation_count(wild_location_id) != 1:
		_fail("v65 generated_wild generation count should be 1 after first entry")
		return
	var wild_data: Dictionary = world_service.get_registered_location_data(wild_location_id)
	if wild_data.is_empty():
		_fail("v65 generated_wild location data was not registered")
		return
	if not _wild_data_has_world_exit(wild_data):
		_fail("v65 generated_wild location data did not expose world graph exits")
		return
	var target_spawn: Dictionary = world_service.get_spawn_spec(wild_location_id, str(generated_edge.get("target_spawn_id", "")))
	var target_entrance_id := str(target_spawn.get("entrance_id", ""))
	if target_entrance_id.is_empty() or _entrance(wild_data, target_entrance_id).is_empty():
		_fail("v65 generated_wild did not compile the edge target entrance: %s" % target_entrance_id)
		return

	var return_edge: Dictionary = _first_edge_to(world_service, wild_location_id, start_location_id)
	if return_edge.is_empty():
		_fail("v65 generated_wild node has no return edge to start")
		return
	var return_metadata: Dictionary = return_edge.get("metadata", {}) as Dictionary
	if not _entrance_matches_side(wild_data, target_entrance_id, str(return_metadata.get("side", ""))):
		_fail("v65 generated_wild target entrance is not near its world edge side")
		return
	var return_result: Dictionary = world_service.transition_by_exit_id(str(return_edge.get("exit_id", "")), false)
	if not bool(return_result.get("success", false)):
		_fail("v65 generated_wild return transition failed: %s" % str(return_result.get("error", "")))
		return
	if str(world_service.get_current_location_id()) != start_location_id:
		_fail("v65 return transition did not restore the start location")
		return

	var second_enter: Dictionary = world_service.transition_by_exit_id(str(generated_edge.get("exit_id", "")), false)
	if not bool(second_enter.get("success", false)):
		_fail("v65 second generated_wild entry failed: %s" % str(second_enter.get("error", "")))
		return
	if str(second_enter.get("generated_or_loaded", "")) != "runtime":
		_fail("v65 second generated_wild entry should reuse runtime data")
		return
	if world_service.get_generation_count(wild_location_id) != 1:
		_fail("v65 generated_wild was regenerated on second entry")
		return

	var save_state: Dictionary = world_service.get_save_state()
	world_service.apply_save_state(save_state)
	if world_service.get_exit_spec(start_location_id, str(generated_edge.get("exit_id", ""))).is_empty():
		_fail("v65 restored save state lost generated graph edge")
		return

	var summary: Dictionary = first_data.get("debug_summary", {}) as Dictionary
	print("v65 world graph generator smoke test passed (nodes=%d edges=%d generated=%s first_wild=%s)" % [
		int(summary.get("node_count", 0)),
		int(summary.get("edge_count", 0)),
		str(summary.get("generated_node_ids", [])),
		wild_location_id,
	])
	quit(0)


func _assert_blueprint(blueprint: RefCounted, data: Dictionary) -> bool:
	var validation_errors: Array[String] = blueprint.validate()
	if not validation_errors.is_empty():
		_fail("v65 generated blueprint failed validation: %s" % str(validation_errors))
		return false
	var locations: Array = data.get("locations", []) as Array
	var exits: Array = data.get("exits", []) as Array
	var spawns: Array = data.get("spawns", []) as Array
	var profile_range := [5, 8]
	var node_count := locations.size()
	if node_count < int(profile_range[0]) or node_count > int(profile_range[1]):
		_fail("v65 node_count outside profile range: %d" % node_count)
		return false
	if node_count < 2:
		_fail("v65 generated graph has too few nodes")
		return false
	if _generated_wild_nodes(locations).is_empty():
		_fail("v65 generated graph has no generated_wild node")
		return false
	if not _ids_are_unique(locations, "location_id"):
		_fail("v65 location node ids are not unique")
		return false
	if not _ids_are_unique(exits, "exit_id"):
		_fail("v65 transition edge ids are not unique")
		return false
	if not _spawn_ids_are_unique(spawns):
		_fail("v65 spawn ids are not unique within their locations")
		return false
	if not _all_edges_resolve(data):
		return false
	if not _generated_wild_nodes_have_generation_data(locations):
		return false
	if not _generated_wild_nodes_have_semantic_profiles(locations):
		return false
	var summary: Dictionary = data.get("debug_summary", {}) as Dictionary
	if summary.is_empty() or not bool(summary.get("connected", false)):
		_fail("v65 debug summary is missing or reports disconnected graph")
		return false
	return true


func _generated_wild_nodes(locations: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for location_value in locations:
		var location: Dictionary = location_value as Dictionary
		if str(location.get("location_kind", "")) == "generated_wild":
			result.append(location)
	return result


func _generated_wild_nodes_have_generation_data(locations: Array) -> bool:
	for location in _generated_wild_nodes(locations):
		if str(location.get("generator_profile_id", "")).is_empty():
			_fail("v65 generated_wild node missing generator_profile_id")
			return false
		if not location.has("seed"):
			_fail("v65 generated_wild node missing seed")
			return false
		if (location.get("size", {}) as Dictionary).is_empty():
			_fail("v65 generated_wild node missing size")
			return false
	return true


func _generated_wild_nodes_have_semantic_profiles(locations: Array) -> bool:
	var generated_nodes := _generated_wild_nodes(locations)
	var profile_ids: Dictionary = {}
	for location in generated_nodes:
		var location_id := str(location.get("location_id", ""))
		var profile_id := str(location.get("generator_profile_id", ""))
		profile_ids[profile_id] = true
		if not location_id.contains(profile_id):
			_fail("v65 generated_wild node id should include its terrain profile: %s / %s" % [location_id, profile_id])
			return false
	if generated_nodes.size() >= 2 and profile_ids.size() < 2:
		_fail("v65 generated world should not collapse every generated node to the same terrain profile")
		return false
	return true


func _ids_are_unique(rows: Array, id_key: String) -> bool:
	var seen: Dictionary = {}
	for row_value in rows:
		var row: Dictionary = row_value as Dictionary
		var id := str(row.get(id_key, ""))
		if id.is_empty() or seen.has(id):
			return false
		seen[id] = true
	return true


func _spawn_ids_are_unique(spawns: Array) -> bool:
	var seen: Dictionary = {}
	for spawn_value in spawns:
		var spawn: Dictionary = spawn_value as Dictionary
		var key := "%s::%s" % [str(spawn.get("location_id", "")), str(spawn.get("spawn_id", ""))]
		if seen.has(key):
			return false
		seen[key] = true
	return true


func _all_edges_resolve(data: Dictionary) -> bool:
	var locations: Dictionary = {}
	var spawns: Dictionary = {}
	for location_value in (data.get("locations", []) as Array):
		var location: Dictionary = location_value as Dictionary
		locations[str(location.get("location_id", ""))] = true
	for spawn_value in (data.get("spawns", []) as Array):
		var spawn: Dictionary = spawn_value as Dictionary
		spawns["%s::%s" % [str(spawn.get("location_id", "")), str(spawn.get("spawn_id", ""))]] = true
	for exit_value in (data.get("exits", []) as Array):
		var edge: Dictionary = exit_value as Dictionary
		var from_location_id := str(edge.get("from_location_id", ""))
		var target_location_id := str(edge.get("target_location_id", ""))
		var target_spawn_id := str(edge.get("target_spawn_id", ""))
		if not locations.has(from_location_id) or not locations.has(target_location_id):
			_fail("v65 edge references an unknown node: %s" % str(edge))
			return false
		if not spawns.has("%s::%s" % [target_location_id, target_spawn_id]):
			_fail("v65 edge target spawn cannot resolve: %s" % str(edge))
			return false
	return true


func _first_generated_wild_edge_from(world_service: Variant, data: Dictionary, from_location_id: String) -> Dictionary:
	for edge_value in world_service.get_edges_from(from_location_id):
		var edge: Dictionary = edge_value as Dictionary
		var target_location_id := str(edge.get("target_location_id", ""))
		var location: Dictionary = _location_row(data, target_location_id)
		if str(location.get("location_kind", "")) == "generated_wild":
			return edge
	return {}


func _generated_wild_edge_count_from(world_service: Variant, data: Dictionary, from_location_id: String) -> int:
	var count := 0
	for edge_value in world_service.get_edges_from(from_location_id):
		var edge: Dictionary = edge_value as Dictionary
		var target_location_id := str(edge.get("target_location_id", ""))
		var location: Dictionary = _location_row(data, target_location_id)
		if str(location.get("location_kind", "")) == "generated_wild":
			count += 1
	return count


func _first_edge_to(world_service: Variant, from_location_id: String, target_location_id: String) -> Dictionary:
	for edge_value in world_service.get_edges_from(from_location_id):
		var edge: Dictionary = edge_value as Dictionary
		if str(edge.get("target_location_id", "")) == target_location_id:
			return edge
	return {}


func _location_row(data: Dictionary, location_id: String) -> Dictionary:
	for location_value in (data.get("locations", []) as Array):
		var location: Dictionary = location_value as Dictionary
		if str(location.get("location_id", "")) == location_id:
			return location
	return {}


func _wild_data_has_world_exit(location_data: Dictionary) -> bool:
	for exit_value in (location_data.get("exits", []) as Array):
		var exit_data: Dictionary = exit_value as Dictionary
		if not str(exit_data.get("world_exit_id", "")).is_empty():
			return true
	return false


func _entrance(location_data: Dictionary, entrance_id: String) -> Dictionary:
	for entrance_value in (location_data.get("entrances", []) as Array):
		var entrance: Dictionary = entrance_value as Dictionary
		if str(entrance.get("id", "")) == entrance_id:
			return entrance
	return {}


func _entrance_matches_side(location_data: Dictionary, entrance_id: String, side: String) -> bool:
	var entrance_data := _entrance(location_data, entrance_id)
	if entrance_data.is_empty() or side.is_empty():
		return true
	var cell: Dictionary = entrance_data.get("grid_position", {}) as Dictionary
	var size: Dictionary = location_data.get("size", {}) as Dictionary
	var x := int(cell.get("x", 0))
	var y := int(cell.get("y", 0))
	var width := int(size.get("width", 1))
	var height := int(size.get("height", 1))
	var edge_band := maxi(3, int(ceil(float(maxi(width, height)) * 0.20)))
	match side:
		"west", "left":
			return x <= edge_band
		"east", "right":
			return x >= width - 1 - edge_band
		"north", "up":
			return y <= edge_band
		"south", "down":
			return y >= height - 1 - edge_band
		_:
			return true


func _world_signature(data: Dictionary) -> String:
	var parts: Array[String] = [
		str(data.get("world_id", "")),
		str(data.get("world_seed", "")),
		str(data.get("start_location_id", "")),
	]
	var locations: Array[String] = []
	for location_value in (data.get("locations", []) as Array):
		var location: Dictionary = location_value as Dictionary
		locations.append("%s:%s:%s:%s:%s" % [
			str(location.get("location_id", "")),
			str(location.get("location_kind", "")),
			str(location.get("generator_profile_id", "")),
			str(location.get("seed", "")),
			str(location.get("size", {})),
		])
	locations.sort()
	parts.append_array(locations)
	var exits: Array[String] = []
	for exit_value in (data.get("exits", []) as Array):
		var edge: Dictionary = exit_value as Dictionary
		exits.append("%s:%s:%s:%s" % [
			str(edge.get("exit_id", "")),
			str(edge.get("from_location_id", "")),
			str(edge.get("target_location_id", "")),
			str(edge.get("target_spawn_id", "")),
		])
	exits.sort()
	parts.append_array(exits)
	return "|".join(parts)


func _world_service() -> Variant:
	return root.get_node_or_null("WorldTransitionService")


func _fail(message: String) -> void:
	push_error(message)
	quit(1)

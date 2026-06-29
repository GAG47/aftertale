extends SceneTree

const WorldGraphGeneratorScript := preload("res://scripts/systems/world/world_graph_generator.gd")
const WorldGraphBlueprintScript := preload("res://scripts/systems/world/world_graph_blueprint.gd")
const WorldGraphCompilerScript := preload("res://scripts/systems/world/world_graph_compiler.gd")

const PROFILE_ID := "temperate_frontier"
const WORLD_SEED := 6501
const LEGACY_TARGET_SCENE_PATH := "res://scenes/locations/generated_settlement_location.tscn"


class FakeLocationRoot:
	extends Node

	var grid: LocationGrid
	var transition_requested := false

	func get_location_grid() -> LocationGrid:
		return grid

	func request_exit_transition(_exit_data: Dictionary) -> bool:
		transition_requested = true
		return true


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var input := {
		"world_id": "generated_world_graph_smoke",
		"world_seed": WORLD_SEED,
		"region_profile_id": PROFILE_ID,
	}
	var generator: RefCounted = WorldGraphGeneratorScript.new()
	var first_result: Dictionary = generator.generate_world_data_result(input)
	if not bool(first_result.get("success", false)):
		_fail("v65.1 generated world graph failed: %s" % str(first_result.get("errors", [])))
		return
	var first_data: Dictionary = first_result.get("world_data", {}) as Dictionary
	var first_blueprint: RefCounted = WorldGraphBlueprintScript.new()
	first_blueprint.configure(first_data)
	if not _assert_blueprint(first_blueprint, first_data):
		return

	var second_generator: RefCounted = WorldGraphGeneratorScript.new()
	var second_result: Dictionary = second_generator.generate_world_data_result(input)
	if not bool(second_result.get("success", false)):
		_fail("v65.1 second same-seed generation failed: %s" % str(second_result.get("errors", [])))
		return
	var second_data: Dictionary = second_result.get("world_data", {}) as Dictionary
	if _world_signature(first_data) != _world_signature(second_data):
		_fail("v65.1 same seed did not reproduce the same generated world graph")
		return

	var third_generator: RefCounted = WorldGraphGeneratorScript.new()
	var different_result: Dictionary = third_generator.generate_world_data_result({
		"world_id": "generated_world_graph_smoke",
		"world_seed": WORLD_SEED + 7,
		"region_profile_id": PROFILE_ID,
	})
	if not bool(different_result.get("success", false)):
		_fail("v65.1 different-seed generation failed: %s" % str(different_result.get("errors", [])))
		return
	var different_data: Dictionary = different_result.get("world_data", {}) as Dictionary
	if _world_signature(first_data) == _world_signature(different_data):
		_fail("v65.1 different seed produced the same generated world graph signature")
		return

	if not _assert_unsupported_kind_fails():
		return
	if not _assert_move_action_does_not_request_exit():
		return

	var compiler: RefCounted = WorldGraphCompilerScript.new()
	var compile_result: Dictionary = compiler.compile_to_graph(first_blueprint)
	if not bool(compile_result.get("success", false)):
		_fail("v65.1 generated world graph did not compile: %s" % str(compile_result.get("errors", [])))
		return

	var world_service: Variant = _world_service()
	if world_service == null:
		_fail("v65.1 WorldTransitionService autoload is missing")
		return
	world_service.reset_world()
	var load_result: Dictionary = world_service.load_world_from_data(first_data)
	if not bool(load_result.get("success", false)):
		_fail("v65.1 generated world graph could not load into WorldTransitionService: %s" % str(load_result.get("error", "")))
		return
	var start_result: Dictionary = world_service.start_world(false)
	if not bool(start_result.get("success", false)):
		_fail("v65.1 generated world could not start: %s" % str(start_result.get("error", "")))
		return

	var start_location_id := str(first_data.get("start_location_id", ""))
	if str(world_service.get_current_location_id()) != start_location_id:
		_fail("v65.1 generated world should expose the world node id as current location, got %s" % str(world_service.get_current_location_id()))
		return
	var start_generation_count: int = int(world_service.get_generation_count(start_location_id))
	if start_generation_count != 1:
		_fail("v65.1 start generated_wild should materialize once, got %d" % start_generation_count)
		return

	var generated_edge: Dictionary = _first_edge_from(world_service, start_location_id)
	if generated_edge.is_empty():
		_fail("v65.1 generated graph has no edge reachable from start")
		return

	var enter_result: Dictionary = world_service.transition_by_exit_id(str(generated_edge.get("exit_id", "")), false)
	if not bool(enter_result.get("success", false)):
		_fail("v65.1 generated edge transition failed: %s" % str(enter_result.get("error", "")))
		return
	var target_location_id := str(enter_result.get("target_location_id", ""))
	if str(enter_result.get("target_location_kind", "")) != "generated_wild":
		_fail("v65.1 generated edge did not target generated_wild")
		return
	if str(enter_result.get("generated_or_loaded", "")) != "generated":
		_fail("v65.1 generated_wild first entry should materialize, got %s" % str(enter_result.get("generated_or_loaded", "")))
		return
	if world_service.get_generation_count(target_location_id) != 1:
		_fail("v65.1 generated_wild generation count should be 1 after first entry")
		return
	var wild_data: Dictionary = world_service.get_registered_location_data(target_location_id)
	if wild_data.is_empty():
		_fail("v65.1 generated_wild location data was not registered")
		return
	if not _wild_data_has_world_exit(wild_data):
		_fail("v65.1 generated_wild location data did not expose world graph exits")
		return
	var target_spawn: Dictionary = world_service.get_spawn_spec(target_location_id, str(generated_edge.get("target_spawn_id", "")))
	var target_entrance_id := str(target_spawn.get("entrance_id", ""))
	if target_entrance_id.is_empty() or _entrance(wild_data, target_entrance_id).is_empty():
		_fail("v65.1 generated_wild did not compile the edge target entrance: %s" % target_entrance_id)
		return

	var return_edge: Dictionary = _first_edge_to(world_service, target_location_id, start_location_id)
	if return_edge.is_empty():
		_fail("v65.1 generated_wild node has no return edge to start")
		return
	if not _entrance_is_adjacent_to_exit(wild_data, target_entrance_id, str(return_edge.get("exit_id", ""))):
		_fail("v65.1 generated_wild target entrance is not adjacent to the paired return exit")
		return
	var return_result: Dictionary = world_service.transition_by_exit_id(str(return_edge.get("exit_id", "")), false)
	if not bool(return_result.get("success", false)):
		_fail("v65.1 generated_wild return transition failed: %s" % str(return_result.get("error", "")))
		return
	if str(world_service.get_current_location_id()) != start_location_id:
		_fail("v65.1 return transition did not restore the start location")
		return

	var second_enter: Dictionary = world_service.transition_by_exit_id(str(generated_edge.get("exit_id", "")), false)
	if not bool(second_enter.get("success", false)):
		_fail("v65.1 second generated_wild entry failed: %s" % str(second_enter.get("error", "")))
		return
	if str(second_enter.get("generated_or_loaded", "")) != "runtime":
		_fail("v65.1 second generated_wild entry should reuse runtime data")
		return
	if world_service.get_generation_count(target_location_id) != 1:
		_fail("v65.1 generated_wild was regenerated on second entry")
		return

	var save_state: Dictionary = world_service.get_save_state()
	world_service.apply_save_state(save_state)
	if world_service.get_exit_spec(start_location_id, str(generated_edge.get("exit_id", ""))).is_empty():
		_fail("v65.1 restored save state lost generated graph edge")
		return
	var active_world_blocks_legacy_target: bool = await _assert_location_root_blocks_legacy_target_scene_path(first_data)
	if not active_world_blocks_legacy_target:
		return

	var summary: Dictionary = first_data.get("debug_summary", {}) as Dictionary
	print("v65.1 world graph generator smoke test passed (nodes=%d edges=%d first_target=%s)" % [
		int(summary.get("node_count", 0)),
		int(summary.get("edge_count", 0)),
		target_location_id,
	])
	quit(0)


func _assert_blueprint(blueprint: RefCounted, data: Dictionary) -> bool:
	var validation_errors: Array[String] = blueprint.validate()
	if not validation_errors.is_empty():
		_fail("v65.1 generated blueprint failed validation: %s" % str(validation_errors))
		return false
	if not _assert_no_fixture_tokens(data):
		return false
	var locations: Array = data.get("locations", []) as Array
	var exits: Array = data.get("exits", []) as Array
	var spawns: Array = data.get("spawns", []) as Array
	var node_count := locations.size()
	if node_count < 5 or node_count > 8:
		_fail("v65.1 node_count outside profile range: %d" % node_count)
		return false
	if node_count < 2:
		_fail("v65.1 generated graph has too few nodes")
		return false
	if str(data.get("start_spawn_id", "")).is_empty():
		_fail("v65.1 start_spawn_id is missing")
		return false
	if _generated_wild_nodes(locations).is_empty():
		_fail("v65.1 generated graph has no generated_wild node")
		return false
	if not _ids_are_unique(locations, "location_id"):
		_fail("v65.1 location node ids are not unique")
		return false
	if not _ids_are_unique(exits, "exit_id"):
		_fail("v65.1 transition edge ids are not unique")
		return false
	if not _spawn_ids_are_unique(spawns):
		_fail("v65.1 spawn ids are not unique within their locations")
		return false
	if not _all_edges_resolve(data):
		return false
	if not _generated_wild_nodes_have_generation_data(locations):
		return false
	var summary: Dictionary = data.get("debug_summary", {}) as Dictionary
	if summary.is_empty() or not bool(summary.get("connected", false)):
		_fail("v65.1 debug summary is missing or reports disconnected graph")
		return false
	return true


func _assert_no_fixture_tokens(data: Dictionary) -> bool:
	var serialized: String = JSON.stringify(data)
	for token in ["test_village", "test_wild_plain", "test_world", "wild_gate", "return_to_village"]:
		if serialized.contains(token):
			_fail("v65.1 generated graph still contains fixture token: %s" % token)
			return false
	return true


func _assert_unsupported_kind_fails() -> bool:
	var generator: RefCounted = WorldGraphGeneratorScript.new()
	var result: Dictionary = generator.generate_world_data_result({
		"world_id": "unsupported_kind_world",
		"world_seed": WORLD_SEED,
		"region_profile_id": PROFILE_ID,
		"available_location_kinds": ["generated_settlement"],
		"location_kind_weights": {
			"generated_settlement": 1.0,
		},
	})
	if bool(result.get("success", false)):
		_fail("v65.1 unsupported generated_settlement unexpectedly succeeded")
		return false
	var errors_text := str(result.get("errors", []))
	if not errors_text.contains("unsupported location kind"):
		_fail("v65.1 unsupported generated_settlement did not report an unsupported kind error: %s" % errors_text)
		return false
	return true


func _assert_move_action_does_not_request_exit() -> bool:
	var grid := LocationGrid.from_dictionary({
		"id": "move_action_exit_contract",
		"display_name": "Move Action Exit Contract",
		"size": { "width": 4, "height": 3 },
		"tile_size": 32,
		"tiles": [
			"gggg",
			"gggg",
			"gggg",
		],
		"terrain": {
			"g": { "id": "grass", "walkable": true },
		},
		"exits": [
			{
				"id": "contract_exit",
				"grid_position": { "x": 2, "y": 1 },
				"world_exit_id": "contract_world_exit",
				"target_entrance_id": "contract_entry",
			},
		],
	})
	var actor := CharacterEntity.new()
	actor.character_id = "move_action_actor"
	actor.display_name = "Move Action Actor"
	actor.blocks_movement = true
	actor.set_grid_position(Vector2i(1, 1))
	if not grid.register_character(actor.character_id, actor.grid_position, actor, actor.blocks_movement):
		actor.free()
		_fail("v65.1 move action contract could not register the actor")
		return false

	var fake_root := FakeLocationRoot.new()
	fake_root.grid = grid
	root.add_child(fake_root)
	var action := MoveAction.new()
	action.configure(actor, { "direction": Vector2i.RIGHT }, { "location_root": fake_root })
	var action_result: ActionResult = action.execute()
	var transition_requested := fake_root.transition_requested
	var actor_cell := actor.grid_position
	fake_root.queue_free()
	actor.free()

	if not action_result.success:
		_fail("v65.1 MoveAction failed when walking onto an exit cell: %s" % action_result.failure_reason)
		return false
	if actor_cell != Vector2i(2, 1):
		_fail("v65.1 MoveAction did not move the actor onto the exit cell")
		return false
	if transition_requested:
		_fail("v65.1 MoveAction requested an exit transition directly")
		return false
	if _action_result_has_change_type(action_result, "location_exit_requested"):
		_fail("v65.1 MoveAction still emits location_exit_requested")
		return false
	return true


func _action_result_has_change_type(result: ActionResult, change_type: String) -> bool:
	for change in result.world_changes:
		if str(change.get("type", "")) == change_type:
			return true
	return false


func _assert_location_root_blocks_legacy_target_scene_path(world_data: Dictionary) -> bool:
	var world_service: Variant = _world_service()
	var scene_loader: Variant = _scene_loader()
	if world_service == null or scene_loader == null:
		_fail("v65.1 cannot verify active-world legacy target blocking without world service and scene loader")
		return false

	var scene_container := Node.new()
	scene_container.name = "V65SceneLoaderSmokeContainer"
	root.add_child(scene_container)
	scene_loader.configure(scene_container)
	scene_loader.unload_current_scene()
	world_service.reset_world()

	var load_result: Dictionary = world_service.load_world_from_data(world_data)
	if not bool(load_result.get("success", false)):
		return _fail_location_root_assertion(
			"v65.1 could not reload generated world for LocationRoot legacy target check: %s" % str(load_result.get("error", "")),
			scene_loader,
			scene_container,
			world_service
		)
	var start_result: Dictionary = world_service.start_world(true)
	if not bool(start_result.get("success", false)):
		return _fail_location_root_assertion(
			"v65.1 could not load generated world scene for legacy target check: %s" % str(start_result.get("error", "")),
			scene_loader,
			scene_container,
			world_service
		)
	await process_frame
	if scene_loader.current_scene == null or not is_instance_valid(scene_loader.current_scene):
		return _fail_location_root_assertion(
			"v65.1 SceneLoader did not expose the active generated LocationRoot",
			scene_loader,
			scene_container,
			world_service
		)

	var original_scene: Node = scene_loader.current_scene
	var original_scene_path := str(scene_loader.current_scene_path)
	if not original_scene.has_method("request_exit_transition"):
		return _fail_location_root_assertion(
			"v65.1 loaded scene cannot receive exit transition requests",
			scene_loader,
			scene_container,
			world_service
		)

	var result: bool = bool(original_scene.call("request_exit_transition", {
		"id": "missing_exit_with_legacy_target",
		"world_exit_id": "missing_exit_with_legacy_target",
		"target_scene_path": LEGACY_TARGET_SCENE_PATH,
		"target_entrance_id": "legacy_target",
	}))
	if result:
		return _fail_location_root_assertion(
			"v65.1 active LocationRoot accepted a missing world edge because target_scene_path existed",
			scene_loader,
			scene_container,
			world_service
		)
	if str(scene_loader.current_scene_path) != original_scene_path:
		return _fail_location_root_assertion(
			"v65.1 active LocationRoot loaded target_scene_path after a failed world edge",
			scene_loader,
			scene_container,
			world_service
		)
	if scene_loader.current_scene != original_scene:
		return _fail_location_root_assertion(
			"v65.1 active LocationRoot replaced the scene after a failed world edge",
			scene_loader,
			scene_container,
			world_service
		)

	scene_loader.unload_current_scene()
	await process_frame
	world_service.reset_world()
	scene_container.queue_free()
	return true


func _fail_location_root_assertion(message: String, scene_loader: Variant, scene_container: Node, world_service: Variant) -> bool:
	if scene_loader != null:
		scene_loader.unload_current_scene()
	if scene_container != null and is_instance_valid(scene_container):
		scene_container.queue_free()
	if world_service != null:
		world_service.reset_world()
	_fail(message)
	return false


func _generated_wild_nodes(locations: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for location_value in locations:
		var location: Dictionary = location_value as Dictionary
		if str(location.get("location_kind", "")) == "generated_wild":
			result.append(location)
	return result


func _generated_wild_nodes_have_generation_data(locations: Array) -> bool:
	for location in _generated_wild_nodes(locations):
		if str(location.get("generator_id", "")) != "wild_terrain":
			_fail("v65.1 generated_wild node has wrong generator_id")
			return false
		if str(location.get("generator_profile_id", "")).is_empty():
			_fail("v65.1 generated_wild node missing generator_profile_id")
			return false
		if not location.has("seed"):
			_fail("v65.1 generated_wild node missing seed")
			return false
		var size: Dictionary = location.get("size", {}) as Dictionary
		if int(size.get("width", 0)) <= 0 or int(size.get("height", 0)) <= 0:
			_fail("v65.1 generated_wild node missing width or height")
			return false
		if not str(location.get("scene_path", "")).is_empty() or not str(location.get("data_path", "")).is_empty():
			_fail("v65.1 generated_wild node should not point at fixture scene or data paths")
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
			_fail("v65.1 edge references an unknown node: %s" % str(edge))
			return false
		if not spawns.has("%s::%s" % [target_location_id, target_spawn_id]):
			_fail("v65.1 edge target spawn cannot resolve: %s" % str(edge))
			return false
	return true


func _first_edge_from(world_service: Variant, from_location_id: String) -> Dictionary:
	for edge_value in world_service.get_edges_from(from_location_id):
		return (edge_value as Dictionary).duplicate(true)
	return {}


func _first_edge_to(world_service: Variant, from_location_id: String, target_location_id: String) -> Dictionary:
	for edge_value in world_service.get_edges_from(from_location_id):
		var edge: Dictionary = edge_value as Dictionary
		if str(edge.get("target_location_id", "")) == target_location_id:
			return edge.duplicate(true)
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


func _exit(location_data: Dictionary, exit_id: String) -> Dictionary:
	for exit_value in (location_data.get("exits", []) as Array):
		var exit_data: Dictionary = exit_value as Dictionary
		if str(exit_data.get("id", "")) == exit_id:
			return exit_data
	return {}


func _entrance_is_adjacent_to_exit(location_data: Dictionary, entrance_id: String, exit_id: String) -> bool:
	var entrance_data := _entrance(location_data, entrance_id)
	var exit_data := _exit(location_data, exit_id)
	if entrance_data.is_empty() or exit_data.is_empty():
		return false
	var entrance_cell := _cell_from_dict(entrance_data.get("grid_position", {}) as Dictionary)
	var exit_cell := _cell_from_dict(exit_data.get("grid_position", {}) as Dictionary)
	return abs(entrance_cell.x - exit_cell.x) + abs(entrance_cell.y - exit_cell.y) == 1


func _cell_from_dict(value: Dictionary) -> Vector2i:
	return Vector2i(int(value.get("x", 0)), int(value.get("y", 0)))


func _world_signature(data: Dictionary) -> String:
	var parts: Array[String] = [
		str(data.get("world_id", "")),
		str(data.get("world_seed", "")),
		str(data.get("start_location_id", "")),
		str(data.get("start_spawn_id", "")),
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


func _scene_loader() -> Variant:
	return root.get_node_or_null("SceneLoader")


func _fail(message: String) -> void:
	push_error(message)
	quit(1)

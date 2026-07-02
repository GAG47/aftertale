extends SceneTree

const WorldGraphGeneratorScript := preload("res://scripts/systems/world/world_graph_generator.gd")
const WildLocationCompilerScript := preload("res://scripts/systems/terrain/wild_location_compiler.gd")

const GENERATED_WILD_SCENE_PATH := "res://scenes/locations/generated_wild_location.tscn"
const PROFILE_ID := "temperate_frontier"
const WORLD_SEED := 6711


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if not _assert_scene_loader_rejects_empty_entrance():
		return
	if not _assert_world_graph_rejects_missing_entry_data():
		return
	if not _assert_wild_compiler_requires_explicit_entrance_hints():
		return
	if not _assert_world_entries_compile_to_real_entrances():
		return
	var entry_scene_ok: bool = await _assert_location_root_spawns_player_at_requested_entry()
	if not entry_scene_ok:
		return

	print("v67.1 explicit location entry smoke test passed")
	quit(0)


func _assert_scene_loader_rejects_empty_entrance() -> bool:
	var scene_loader: Variant = root.get_node_or_null("SceneLoader")
	if scene_loader == null:
		_fail("v67.1 SceneLoader autoload is missing")
		return false
	var scene_container := Node.new()
	scene_container.name = "V671EmptyEntranceContainer"
	root.add_child(scene_container)
	scene_loader.configure(scene_container)
	scene_loader.unload_current_scene()
	var load_error: Error = scene_loader.load_location(GENERATED_WILD_SCENE_PATH, "")
	scene_container.queue_free()
	if load_error != ERR_INVALID_PARAMETER:
		_fail("v67.1 SceneLoader accepted an empty entrance_id")
		return false
	return true


func _assert_world_graph_rejects_missing_entry_data() -> bool:
	var world_service: Variant = root.get_node_or_null("WorldTransitionService")
	if world_service == null:
		_fail("v67.1 WorldTransitionService autoload is missing")
		return false
	var world_data := _generated_world_data(WORLD_SEED)

	var missing_start := world_data.duplicate(true)
	missing_start.erase("start_spawn_id")
	world_service.reset_world()
	var missing_start_result: Dictionary = world_service.load_world_from_data(missing_start)
	if bool(missing_start_result.get("success", false)):
		_fail("v67.1 world graph accepted missing start_spawn_id")
		return false

	var missing_entrance := world_data.duplicate(true)
	var spawns: Array = missing_entrance.get("spawns", []) as Array
	if spawns.is_empty():
		_fail("v67.1 generated world has no spawns to validate")
		return false
	var first_spawn: Dictionary = spawns[0] as Dictionary
	first_spawn.erase("entrance_id")
	spawns[0] = first_spawn
	missing_entrance["spawns"] = spawns
	world_service.reset_world()
	var missing_entrance_result: Dictionary = world_service.load_world_from_data(missing_entrance)
	if bool(missing_entrance_result.get("success", false)):
		_fail("v67.1 world graph accepted a spawn without entrance_id")
		return false
	world_service.reset_world()
	return true


func _assert_wild_compiler_requires_explicit_entrance_hints() -> bool:
	var compiler: RefCounted = WildLocationCompilerScript.new()
	var location_data: Dictionary = compiler.generate_location({
		"id": "v67_1_no_entry_hint",
		"display_name": "v67.1 no entry hint",
		"tile_size": 32,
		"generator": {
			"type": "wild_terrain",
			"seed": WORLD_SEED,
			"terrain_profile_id": "plain",
			"size": { "width": 32, "height": 32 },
		},
	})
	var errors: Array[String] = compiler.validate_location(location_data)
	if errors.is_empty() or not str(errors).contains("no explicit entrances"):
		_fail("v67.1 wild compiler accepted a generated wild location without explicit entrance hints: %s" % str(errors))
		return false
	return true


func _assert_world_entries_compile_to_real_entrances() -> bool:
	var world_service: Variant = root.get_node_or_null("WorldTransitionService")
	if world_service == null:
		_fail("v67.1 WorldTransitionService autoload is missing")
		return false
	world_service.reset_world()
	var world_data := _generated_world_data(WORLD_SEED + 1)
	var load_result: Dictionary = world_service.load_world_from_data(world_data)
	if not bool(load_result.get("success", false)):
		_fail("v67.1 generated world could not load: %s" % str(load_result.get("error", "")))
		return false
	var start_result: Dictionary = world_service.start_world(false)
	if not bool(start_result.get("success", false)):
		_fail("v67.1 generated world could not start: %s" % str(start_result.get("error", "")))
		return false
	var start_location_id := str(world_data.get("start_location_id", ""))
	var start_spawn_id := str(world_data.get("start_spawn_id", ""))
	var start_spawn: Dictionary = _spawn_by_id(world_data, start_location_id, start_spawn_id)
	if str(start_result.get("entrance_id", "")) != str(start_spawn.get("entrance_id", "")):
		_fail("v67.1 start transition did not use the declared start spawn entrance")
		return false
	var start_data: Dictionary = world_service.get_registered_location_data(start_location_id)
	if not _location_has_walkable_entrance(start_data, str(start_spawn.get("entrance_id", ""))):
		_fail("v67.1 start generated_wild did not compile its world spawn entrance")
		return false

	var first_edge: Dictionary = _first_edge_from(world_data, start_location_id)
	if first_edge.is_empty():
		_fail("v67.1 generated world has no edge from start")
		return false
	var target_location_id := str(first_edge.get("target_location_id", ""))
	var target_spawn_id := str(first_edge.get("target_spawn_id", ""))
	var target_spawn: Dictionary = _spawn_by_id(world_data, target_location_id, target_spawn_id)
	var transition_result: Dictionary = world_service.transition_by_exit_id(str(first_edge.get("exit_id", "")), false)
	if not bool(transition_result.get("success", false)):
		_fail("v67.1 edge transition failed: %s" % str(transition_result.get("error", "")))
		return false
	if str(transition_result.get("entrance_id", "")) != str(target_spawn.get("entrance_id", "")):
		_fail("v67.1 edge transition did not use the target spawn entrance")
		return false
	var target_data: Dictionary = world_service.get_registered_location_data(target_location_id)
	if not _location_has_walkable_entrance(target_data, str(target_spawn.get("entrance_id", ""))):
		_fail("v67.1 target generated_wild did not compile the edge target entrance")
		return false
	world_service.reset_world()
	return true


func _assert_location_root_spawns_player_at_requested_entry() -> bool:
	var world_service: Variant = root.get_node_or_null("WorldTransitionService")
	var scene_loader: Variant = root.get_node_or_null("SceneLoader")
	var game_state: Variant = root.get_node_or_null("GameState")
	var party_system: Variant = root.get_node_or_null("PartySystem")
	if world_service == null or scene_loader == null or game_state == null or party_system == null:
		_fail("v67.1 required autoload is missing for LocationRoot entry test")
		return false

	game_state.start_new_session("v67_1_explicit_entry_smoke")
	party_system.reset_party("debug_player")
	var scene_container := Node.new()
	scene_container.name = "V671EntrySceneContainer"
	root.add_child(scene_container)
	scene_loader.configure(scene_container)
	scene_loader.unload_current_scene()
	world_service.reset_world()

	var world_data := _generated_world_data(WORLD_SEED + 2)
	var load_result: Dictionary = world_service.load_world_from_data(world_data)
	if not bool(load_result.get("success", false)):
		return _fail_entry_scene("v67.1 generated world could not load: %s" % str(load_result.get("error", "")), scene_loader, scene_container, world_service)
	var start_result: Dictionary = world_service.start_world(true)
	if not bool(start_result.get("success", false)):
		return _fail_entry_scene("v67.1 generated world could not start with scene load: %s" % str(start_result.get("error", "")), scene_loader, scene_container, world_service)
	await process_frame

	var location_root: Node = scene_loader.current_scene
	if location_root == null or not is_instance_valid(location_root):
		return _fail_entry_scene("v67.1 LocationRoot did not load", scene_loader, scene_container, world_service)
	var grid: LocationGrid = location_root.get_location_grid() as LocationGrid
	var controlled: Node = location_root.get_controlled_character() as Node
	if grid == null or controlled == null:
		return _fail_entry_scene("v67.1 LocationRoot did not spawn the controlled player", scene_loader, scene_container, world_service)
	var expected_cell := grid.get_entrance_cell(str(start_result.get("entrance_id", "")))
	var controlled_cell: Vector2i = controlled.get("grid_position") as Vector2i
	if controlled_cell != expected_cell:
		return _fail_entry_scene("v67.1 player did not spawn at requested entrance: expected %s got %s" % [str(expected_cell), str(controlled_cell)], scene_loader, scene_container, world_service)

	scene_loader.unload_current_scene()
	await process_frame
	world_service.reset_world()
	scene_container.queue_free()
	return true


func _generated_world_data(seed: int) -> Dictionary:
	var generator: RefCounted = WorldGraphGeneratorScript.new()
	var result: Dictionary = generator.generate_world_data_result({
		"world_id": "v67_1_entry_world_%d" % seed,
		"world_seed": seed,
		"region_profile_id": PROFILE_ID,
	})
	if not bool(result.get("success", false)):
		_fail("v67.1 generated world failed: %s" % str(result.get("errors", [])))
		return {}
	return result.get("world_data", {}) as Dictionary


func _spawn_by_id(world_data: Dictionary, location_id: String, spawn_id: String) -> Dictionary:
	for spawn_value in (world_data.get("spawns", []) as Array):
		var spawn: Dictionary = spawn_value as Dictionary
		if str(spawn.get("location_id", "")) == location_id and str(spawn.get("spawn_id", "")) == spawn_id:
			return spawn
	return {}


func _first_edge_from(world_data: Dictionary, location_id: String) -> Dictionary:
	for edge_value in (world_data.get("exits", []) as Array):
		var edge: Dictionary = edge_value as Dictionary
		if str(edge.get("from_location_id", "")) == location_id:
			return edge
	return {}


func _location_has_walkable_entrance(location_data: Dictionary, entrance_id: String) -> bool:
	if location_data.is_empty() or entrance_id.is_empty():
		return false
	var grid: LocationGrid = LocationGrid.from_dictionary(location_data)
	if not grid.is_valid():
		return false
	var entrance: Dictionary = grid.get_entrance(entrance_id)
	if entrance.is_empty():
		return false
	var cell := grid.get_entrance_cell(entrance_id)
	return grid.in_bounds(cell) and grid.is_walkable(cell)


func _fail_entry_scene(message: String, scene_loader: Variant, scene_container: Node, world_service: Variant) -> bool:
	_fail(message)
	if scene_loader != null:
		scene_loader.unload_current_scene()
	if world_service != null:
		world_service.reset_world()
	if scene_container != null and is_instance_valid(scene_container):
		scene_container.queue_free()
	return false


func _fail(message: String) -> void:
	push_error(message)
	quit(1)

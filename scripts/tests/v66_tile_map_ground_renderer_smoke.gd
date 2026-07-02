extends SceneTree

const TileMapGroundRendererScript := preload("res://scripts/systems/scenes/tile_map_ground_renderer.gd")
const WorldGraphGeneratorScript := preload("res://scripts/systems/world/world_graph_generator.gd")

const MAPPING_PATH := "res://data/rendering/terrain_tile_map.json"
const GENERATED_WILD_SCENE_PATH := "res://scenes/locations/generated_wild_location.tscn"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if not _assert_renderer_builds_small_grid():
		return
	if not _assert_all_configured_terrain_ids_map():
		return
	if not _assert_unknown_terrain_fails():
		return

	var location_root_ok: bool = await _assert_location_root_uses_formal_ground()
	if not location_root_ok:
		return
	var generated_wild_ok: bool = await _assert_generated_wild_uses_formal_ground()
	if not generated_wild_ok:
		return

	print("v66 tile map ground renderer smoke test passed")
	quit(0)


func _assert_renderer_builds_small_grid() -> bool:
	var grid: LocationGrid = LocationGrid.from_dictionary(_small_location_data(false))
	if not grid.is_valid():
		_fail("v66 small LocationGrid is invalid")
		return false

	var renderer: Node = TileMapGroundRendererScript.new()
	root.add_child(renderer)
	if not bool(renderer.call("configure", MAPPING_PATH)):
		return _fail_with_renderer("v66 renderer could not load terrain mapping", renderer)
	if not bool(renderer.call("rebuild_from_grid", grid)):
		return _fail_with_renderer("v66 renderer could not rebuild from a valid grid", renderer)

	var summary: Dictionary = renderer.call("get_render_summary") as Dictionary
	if str(summary.get("renderer", "")) != "TileMapLayer":
		return _fail_with_renderer("v66 renderer summary is not TileMapLayer", renderer)
	if int(summary.get("width", 0)) != grid.width or int(summary.get("height", 0)) != grid.height:
		return _fail_with_renderer("v66 renderer summary size does not match grid", renderer)
	if int(summary.get("mapped_cell_count", 0)) != grid.width * grid.height:
		return _fail_with_renderer("v66 renderer did not map every cell", renderer)
	if int(summary.get("full_rebuild_count", 0)) != 1:
		return _fail_with_renderer("v66 renderer full_rebuild_count should be 1 after explicit rebuild", renderer)
	if bool(summary.get("is_debug_renderer_active", true)):
		return _fail_with_renderer("v66 renderer reports debug ground active by default", renderer)

	renderer.call("clear_renderer_state")
	var cleared_summary: Dictionary = renderer.call("get_render_summary") as Dictionary
	if bool(cleared_summary.get("is_ready", true)) or int(cleared_summary.get("mapped_cell_count", -1)) != 0:
		return _fail_with_renderer("v66 renderer clear state interface did not reset readiness and mapped cells", renderer)

	renderer.queue_free()
	return true


func _assert_all_configured_terrain_ids_map() -> bool:
	var mapping: Dictionary = _load_json_resource(MAPPING_PATH)
	var terrains: Dictionary = mapping.get("terrains", {}) as Dictionary
	if terrains.is_empty():
		_fail("v66 terrain mapping has no terrain ids")
		return false

	var symbols := "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
	if terrains.size() > symbols.length():
		_fail("v66 test symbol pool is too small for terrain mapping")
		return false

	var terrain_defs: Dictionary = {}
	var row := ""
	var index := 0
	for terrain_id_value in terrains.keys():
		var terrain_id := str(terrain_id_value)
		var key := symbols.substr(index, 1)
		terrain_defs[key] = { "id": terrain_id, "walkable": true }
		row += key
		index += 1

	var grid: LocationGrid = LocationGrid.from_dictionary({
		"id": "v66_all_configured_terrains",
		"display_name": "v66 all configured terrains",
		"size": { "width": row.length(), "height": 1 },
		"tile_size": 32,
		"tiles": [row],
		"terrain": terrain_defs,
		"entrances": [{ "id": "start", "grid_position": { "x": 0, "y": 0 }, "facing": "right" }],
	})
	if not grid.is_valid():
		_fail("v66 all-terrain LocationGrid is invalid")
		return false

	var renderer: Node = TileMapGroundRendererScript.new()
	root.add_child(renderer)
	if not bool(renderer.call("configure", MAPPING_PATH)):
		return _fail_with_renderer("v66 all-terrain renderer could not load mapping", renderer)
	if not bool(renderer.call("rebuild_from_grid", grid)):
		return _fail_with_renderer("v66 configured terrain id was not mapped", renderer)
	if int((renderer.call("get_render_summary") as Dictionary).get("mapped_cell_count", 0)) != row.length():
		return _fail_with_renderer("v66 all-terrain mapped count mismatch", renderer)
	renderer.queue_free()
	return true


func _assert_unknown_terrain_fails() -> bool:
	var grid: LocationGrid = LocationGrid.from_dictionary({
		"id": "v66_unknown_terrain",
		"display_name": "v66 unknown terrain",
		"size": { "width": 1, "height": 1 },
		"tile_size": 32,
		"tiles": ["u"],
		"terrain": {
			"u": { "id": "unmapped_v66_terrain", "walkable": true },
		},
		"entrances": [{ "id": "start", "grid_position": { "x": 0, "y": 0 }, "facing": "right" }],
	})
	var renderer: Node = TileMapGroundRendererScript.new()
	root.add_child(renderer)
	if not bool(renderer.call("configure", MAPPING_PATH)):
		return _fail_with_renderer("v66 unknown-terrain renderer could not load mapping", renderer)
	if bool(renderer.call("rebuild_from_grid", grid)):
		return _fail_with_renderer("v66 unknown terrain id was silently accepted", renderer)

	var summary: Dictionary = renderer.call("get_render_summary") as Dictionary
	if int(summary.get("unknown_terrain_count", 0)) <= 0:
		return _fail_with_renderer("v66 unknown terrain failure did not expose unknown_terrain_count", renderer)
	if bool(summary.get("is_ready", true)):
		return _fail_with_renderer("v66 renderer stayed ready after unknown terrain failure", renderer)

	renderer.queue_free()
	return true


func _assert_location_root_uses_formal_ground() -> bool:
	var scene_loader: Variant = _scene_loader()
	if scene_loader == null:
		_fail("v66 SceneLoader autoload is missing")
		return false
	var game_state: Variant = _game_state()
	var input_manager: Variant = _input_manager()
	if game_state == null or input_manager == null:
		_fail("v66 GameState or InputManager autoload is missing")
		return false

	game_state.start_new_session("v66_tile_map_ground_renderer_smoke")
	var scene_container := Node.new()
	scene_container.name = "V66SceneLoaderSmokeContainer"
	root.add_child(scene_container)
	scene_loader.configure(scene_container)
	scene_loader.unload_current_scene()
	scene_loader.set_pending_location_data(_small_location_data(true))
	var load_error: Error = scene_loader.load_location(GENERATED_WILD_SCENE_PATH, "start")
	if load_error != OK:
		return _fail_location_root_assertion("v66 LocationRoot scene load failed", scene_loader, scene_container)

	await process_frame
	var location_root: Node = scene_loader.current_scene
	if location_root == null or not is_instance_valid(location_root):
		return _fail_location_root_assertion("v66 LocationRoot did not become current scene", scene_loader, scene_container)
	if location_root.get_node_or_null("DebugTileRenderer") != null:
		return _fail_location_root_assertion("v66 LocationRoot created DebugTileRenderer in formal ground path", scene_loader, scene_container)
	if not location_root.has_method("get_ground_render_summary"):
		return _fail_location_root_assertion("v66 LocationRoot has no ground render summary", scene_loader, scene_container)

	var summary: Dictionary = location_root.get_ground_render_summary()
	if str(summary.get("renderer", "")) != "TileMapLayer":
		return _fail_location_root_assertion("v66 LocationRoot is not using TileMapLayer ground", scene_loader, scene_container)
	if int(summary.get("full_rebuild_count", 0)) != 1:
		return _fail_location_root_assertion("v66 LocationRoot should rebuild ground once on load", scene_loader, scene_container)
	if bool(summary.get("is_debug_renderer_active", true)):
		return _fail_location_root_assertion("v66 LocationRoot reports debug ground active by default", scene_loader, scene_container)

	input_manager.move_requested.emit(Vector2i.RIGHT)
	await process_frame
	var after_move_summary: Dictionary = location_root.get_ground_render_summary()
	if int(after_move_summary.get("full_rebuild_count", 0)) != int(summary.get("full_rebuild_count", 0)):
		return _fail_location_root_assertion("v66 player movement triggered a full ground rebuild", scene_loader, scene_container)

	if not location_root.has_method("set_cell_terrain"):
		return _fail_location_root_assertion("v66 LocationRoot has no local terrain update interface", scene_loader, scene_container)
	if not bool(location_root.call("set_cell_terrain", Vector2i(0, 0), "path")):
		return _fail_location_root_assertion("v66 LocationRoot could not update one ground cell", scene_loader, scene_container)
	var after_cell_update: Dictionary = location_root.get_ground_render_summary()
	if int(after_cell_update.get("full_rebuild_count", 0)) != int(summary.get("full_rebuild_count", 0)):
		return _fail_location_root_assertion("v66 single-cell terrain update triggered a full rebuild", scene_loader, scene_container)
	if int(after_cell_update.get("single_cell_update_count", 0)) != 1:
		return _fail_location_root_assertion("v66 single-cell terrain update counter did not increase", scene_loader, scene_container)

	location_root.set_debug_presentation_visible(true)
	await process_frame
	var debug_summary: Dictionary = location_root.get_ground_render_summary()
	if location_root.get_node_or_null("DebugTileRenderer") == null:
		return _fail_location_root_assertion("v66 debug ground renderer was not created when debug was enabled", scene_loader, scene_container)
	if not bool(debug_summary.get("is_debug_renderer_active", false)):
		return _fail_location_root_assertion("v66 debug renderer active flag did not update", scene_loader, scene_container)
	location_root.set_debug_presentation_visible(false)
	await process_frame
	if location_root.get_node_or_null("DebugTileRenderer") != null:
		return _fail_location_root_assertion("v66 debug ground renderer remained after debug was disabled", scene_loader, scene_container)

	scene_loader.unload_current_scene()
	await process_frame
	scene_container.queue_free()
	return true


func _assert_generated_wild_uses_formal_ground() -> bool:
	var world_service: Variant = _world_service()
	var scene_loader: Variant = _scene_loader()
	if world_service == null or scene_loader == null:
		_fail("v66 world service or scene loader autoload is missing")
		return false

	var generator: RefCounted = WorldGraphGeneratorScript.new()
	var result: Dictionary = generator.generate_world_data_result({
		"world_id": "v66_generated_world_smoke",
		"world_seed": 6601,
		"region_profile_id": "temperate_frontier",
	})
	if not bool(result.get("success", false)):
		_fail("v66 generated world graph failed: %s" % str(result.get("errors", [])))
		return false
	var world_data: Dictionary = result.get("world_data", {}) as Dictionary

	var scene_container := Node.new()
	scene_container.name = "V66GeneratedWildSceneContainer"
	root.add_child(scene_container)
	scene_loader.configure(scene_container)
	scene_loader.unload_current_scene()
	world_service.reset_world()

	var load_result: Dictionary = world_service.load_world_from_data(world_data)
	if not bool(load_result.get("success", false)):
		return _fail_world_assertion("v66 generated world could not load: %s" % str(load_result.get("error", "")), scene_loader, scene_container, world_service)
	var start_result: Dictionary = world_service.start_world(true)
	if not bool(start_result.get("success", false)):
		return _fail_world_assertion("v66 generated world could not start with scene load: %s" % str(start_result.get("error", "")), scene_loader, scene_container, world_service)

	await process_frame
	var location_root: Node = scene_loader.current_scene
	if location_root == null or not is_instance_valid(location_root):
		return _fail_world_assertion("v66 generated_wild did not load a LocationRoot scene", scene_loader, scene_container, world_service)
	if not location_root.has_method("get_ground_render_summary"):
		return _fail_world_assertion("v66 generated_wild LocationRoot has no ground render summary", scene_loader, scene_container, world_service)
	var summary: Dictionary = location_root.get_ground_render_summary()
	if str(summary.get("renderer", "")) != "TileMapLayer":
		return _fail_world_assertion("v66 generated_wild is not using TileMapLayer ground", scene_loader, scene_container, world_service)
	if int(summary.get("mapped_cell_count", 0)) <= 0 or int(summary.get("unknown_terrain_count", 0)) != 0:
		return _fail_world_assertion("v66 generated_wild ground mapping summary is invalid: %s" % str(summary), scene_loader, scene_container, world_service)
	if location_root.get_node_or_null("DebugTileRenderer") != null:
		return _fail_world_assertion("v66 generated_wild created DebugTileRenderer in formal ground path", scene_loader, scene_container, world_service)

	scene_loader.unload_current_scene()
	await process_frame
	world_service.reset_world()
	scene_container.queue_free()
	return true


func _small_location_data(with_player: bool) -> Dictionary:
	var characters: Array = []
	if with_player:
		characters.append({
			"id": "debug_player",
			"source": "res://data/characters/debug_player.json",
			"spawn_at_entrance": true,
			"facing": "right",
		})
	return {
		"id": "test_field",
		"display_name": "v66 renderer location",
		"size": { "width": 4, "height": 3 },
		"tile_size": 32,
		"tiles": [
			"gggg",
			"gpgw",
			"gggg",
		],
		"terrain": {
			"g": { "id": "grass", "walkable": true },
			"p": { "id": "path", "walkable": true },
			"w": { "id": "water", "walkable": false },
		},
		"entrances": [{ "id": "start", "grid_position": { "x": 1, "y": 1 }, "facing": "right" }],
		"objects": [],
		"characters": characters,
		"state": {},
	}


func _load_json_resource(resource_path: String) -> Dictionary:
	var file := FileAccess.open(resource_path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		return (parsed as Dictionary).duplicate(true)
	return {}


func _fail_with_renderer(message: String, renderer: Node) -> bool:
	if renderer != null and is_instance_valid(renderer):
		renderer.queue_free()
	_fail(message)
	return false


func _fail_location_root_assertion(message: String, scene_loader: Variant, scene_container: Node) -> bool:
	if scene_loader != null:
		scene_loader.unload_current_scene()
	if scene_container != null and is_instance_valid(scene_container):
		scene_container.queue_free()
	_fail(message)
	return false


func _fail_world_assertion(message: String, scene_loader: Variant, scene_container: Node, world_service: Variant) -> bool:
	if scene_loader != null:
		scene_loader.unload_current_scene()
	if world_service != null:
		world_service.reset_world()
	if scene_container != null and is_instance_valid(scene_container):
		scene_container.queue_free()
	_fail(message)
	return false


func _scene_loader() -> Variant:
	return root.get_node_or_null("SceneLoader")


func _world_service() -> Variant:
	return root.get_node_or_null("WorldTransitionService")


func _game_state() -> Variant:
	return root.get_node_or_null("GameState")


func _input_manager() -> Variant:
	return root.get_node_or_null("InputManager")


func _fail(message: String) -> void:
	push_error(message)
	quit(1)

extends SceneTree

const RegionMapGeneratorScript := preload("res://scripts/systems/world/region_map_generator.gd")
const WorldGenerationProfileScript := preload("res://scripts/systems/world/world_generation_profile.gd")
const WorldGraphGeneratorScript := preload("res://scripts/systems/world/world_graph_generator.gd")
const WildTerrainGeneratorScript := preload("res://scripts/systems/terrain/wild_terrain_generator.gd")

const PROFILE_ID := "temperate_frontier"
const WORLD_SEED := 6701


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if not _assert_region_map_seed_behavior():
		return
	if not _assert_world_graph_uses_region_map():
		return
	if not _assert_generated_wild_receives_region_patch():
		return
	if not _assert_unsupported_profile_fails():
		return

	print("v67 region map world context smoke test passed")
	quit(0)


func _assert_region_map_seed_behavior() -> bool:
	var generator: RefCounted = RegionMapGeneratorScript.new()
	var first_config := WorldGenerationProfileScript.resolve_generation_config({
		"world_id": "v67_region_seed_a",
		"world_seed": WORLD_SEED,
		"region_profile_id": PROFILE_ID,
	})
	var second_config := WorldGenerationProfileScript.resolve_generation_config({
		"world_id": "v67_region_seed_b",
		"world_seed": WORLD_SEED,
		"region_profile_id": PROFILE_ID,
	})
	var different_config := WorldGenerationProfileScript.resolve_generation_config({
		"world_id": "v67_region_seed_c",
		"world_seed": WORLD_SEED + 11,
		"region_profile_id": PROFILE_ID,
	})
	var first_map: Dictionary = generator.generate_region_map(first_config)
	var second_map: Dictionary = generator.generate_region_map(second_config)
	var different_map: Dictionary = generator.generate_region_map(different_config)
	if not generator.validate_region_map(first_map).is_empty():
		_fail("v67 RegionMap validation failed: %s" % str(generator.validate_region_map(first_map)))
		return false
	if generator.fingerprint(first_map) != generator.fingerprint(second_map):
		_fail("v67 RegionMap is not deterministic for the same seed")
		return false
	if generator.fingerprint(first_map) == generator.fingerprint(different_map):
		_fail("v67 RegionMap did not change for a different seed")
		return false
	for layer_name in ["elevation_map", "moisture_map", "water_map", "forest_map", "rock_map"]:
		if not _assert_continuous_numeric_layer(first_map, layer_name):
			return false
	if not _assert_biomes_derive_from_layers(first_map):
		return false
	return true


func _assert_world_graph_uses_region_map() -> bool:
	var result := _generated_world_result(WORLD_SEED)
	if not bool(result.get("success", false)):
		_fail("v67 world graph generation failed: %s" % str(result.get("errors", [])))
		return false
	var world_data: Dictionary = result.get("world_data", {}) as Dictionary
	var region_map: Dictionary = world_data.get("region_map", {}) as Dictionary
	if region_map.is_empty():
		_fail("v67 generated world_data has no RegionMap")
		return false
	var metadata: Dictionary = world_data.get("generator_metadata", {}) as Dictionary
	if not bool(metadata.get("profiles_are_region_derived", false)):
		_fail("v67 world generator metadata does not expose region-derived profiles")
		return false
	var profile_map: Dictionary = WorldGenerationProfileScript.resolve_generation_config({
		"world_seed": WORLD_SEED,
		"region_profile_id": PROFILE_ID,
	}).get("biome_profile_map", {}) as Dictionary
	var location_by_id: Dictionary = {}
	for location_value in (world_data.get("locations", []) as Array):
		var location: Dictionary = location_value as Dictionary
		var location_id := str(location.get("location_id", ""))
		location_by_id[location_id] = location
		if not _assert_node_has_region_context(location, region_map, profile_map):
			return false
	for edge_value in (world_data.get("exits", []) as Array):
		if not _assert_edge_has_region_context(edge_value as Dictionary, location_by_id):
			return false
	return true


func _assert_generated_wild_receives_region_patch() -> bool:
	var result := _generated_world_result(WORLD_SEED + 3)
	if not bool(result.get("success", false)):
		_fail("v67 world graph generation for registry test failed: %s" % str(result.get("errors", [])))
		return false
	var world_data: Dictionary = result.get("world_data", {}) as Dictionary
	var world_service: Variant = root.get_node_or_null("WorldTransitionService")
	if world_service == null:
		_fail("v67 WorldTransitionService autoload is missing")
		return false
	world_service.reset_world()
	var load_result: Dictionary = world_service.load_world_from_data(world_data)
	if not bool(load_result.get("success", false)):
		_fail("v67 generated world failed to load: %s" % str(load_result.get("error", "")))
		return false
	var start_result: Dictionary = world_service.start_world(false)
	if not bool(start_result.get("success", false)):
		_fail("v67 generated world failed to start: %s" % str(start_result.get("error", "")))
		return false
	var start_location_id := str(world_data.get("start_location_id", ""))
	var wild_data: Dictionary = world_service.get_registered_location_data(start_location_id)
	if wild_data.is_empty():
		_fail("v67 generated_wild start location was not materialized")
		return false
	var summary: Dictionary = wild_data.get("generation_summary", {}) as Dictionary
	if not bool(summary.get("region_patch_applied", false)):
		_fail("v67 generated_wild did not apply RegionPatch")
		return false
	var patch: Dictionary = summary.get("region_patch", {}) as Dictionary
	if patch.is_empty():
		_fail("v67 generated_wild summary has no RegionPatch")
		return false
	var start_spec := _location_by_id(world_data, start_location_id)
	if str(patch.get("center_biome", "")) != str(start_spec.get("region_biome", "")):
		_fail("v67 generated_wild RegionPatch does not match node biome")
		return false
	world_service.reset_world()
	return true


func _assert_unsupported_profile_fails() -> bool:
	var generator: RefCounted = WorldGraphGeneratorScript.new()
	var result: Dictionary = generator.generate_world_data_result({
		"world_id": "v67_bad_profile_world",
		"world_seed": WORLD_SEED,
		"region_profile_id": PROFILE_ID,
		"biome_profile_map": {
			"plain": ["missing_profile"],
		},
	})
	if bool(result.get("success", false)):
		_fail("v67 unsupported biome profile unexpectedly succeeded")
		return false
	var errors_text := str(result.get("errors", []))
	if not errors_text.contains("unsupported wild terrain profile"):
		_fail("v67 unsupported biome profile did not report explicit failure: %s" % errors_text)
		return false

	var terrain_generator: RefCounted = WildTerrainGeneratorScript.new()
	var blueprint: RefCounted = terrain_generator.generate_blueprint({
		"seed": WORLD_SEED,
		"terrain_profile_id": "missing_profile",
		"size": { "width": 32, "height": 32 },
	})
	var terrain_errors: Array[String] = terrain_generator.validate_blueprint(blueprint)
	if terrain_errors.is_empty() or not str(terrain_errors).contains("unsupported wild terrain profile"):
		_fail("v67 WildTerrainGenerator did not reject an unsupported profile: %s" % str(terrain_errors))
		return false
	return true


func _generated_world_result(seed: int) -> Dictionary:
	var generator: RefCounted = WorldGraphGeneratorScript.new()
	return generator.generate_world_data_result({
		"world_id": "v67_region_world_%d" % seed,
		"world_seed": seed,
		"region_profile_id": PROFILE_ID,
	})


func _assert_node_has_region_context(location: Dictionary, region_map: Dictionary, profile_map: Dictionary) -> bool:
	var location_id := str(location.get("location_id", ""))
	if (location.get("region_position", {}) as Dictionary).is_empty():
		_fail("v67 world node missing region_position: %s" % location_id)
		return false
	if str(location.get("region_biome", "")).is_empty():
		_fail("v67 world node missing region_biome: %s" % location_id)
		return false
	if (location.get("region_patch", {}) as Dictionary).is_empty():
		_fail("v67 world node missing RegionPatch: %s" % location_id)
		return false
	var position := _cell_from_dict(location.get("region_position", {}) as Dictionary)
	var map_biome := _map_string(region_map.get("biome_map", []) as Array, position)
	var node_biome := str(location.get("region_biome", ""))
	if node_biome != map_biome:
		_fail("v67 world node biome does not match RegionMap: %s" % location_id)
		return false
	var patch: Dictionary = location.get("region_patch", {}) as Dictionary
	if str(patch.get("center_biome", "")) != node_biome:
		_fail("v67 world node RegionPatch center biome mismatch: %s" % location_id)
		return false
	var allowed_profiles: Array = profile_map.get(node_biome, []) as Array
	if not allowed_profiles.has(str(location.get("generator_profile_id", ""))):
		_fail("v67 generator_profile_id is not derived from region_biome: %s" % location_id)
		return false
	return true


func _assert_edge_has_region_context(edge: Dictionary, location_by_id: Dictionary) -> bool:
	var exit_id := str(edge.get("exit_id", ""))
	var from_location_id := str(edge.get("from_location_id", ""))
	var target_location_id := str(edge.get("target_location_id", ""))
	var from_node: Dictionary = location_by_id.get(from_location_id, {}) as Dictionary
	var target_node: Dictionary = location_by_id.get(target_location_id, {}) as Dictionary
	if from_node.is_empty() or target_node.is_empty():
		_fail("v67 edge references missing location node: %s" % exit_id)
		return false
	if (edge.get("from_region_position", {}) as Dictionary).is_empty() or (edge.get("to_region_position", {}) as Dictionary).is_empty():
		_fail("v67 edge missing region positions: %s" % exit_id)
		return false
	if str(edge.get("from_biome", "")) != str(from_node.get("region_biome", "")):
		_fail("v67 edge from_biome does not match source node: %s" % exit_id)
		return false
	if str(edge.get("to_biome", "")) != str(target_node.get("region_biome", "")):
		_fail("v67 edge to_biome does not match target node: %s" % exit_id)
		return false
	var expected_transition := "%s_to_%s" % [str(edge.get("from_biome", "")), str(edge.get("to_biome", ""))]
	if str(edge.get("transition_kind", "")) != expected_transition:
		_fail("v67 edge transition_kind is not biome-derived: %s" % exit_id)
		return false
	var metadata: Dictionary = edge.get("metadata", {}) as Dictionary
	if str(metadata.get("transition_kind", "")) != expected_transition:
		_fail("v67 edge metadata transition_kind mismatch: %s" % exit_id)
		return false
	if (metadata.get("region_from", {}) as Dictionary).is_empty() or (metadata.get("region_to", {}) as Dictionary).is_empty():
		_fail("v67 edge metadata missing region endpoints: %s" % exit_id)
		return false
	return true


func _assert_continuous_numeric_layer(region_map: Dictionary, layer_name: String) -> bool:
	var map_data: Array = region_map.get(layer_name, []) as Array
	var width := int(region_map.get("width", 0))
	var height := int(region_map.get("height", 0))
	var delta_total := 0.0
	var sample_count := 0
	for y in range(height):
		for x in range(width):
			var cell := Vector2i(x, y)
			for offset_value in [Vector2i.RIGHT, Vector2i.DOWN]:
				var offset: Vector2i = offset_value as Vector2i
				var other := cell + offset
				if other.x >= width or other.y >= height:
					continue
				delta_total += absf(_map_float(map_data, cell) - _map_float(map_data, other))
				sample_count += 1
	var average_delta := delta_total / maxf(1.0, float(sample_count))
	if average_delta >= 0.34:
		_fail("v67 RegionMap layer is too discontinuous: %s avg_delta=%.3f" % [layer_name, average_delta])
		return false
	return true


func _assert_biomes_derive_from_layers(region_map: Dictionary) -> bool:
	var width := int(region_map.get("width", 0))
	var height := int(region_map.get("height", 0))
	for y in range(height):
		for x in range(width):
			var cell := Vector2i(x, y)
			var biome := _map_string(region_map.get("biome_map", []) as Array, cell)
			var elevation := _map_float(region_map.get("elevation_map", []) as Array, cell)
			var moisture := _map_float(region_map.get("moisture_map", []) as Array, cell)
			var water := _map_float(region_map.get("water_map", []) as Array, cell)
			var forest := _map_float(region_map.get("forest_map", []) as Array, cell)
			var rock := _map_float(region_map.get("rock_map", []) as Array, cell)
			match biome:
				"sea":
					if water < 0.76 or elevation > 0.46:
						_fail("v67 sea biome is not derived from water/elevation layers")
						return false
				"coast":
					if not _near_biome(region_map.get("biome_map", []) as Array, cell, "sea", 2):
						_fail("v67 coast biome is not near sea")
						return false
				"riverbank":
					if water < 0.42 or moisture < 0.45:
						_fail("v67 riverbank biome is not derived from water/moisture layers")
						return false
				"rocky":
					if rock < 0.66 or elevation < 0.52:
						_fail("v67 rocky biome is not derived from rock/elevation layers")
						return false
				"foothill":
					if elevation < 0.63:
						_fail("v67 foothill biome is not derived from elevation layer")
						return false
				"forest":
					if forest < 0.58 or moisture < 0.38:
						_fail("v67 forest biome is not derived from forest/moisture layers")
						return false
	return true


func _location_by_id(world_data: Dictionary, location_id: String) -> Dictionary:
	for location_value in (world_data.get("locations", []) as Array):
		var location: Dictionary = location_value as Dictionary
		if str(location.get("location_id", "")) == location_id:
			return location
	return {}


func _map_float(map_data: Array, cell: Vector2i) -> float:
	if cell.y < 0 or cell.y >= map_data.size():
		return 0.0
	var row: Array = map_data[cell.y] as Array
	if cell.x < 0 or cell.x >= row.size():
		return 0.0
	return float(row[cell.x])


func _map_string(map_data: Array, cell: Vector2i) -> String:
	if cell.y < 0 or cell.y >= map_data.size():
		return ""
	var row: Array = map_data[cell.y] as Array
	if cell.x < 0 or cell.x >= row.size():
		return ""
	return str(row[cell.x])


func _near_biome(biome_map: Array, cell: Vector2i, biome_id: String, radius: int) -> bool:
	for y in range(cell.y - radius, cell.y + radius + 1):
		for x in range(cell.x - radius, cell.x + radius + 1):
			var other := Vector2i(x, y)
			if other == cell:
				continue
			if _map_string(biome_map, other) == biome_id:
				return true
	return false


func _cell_from_dict(value: Dictionary) -> Vector2i:
	return Vector2i(int(value.get("x", -1)), int(value.get("y", -1)))


func _fail(message: String) -> void:
	push_error(message)
	quit(1)

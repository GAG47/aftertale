extends SceneTree

const WildTerrainGeneratorScript := preload("res://scripts/systems/terrain/wild_terrain_generator.gd")
const WildLocationCompilerScript := preload("res://scripts/systems/terrain/wild_location_compiler.gd")


func _initialize() -> void:
	_run()


func _run() -> void:
	var source_data: Dictionary = _load_json_resource("res://data/locations/test_wild_plain.json")
	if source_data.is_empty():
		_fail("v62 source location could not be loaded")
		return
	var generator_data: Dictionary = source_data.get("generator", {}) as Dictionary

	var generator: RefCounted = WildTerrainGeneratorScript.new()
	var first: RefCounted = generator.generate_blueprint(generator_data)
	var second: RefCounted = generator.generate_blueprint(generator_data)
	if first.fingerprint() != second.fingerprint():
		_fail("v62 wild terrain is not deterministic for the same seed/profile/size")
		return

	var changed_config := generator_data.duplicate(true)
	changed_config["seed"] = int(generator_data.get("seed", 6201)) + 1
	var changed: RefCounted = generator.generate_blueprint(changed_config)
	if first.fingerprint() == changed.fingerprint():
		_fail("v62 wild terrain did not change for a different seed")
		return

	var validation_errors: Array[String] = generator.validate_blueprint(first)
	if not validation_errors.is_empty():
		_fail("v62 blueprint validation errors: %s" % str(validation_errors))
		return

	if first.width != int((generator_data.get("size", {}) as Dictionary).get("width", 64)):
		_fail("v62 width mismatch")
		return
	if first.height != int((generator_data.get("size", {}) as Dictionary).get("height", 64)):
		_fail("v62 height mismatch")
		return
	if first.height_map.is_empty() or first.moisture_map.is_empty() or first.tile_map.is_empty() or first.blocker_map.is_empty():
		_fail("v62 main layer maps are missing")
		return
	if first.natural_objects == null:
		_fail("v62 blueprint is missing natural_objects")
		return
	if first.spawn_candidates.is_empty():
		_fail("v62 generated no spawn candidates")
		return
	if first.exit_candidates.is_empty():
		_fail("v62 generated no exit candidates for configured exit hints")
		return

	var summary: Dictionary = first.debug_summary
	var passable_ratio := float(summary.get("passable_ratio", 0.0))
	if passable_ratio < 0.35 or passable_ratio > 0.90:
		_fail("v62 passable ratio out of range: %.3f" % passable_ratio)
		return
	if not (summary.get("object_counts", {}) is Dictionary):
		_fail("v62 debug summary missing object_counts")
		return
	if not (summary.get("tile_counts", {}) is Dictionary):
		_fail("v62 debug summary missing tile_counts")
		return
	if not (summary.get("biome_counts", {}) is Dictionary):
		_fail("v62 debug summary missing biome_counts")
		return
	if not summary.has("wetland_ratio"):
		_fail("v62 debug summary missing wetland_ratio")
		return
	if float(summary.get("water_ratio", 0.0)) <= 0.01:
		_fail("v62 plain profile generated too little water: %.3f" % float(summary.get("water_ratio", 0.0)))
		return
	if float(summary.get("wetland_ratio", 0.0)) <= 0.01:
		_fail("v62 plain profile generated too little wetland: %.3f" % float(summary.get("wetland_ratio", 0.0)))
		return

	var riverbank_config := generator_data.duplicate(true)
	riverbank_config["terrain_profile_id"] = "riverbank"
	var riverbank: RefCounted = generator.generate_blueprint(riverbank_config)
	var riverbank_summary: Dictionary = riverbank.debug_summary
	if float(riverbank_summary.get("water_ratio", 0.0)) <= 0.02:
		_fail("v62 riverbank profile generated too little water: %.3f" % float(riverbank_summary.get("water_ratio", 0.0)))
		return
	if float(riverbank_summary.get("wetland_ratio", 0.0)) <= 0.01:
		_fail("v62 riverbank profile generated too little wetland: %.3f" % float(riverbank_summary.get("wetland_ratio", 0.0)))
		return

	var forest_config := generator_data.duplicate(true)
	forest_config["terrain_profile_id"] = "forest_edge"
	var forest_edge: RefCounted = generator.generate_blueprint(forest_config)
	if forest_edge.fingerprint() == first.fingerprint():
		_fail("v62 forest_edge profile did not change the terrain fingerprint")
		return

	var foothill_config := generator_data.duplicate(true)
	foothill_config["terrain_profile_id"] = "foothill"
	var foothill: RefCounted = generator.generate_blueprint(foothill_config)
	if foothill.fingerprint() == first.fingerprint():
		_fail("v62 foothill profile did not change the terrain fingerprint")
		return

	var compiler: RefCounted = WildLocationCompilerScript.new()
	var location_data: Dictionary = compiler.generate_location(source_data)
	var compile_errors: Array[String] = compiler.validate_location(location_data)
	if not compile_errors.is_empty():
		_fail("v62 compiled location validation errors: %s" % str(compile_errors))
		return

	var grid: LocationGrid = LocationGrid.from_dictionary(location_data)
	if not grid.is_valid():
		_fail("v62 compiled LocationGrid is invalid")
		return
	var spawn_cell := grid.get_entrance_cell("wild_spawn")
	if not grid.in_bounds(spawn_cell) or not grid.is_walkable(spawn_cell):
		_fail("v62 wild_spawn entrance is missing or blocked")
		return
	if (location_data.get("exits", []) as Array).is_empty():
		_fail("v62 compiled location has no runtime exit")
		return
	if (location_data.get("wild_terrain_blueprint", {}) as Dictionary).is_empty():
		_fail("v62 compiled location did not expose the wild terrain blueprint")
		return

	print("v62 wild terrain smoke test passed (plain water=%.3f wetland=%.3f, riverbank water=%.3f wetland=%.3f)" % [
		float(summary.get("water_ratio", 0.0)),
		float(summary.get("wetland_ratio", 0.0)),
		float(riverbank_summary.get("water_ratio", 0.0)),
		float(riverbank_summary.get("wetland_ratio", 0.0)),
	])
	quit(0)


func _load_json_resource(resource_path: String) -> Dictionary:
	var file := FileAccess.open(resource_path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		return (parsed as Dictionary).duplicate(true)
	return {}


func _fail(message: String) -> void:
	push_error(message)
	quit(1)

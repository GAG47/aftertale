extends SceneTree

const WildTerrainGeneratorScript := preload("res://scripts/systems/terrain/wild_terrain_generator.gd")
const WildLocationCompilerScript := preload("res://scripts/systems/terrain/wild_location_compiler.gd")
const WILD_SOURCE_PATH := "res://data/locations/smoke_generated_wild.json"


func _initialize() -> void:
	_run()


func _run() -> void:
	var source_data: Dictionary = _load_json_resource(WILD_SOURCE_PATH)
	if source_data.is_empty():
		_fail("v63 source location could not be loaded")
		return
	var generator_data: Dictionary = source_data.get("generator", {}) as Dictionary

	var generator: RefCounted = WildTerrainGeneratorScript.new()
	var blueprint: RefCounted = generator.generate_blueprint(generator_data)
	var validation_errors: Array[String] = generator.validate_blueprint(blueprint)
	if not validation_errors.is_empty():
		_fail("v63 blueprint validation errors: %s" % str(validation_errors))
		return

	if not _map_has_size(blueprint.elevation_map, blueprint.width, blueprint.height):
		_fail("v63 elevation_map is missing or has the wrong size")
		return
	if not _map_has_size(blueprint.slope_map, blueprint.width, blueprint.height):
		_fail("v63 slope_map is missing or has the wrong size")
		return
	if not _map_has_size(blueprint.ridge_map, blueprint.width, blueprint.height):
		_fail("v63 ridge_map is missing or has the wrong size")
		return
	if not _map_has_size(blueprint.landform_map, blueprint.width, blueprint.height):
		_fail("v63.2 landform_map is missing or has the wrong size")
		return

	var summary: Dictionary = blueprint.debug_summary
	if not (summary.get("elevation_counts", {}) is Dictionary):
		_fail("v63 debug summary missing elevation_counts")
		return
	if not (summary.get("landform_counts", {}) is Dictionary):
		_fail("v63.2 debug summary missing landform_counts")
		return
	var lowland_ratio := float(summary.get("lowland_ratio", 0.0))
	var highland_ratio := float(summary.get("highland_ratio", 0.0))
	var slope_ratio := float(summary.get("slope_ratio", 0.0))
	var ridge_ratio := float(summary.get("ridge_ratio", 0.0))
	var woodland_ratio := float(summary.get("woodland_ratio", 0.0))
	var open_ground_ratio := float(summary.get("open_ground_ratio", 0.0))
	var upland_landform_ratio := float(summary.get("upland_landform_ratio", 0.0))
	var wetland_landform_ratio := float(summary.get("landform_wetland_ratio", 0.0))
	if lowland_ratio <= 0.02:
		_fail("v63 generated too little lowland: %.3f" % lowland_ratio)
		return
	if highland_ratio + slope_ratio + ridge_ratio <= 0.06:
		_fail("v63 generated too little elevated terrain: high=%.3f slope=%.3f ridge=%.3f" % [highland_ratio, slope_ratio, ridge_ratio])
		return
	if slope_ratio <= 0.01:
		_fail("v63 generated too little slope terrain: %.3f" % slope_ratio)
		return
	if ridge_ratio <= 0.003:
		_fail("v63 generated too little ridge terrain: %.3f" % ridge_ratio)
		return
	if float(summary.get("slope_walk_cost_avg", 0.0)) <= float(summary.get("flat_walk_cost_avg", 0.0)):
		_fail("v63 slope walk cost did not exceed flat walk cost: slope=%.3f flat=%.3f" % [
			float(summary.get("slope_walk_cost_avg", 0.0)),
			float(summary.get("flat_walk_cost_avg", 0.0)),
		])
		return
	var tile_counts: Dictionary = summary.get("tile_counts", {}) as Dictionary
	var dirt_ratio := float(int(tile_counts.get("dirt", 0))) / maxf(1.0, float(blueprint.width * blueprint.height))
	if dirt_ratio > 0.16:
		_fail("v63.1 dirt visual coverage is too high: %.3f" % dirt_ratio)
		return
	var semantic_ground_count := int(tile_counts.get("lowland_grass", 0)) + int(tile_counts.get("highland_grass", 0)) + int(tile_counts.get("slope_grass", 0))
	if semantic_ground_count <= 0:
		_fail("v63.2 generated no semantic elevation ground tiles")
		return
	if upland_landform_ratio <= 0.04:
		_fail("v63.2 generated too little upland landform: %.3f" % upland_landform_ratio)
		return
	if woodland_ratio + open_ground_ratio <= 0.03:
		_fail("v63.2 generated too little woodland/open landform contrast: wood=%.3f open=%.3f" % [woodland_ratio, open_ground_ratio])
		return
	var largest_lowland := _largest_component(blueprint.landform_map, ["lowland", "wetland"])
	var largest_upland := _largest_component(blueprint.landform_map, ["upland", "hillside", "rocky_upland", "rocky_slope", "upland_ridge", "rocky_ridge"])
	var largest_woodland := _largest_component(blueprint.landform_map, ["woodland"])
	if largest_lowland < 20:
		_fail("v63.2 lowland/wetland landform is too fragmented: largest=%d" % largest_lowland)
		return
	if largest_upland < 20:
		_fail("v63.2 upland landform is too fragmented: largest=%d" % largest_upland)
		return
	if woodland_ratio > 0.01 and largest_woodland < 10:
		_fail("v63.2 woodland landform is too fragmented: largest=%d" % largest_woodland)
		return

	if blueprint.natural_objects.is_empty():
		_fail("v63 blueprint generated no natural objects")
		return
	var saw_elevation_source := false
	var saw_landform_source := false
	for object_value in blueprint.natural_objects:
		var object_data: Dictionary = object_value as Dictionary
		var layers: Dictionary = object_data.get("source_layers", {}) as Dictionary
		if layers.has("elevation") and layers.has("slope") and layers.has("ridge"):
			saw_elevation_source = true
		if layers.has("landform"):
			saw_landform_source = true
	if not saw_elevation_source:
		_fail("v63 natural object source_layers did not include elevation semantics")
		return
	if not saw_landform_source:
		_fail("v63.2 natural object source_layers did not include landform semantics")
		return

	var compiler: RefCounted = WildLocationCompilerScript.new()
	var location_data: Dictionary = compiler.generate_location(source_data)
	var compile_errors: Array[String] = compiler.validate_location(location_data)
	if not compile_errors.is_empty():
		_fail("v63 compiled location validation errors: %s" % str(compile_errors))
		return

	var overlay_count := 0
	for overlay_value in (location_data.get("floor_overlays", []) as Array):
		var overlay: Dictionary = overlay_value as Dictionary
		if str(overlay.get("type", "")).begins_with("elevation_"):
			overlay_count += 1
			if not overlay.has("drop_edges"):
				_fail("v63 elevation overlay missing drop_edges")
				return
			if not overlay.has("landform"):
				_fail("v63.2 elevation overlay missing landform metadata")
				return
	if overlay_count <= 0:
		_fail("v63 compiled location did not create elevation overlays")
		return

	var compiled_blueprint: Dictionary = location_data.get("wild_terrain_blueprint", {}) as Dictionary
	if (compiled_blueprint.get("elevation_map", []) as Array).is_empty():
		_fail("v63 compiled blueprint did not expose elevation_map")
		return
	if (compiled_blueprint.get("landform_map", []) as Array).is_empty():
		_fail("v63.2 compiled blueprint did not expose landform_map")
		return

	print("v63 semantic elevation smoke test passed (low=%.3f high=%.3f slope=%.3f ridge=%.3f upland=%.3f wetland_land=%.3f wood=%.3f open=%.3f semantic_tiles=%d low_comp=%d up_comp=%d wood_comp=%d slope_cost=%.3f flat_cost=%.3f dirt=%.3f overlays=%d)" % [
		lowland_ratio,
		highland_ratio,
		slope_ratio,
		ridge_ratio,
		upland_landform_ratio,
		wetland_landform_ratio,
		woodland_ratio,
		open_ground_ratio,
		semantic_ground_count,
		largest_lowland,
		largest_upland,
		largest_woodland,
		float(summary.get("slope_walk_cost_avg", 0.0)),
		float(summary.get("flat_walk_cost_avg", 0.0)),
		dirt_ratio,
		overlay_count,
	])
	quit(0)


func _largest_component(map_data: Array, accepted_ids: Array) -> int:
	var visited: Dictionary = {}
	var best := 0
	var height := map_data.size()
	if height <= 0:
		return 0
	var width := (map_data[0] as Array).size()
	var offsets: Array = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
	for y in range(height):
		for x in range(width):
			var start := Vector2i(x, y)
			var start_key := _cell_key(start)
			if visited.has(start_key):
				continue
			if not accepted_ids.has(_map_string(map_data, start)):
				continue
			var count := 0
			var frontier: Array = [start]
			visited[start_key] = true
			while not frontier.is_empty():
				var current: Vector2i = frontier.pop_back()
				count += 1
				for offset_value in offsets:
					var neighbor: Vector2i = current + (offset_value as Vector2i)
					if neighbor.x < 0 or neighbor.y < 0 or neighbor.x >= width or neighbor.y >= height:
						continue
					var neighbor_key := _cell_key(neighbor)
					if visited.has(neighbor_key):
						continue
					if not accepted_ids.has(_map_string(map_data, neighbor)):
						continue
					visited[neighbor_key] = true
					frontier.append(neighbor)
			best = maxi(best, count)
	return best


func _map_has_size(map_data: Array, width: int, height: int) -> bool:
	if map_data.size() != height:
		return false
	for row_value in map_data:
		var row: Array = row_value as Array
		if row.size() != width:
			return false
	return true


func _map_string(map_data: Array, cell: Vector2i) -> String:
	if cell.y < 0 or cell.y >= map_data.size():
		return ""
	var row: Array = map_data[cell.y] as Array
	if cell.x < 0 or cell.x >= row.size():
		return ""
	return str(row[cell.x])


func _cell_key(cell: Vector2i) -> String:
	return "%d,%d" % [cell.x, cell.y]


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

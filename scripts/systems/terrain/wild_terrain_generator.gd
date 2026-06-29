class_name WildTerrainGenerator
extends RefCounted

const WildTerrainBlueprintScript := preload("res://scripts/systems/terrain/wild_terrain_blueprint.gd")
const WildTerrainProfileScript := preload("res://scripts/systems/terrain/wild_terrain_profile.gd")

const DEFAULT_WIDTH := 64
const DEFAULT_HEIGHT := 64
const MIN_WIDTH := 16
const MIN_HEIGHT := 16
const MAX_SPAWN_CANDIDATES := 24
const MAX_EXIT_CANDIDATES_PER_HINT := 1

var _seed: int = 0
var _width: int = DEFAULT_WIDTH
var _height: int = DEFAULT_HEIGHT
var _profile: Dictionary = {}
var _profile_id: String = "plain"
var _region_patch: Dictionary = {}
var _spawn_hint: Dictionary = {}
var _exit_hints: Array = []
var _warnings: Array[String] = []
var _errors: Array[String] = []
var _height_map: Array = []
var _moisture_map: Array = []
var _roughness_map: Array = []
var _vegetation_map: Array = []
var _rock_map: Array = []
var _water_map: Array = []
var _elevation_map: Array = []
var _slope_map: Array = []
var _ridge_map: Array = []
var _landform_map: Array = []
var _biome_map: Array = []
var _tile_map: Array = []
var _blocker_map: Array = []
var _walk_cost_map: Array = []


func generate_blueprint(config: Dictionary) -> RefCounted:
	_configure(config)
	if not _errors.is_empty():
		return _failed_blueprint()
	_generate_natural_layers()
	_derive_elevation_semantics()
	_derive_landform_semantics()
	_derive_tiles()
	var natural_objects := _sample_natural_objects()
	_apply_natural_object_blockers(natural_objects)
	var spawn_candidates := _select_spawn_candidates()
	var exit_candidates := _select_exit_candidates(spawn_candidates)
	var summary := _build_debug_summary(natural_objects, spawn_candidates, exit_candidates)

	var blueprint: RefCounted = WildTerrainBlueprintScript.new()
	blueprint.width = _width
	blueprint.height = _height
	blueprint.seed = _seed
	blueprint.terrain_profile_id = _profile_id
	blueprint.profile = _profile.duplicate(true)
	blueprint.generation_metadata = {
		"generator": "wild_terrain",
		"algorithm": "layered_value_noise_with_blue_noise_object_sampling",
		"natural_layer_order": [
			"height_map",
			"moisture_map",
			"roughness_map",
			"vegetation_map",
			"rock_map",
			"water_map",
			"elevation_map",
			"slope_map",
			"ridge_map",
			"landform_map",
			"biome_map",
		],
		"elevation_semantics": "v63_lowland_midland_highland_slope_ridge",
		"landform_semantics": "v63_2_contiguous_lowland_upland_woodland_open_ground",
		"profiles_are_natural_parameters": true,
		"region_patch_applied": not _region_patch.is_empty(),
		"region_patch": _region_patch.duplicate(true),
		"spawn_hint_used_for_selection_only": not _spawn_hint.is_empty(),
		"exit_hints_used_for_selection_only": _exit_hints.size(),
	}
	blueprint.height_map = _height_map.duplicate(true)
	blueprint.moisture_map = _moisture_map.duplicate(true)
	blueprint.roughness_map = _roughness_map.duplicate(true)
	blueprint.vegetation_map = _vegetation_map.duplicate(true)
	blueprint.rock_map = _rock_map.duplicate(true)
	blueprint.water_map = _water_map.duplicate(true)
	blueprint.elevation_map = _elevation_map.duplicate(true)
	blueprint.slope_map = _slope_map.duplicate(true)
	blueprint.ridge_map = _ridge_map.duplicate(true)
	blueprint.landform_map = _landform_map.duplicate(true)
	blueprint.biome_map = _biome_map.duplicate(true)
	blueprint.tile_map = _tile_map.duplicate(true)
	blueprint.blocker_map = _blocker_map.duplicate(true)
	blueprint.walk_cost_map = _walk_cost_map.duplicate(true)
	blueprint.natural_objects = natural_objects.duplicate(true)
	blueprint.spawn_candidates = spawn_candidates.duplicate(true)
	blueprint.exit_candidates = exit_candidates.duplicate(true)
	blueprint.debug_summary = summary.duplicate(true)
	return blueprint


func validate_blueprint(blueprint: RefCounted) -> Array[String]:
	var errors: Array[String] = []
	if blueprint == null:
		return ["missing blueprint"]
	var debug_summary: Dictionary = blueprint.debug_summary as Dictionary
	for error_value in (debug_summary.get("generation_errors", []) as Array):
		errors.append(str(error_value))
	var generation_metadata: Dictionary = blueprint.generation_metadata as Dictionary
	for error_value in (generation_metadata.get("generation_errors", []) as Array):
		var error_text := str(error_value)
		if not errors.has(error_text):
			errors.append(error_text)
	if not errors.is_empty():
		return errors
	if blueprint.width <= 0 or blueprint.height <= 0:
		errors.append("invalid blueprint size")
	if not _map_has_size(blueprint.height_map, blueprint.width, blueprint.height):
		errors.append("height_map size mismatch")
	if not _map_has_size(blueprint.moisture_map, blueprint.width, blueprint.height):
		errors.append("moisture_map size mismatch")
	if not _map_has_size(blueprint.roughness_map, blueprint.width, blueprint.height):
		errors.append("roughness_map size mismatch")
	if not _map_has_size(blueprint.vegetation_map, blueprint.width, blueprint.height):
		errors.append("vegetation_map size mismatch")
	if not _map_has_size(blueprint.rock_map, blueprint.width, blueprint.height):
		errors.append("rock_map size mismatch")
	if not _map_has_size(blueprint.water_map, blueprint.width, blueprint.height):
		errors.append("water_map size mismatch")
	if not _map_has_size(blueprint.elevation_map, blueprint.width, blueprint.height):
		errors.append("elevation_map size mismatch")
	if not _map_has_size(blueprint.slope_map, blueprint.width, blueprint.height):
		errors.append("slope_map size mismatch")
	if not _map_has_size(blueprint.ridge_map, blueprint.width, blueprint.height):
		errors.append("ridge_map size mismatch")
	if not _map_has_size(blueprint.landform_map, blueprint.width, blueprint.height):
		errors.append("landform_map size mismatch")
	if not _map_has_size(blueprint.biome_map, blueprint.width, blueprint.height):
		errors.append("biome_map size mismatch")
	if not _map_has_size(blueprint.tile_map, blueprint.width, blueprint.height):
		errors.append("tile_map size mismatch")
	if not _map_has_size(blueprint.blocker_map, blueprint.width, blueprint.height):
		errors.append("blocker_map size mismatch")
	if not _map_has_size(blueprint.walk_cost_map, blueprint.width, blueprint.height):
		errors.append("walk_cost_map size mismatch")
	if not errors.is_empty():
		return errors

	var passable_count := 0
	var total: int = int(blueprint.width) * int(blueprint.height)
	for y in range(blueprint.height):
		for x in range(blueprint.width):
			if not bool((blueprint.blocker_map[y] as Array)[x]):
				passable_count += 1
	var passable_ratio := float(passable_count) / maxf(1.0, float(total))
	if passable_ratio < 0.35 or passable_ratio > 0.90:
		errors.append("passable ratio out of expected smoke range: %.3f" % passable_ratio)

	if blueprint.spawn_candidates.is_empty():
		errors.append("missing spawn candidates")
	for spawn_value in blueprint.spawn_candidates:
		var spawn: Dictionary = spawn_value as Dictionary
		var cell := _cell_from_dict(spawn.get("grid_position", {}) as Dictionary)
		if not blueprint.in_bounds(cell):
			errors.append("spawn candidate out of bounds: %s" % str(cell))
		elif blueprint.blocks_at(cell):
			errors.append("spawn candidate is blocked: %s" % str(cell))

	for exit_value in blueprint.exit_candidates:
		var exit_data: Dictionary = exit_value as Dictionary
		var cell := _cell_from_dict(exit_data.get("grid_position", {}) as Dictionary)
		if not blueprint.in_bounds(cell):
			errors.append("exit candidate out of bounds: %s" % str(cell))
		elif blueprint.blocks_at(cell):
			errors.append("exit candidate is blocked: %s" % str(cell))

	return errors


func _configure(config: Dictionary) -> void:
	var size: Dictionary = config.get("size", {}) as Dictionary
	_width = max(MIN_WIDTH, int(config.get("width", size.get("width", DEFAULT_WIDTH))))
	_height = max(MIN_HEIGHT, int(config.get("height", size.get("height", DEFAULT_HEIGHT))))
	_seed = int(config.get("seed", 6201))
	_profile_id = str(config.get("terrain_profile_id", config.get("profile", "plain")))
	_profile = WildTerrainProfileScript.get_profile(_profile_id)
	_region_patch = (config.get("region_patch", {}) as Dictionary).duplicate(true)
	_spawn_hint = (config.get("optional_spawn_hint", {}) as Dictionary).duplicate(true)
	_exit_hints = (config.get("optional_exit_hints", []) as Array).duplicate(true)
	_warnings.clear()
	_errors.clear()
	if _profile.is_empty():
		_errors.append("unsupported wild terrain profile: %s" % _profile_id)
	else:
		_profile_id = str(_profile.get("id", _profile_id))
		_apply_region_patch_to_profile()
	_height_map = _empty_grid(0.0)
	_moisture_map = _empty_grid(0.0)
	_roughness_map = _empty_grid(0.0)
	_vegetation_map = _empty_grid(0.0)
	_rock_map = _empty_grid(0.0)
	_water_map = _empty_grid(0.0)
	_elevation_map = _empty_grid("")
	_slope_map = _empty_grid(0.0)
	_ridge_map = _empty_grid(0.0)
	_landform_map = _empty_grid("")
	_biome_map = _empty_grid("")
	_tile_map = _empty_grid("")
	_blocker_map = _empty_grid(false)
	_walk_cost_map = _empty_grid(1.0)


func _apply_region_patch_to_profile() -> void:
	if _region_patch.is_empty() or _profile.is_empty():
		return
	var center_biome := str(_region_patch.get("center_biome", ""))
	var water_influence := clampf(float(_region_patch.get("water_influence", 0.0)), 0.0, 1.0)
	var coast_influence := clampf(float(_region_patch.get("coast_influence", 0.0)), 0.0, 1.0)
	var river_influence := clampf(float(_region_patch.get("river_influence", 0.0)), 0.0, 1.0)
	var forest_influence := clampf(float(_region_patch.get("forest_influence", 0.0)), 0.0, 1.0)
	var rock_influence := clampf(float(_region_patch.get("rock_influence", 0.0)), 0.0, 1.0)
	var moisture := clampf(float(_region_patch.get("average_moisture", 0.5)), 0.0, 1.0)
	var elevation := clampf(float(_region_patch.get("average_elevation", 0.5)), 0.0, 1.0)
	var water_bias := maxf(water_influence, maxf(coast_influence * 0.72, river_influence * 0.84))

	_profile["moisture_bias"] = clampf(float(_profile.get("moisture_bias", 0.5)) + (moisture - 0.5) * 0.28 + water_bias * 0.12, 0.0, 1.0)
	_profile["vegetation_bias"] = clampf(float(_profile.get("vegetation_bias", 0.5)) + (forest_influence - 0.5) * 0.22 + maxf(0.0, moisture - 0.5) * 0.10, 0.0, 1.0)
	_profile["rock_bias"] = clampf(float(_profile.get("rock_bias", 0.25)) + rock_influence * 0.18 + maxf(0.0, elevation - 0.55) * 0.16, 0.0, 1.0)
	_profile["base_height"] = clampf(float(_profile.get("base_height", 0.5)) + (elevation - 0.5) * 0.14 - water_bias * 0.06, 0.0, 1.0)
	_profile["water_level"] = clampf(float(_profile.get("water_level", 0.42)) + water_bias * 0.10 - maxf(0.0, elevation - 0.58) * 0.06, 0.0, 1.0)
	_profile["river_influence"] = clampf(float(_profile.get("river_influence", 0.0)) + river_influence * 0.62, 0.0, 1.0)
	_profile["pond_influence"] = clampf(float(_profile.get("pond_influence", 0.0)) + water_bias * 0.24, 0.0, 1.0)
	_profile["tree_density"] = clampf(float(_profile.get("tree_density", 0.0)) + forest_influence * 0.055 - rock_influence * 0.020, 0.0, 0.35)
	_profile["rock_density"] = clampf(float(_profile.get("rock_density", 0.0)) + rock_influence * 0.070 + maxf(0.0, elevation - 0.55) * 0.045, 0.0, 0.35)
	_profile["herb_density"] = clampf(float(_profile.get("herb_density", 0.0)) + maxf(0.0, moisture - 0.50) * 0.022, 0.0, 0.18)
	if center_biome == "foothill" or center_biome == "rocky":
		_profile["slope_threshold"] = maxf(0.010, float(_profile.get("slope_threshold", 0.016)) - 0.003)
		_profile["ledge_block_chance"] = clampf(float(_profile.get("ledge_block_chance", 0.04)) + 0.035, 0.0, 0.24)
	if center_biome == "coast" or coast_influence >= 0.20:
		_profile["mud_moisture_threshold"] = minf(float(_profile.get("mud_moisture_threshold", 0.56)), 0.52)
	if center_biome == "forest":
		_profile["woodland_mass_threshold"] = minf(float(_profile.get("woodland_mass_threshold", 0.55)), 0.48)


func _failed_blueprint() -> RefCounted:
	var blueprint: RefCounted = WildTerrainBlueprintScript.new()
	blueprint.width = _width
	blueprint.height = _height
	blueprint.seed = _seed
	blueprint.terrain_profile_id = _profile_id
	blueprint.profile = _profile.duplicate(true)
	blueprint.generation_metadata = {
		"generator": "wild_terrain",
		"algorithm": "failed_before_layer_generation",
		"region_patch_applied": not _region_patch.is_empty(),
		"region_patch": _region_patch.duplicate(true),
		"generation_errors": _errors.duplicate(),
	}
	blueprint.debug_summary = {
		"seed": _seed,
		"profile": _profile_id,
		"size": { "width": _width, "height": _height },
		"region_patch_applied": not _region_patch.is_empty(),
		"region_patch": _region_patch.duplicate(true),
		"generation_errors": _errors.duplicate(),
	}
	return blueprint


func _generate_natural_layers() -> void:
	for y in range(_height):
		for x in range(_width):
			var cell := Vector2i(x, y)
			var height_value := _layer_value(
				cell,
				11,
				float(_profile.get("base_height", 0.5)),
				float(_profile.get("height_amplitude", 0.35)),
				float(_profile.get("height_scale", 18.0))
			)
			height_value += (_fbm_unit(cell, 29, float(_profile.get("height_scale", 18.0)) * 2.5, 2) - 0.5) * 0.10
			var roughness_value := _layer_value(
				cell,
				47,
				float(_profile.get("roughness_bias", 0.4)),
				float(_profile.get("roughness_amplitude", 0.35)),
				float(_profile.get("roughness_scale", 10.0))
			)
			var moisture_value := _layer_value(
				cell,
				83,
				float(_profile.get("moisture_bias", 0.5)),
				float(_profile.get("moisture_amplitude", 0.35)),
				float(_profile.get("moisture_scale", 14.0))
			)
			var vegetation_value := _layer_value(
				cell,
				131,
				float(_profile.get("vegetation_bias", 0.5)),
				float(_profile.get("vegetation_amplitude", 0.40)),
				float(_profile.get("vegetation_scale", 12.0))
			)
			var rock_value := _layer_value(
				cell,
				191,
				float(_profile.get("rock_bias", 0.2)),
				float(_profile.get("rock_amplitude", 0.35)),
				float(_profile.get("rock_scale", 10.0))
			)

			var water_value := _water_value(cell, height_value)
			moisture_value = clampf(moisture_value + water_value * 0.30 - maxf(0.0, height_value - 0.62) * 0.12, 0.0, 1.0)
			vegetation_value = clampf(vegetation_value + moisture_value * 0.18 - roughness_value * 0.12 - rock_value * 0.10, 0.0, 1.0)
			rock_value = clampf(rock_value + roughness_value * 0.22 + maxf(0.0, height_value - 0.60) * 0.20, 0.0, 1.0)

			_set_grid_value(_height_map, cell, _round3(clampf(height_value, 0.0, 1.0)))
			_set_grid_value(_moisture_map, cell, _round3(moisture_value))
			_set_grid_value(_roughness_map, cell, _round3(clampf(roughness_value, 0.0, 1.0)))
			_set_grid_value(_vegetation_map, cell, _round3(vegetation_value))
			_set_grid_value(_rock_map, cell, _round3(rock_value))
			_set_grid_value(_water_map, cell, _round3(clampf(water_value, 0.0, 1.0)))


func _derive_elevation_semantics() -> void:
	var lowland_threshold := float(_profile.get("lowland_height_threshold", 0.45))
	var highland_threshold := float(_profile.get("highland_height_threshold", 0.62))
	var ridge_threshold := float(_profile.get("ridge_height_threshold", 0.70))
	var slope_threshold := float(_profile.get("slope_threshold", 0.08))
	var ridge_prominence_threshold := float(_profile.get("ridge_prominence_threshold", 0.03))

	for y in range(_height):
		for x in range(_width):
			var cell := Vector2i(x, y)
			var height_value := _value(_height_map, cell)
			var stats := _height_neighbor_stats(cell)
			var slope_value: float = stats.get("max_delta", 0.0)
			var average_delta: float = height_value - float(stats.get("average", height_value))
			var ridge_value := clampf((average_delta - ridge_prominence_threshold) / maxf(0.01, ridge_prominence_threshold * 3.0), 0.0, 1.0)
			var elevation_id := "midland"

			if height_value <= lowland_threshold:
				elevation_id = "lowland"
			elif height_value >= ridge_threshold and (ridge_value >= 0.02 or slope_value >= slope_threshold * 1.1):
				elevation_id = "ridge"
			elif slope_value >= slope_threshold:
				elevation_id = "slope"
			elif height_value >= highland_threshold:
				elevation_id = "highland"

			_set_grid_value(_elevation_map, cell, elevation_id)
			_set_grid_value(_slope_map, cell, _round3(clampf(slope_value, 0.0, 1.0)))
			_set_grid_value(_ridge_map, cell, _round3(ridge_value))


func _derive_landform_semantics() -> void:
	var shallow_water_threshold := float(_profile.get("shallow_water_threshold", 0.34))
	var marsh_water_threshold := float(_profile.get("marsh_water_threshold", 0.52))
	var wet_meadow_water_threshold := float(_profile.get("wet_meadow_water_threshold", 0.34))
	var woodland_threshold := float(_profile.get("woodland_mass_threshold", 0.58))
	var open_threshold := float(_profile.get("open_ground_threshold", 0.34))
	var max_dimension := float(maxi(_width, _height))

	for y in range(_height):
		for x in range(_width):
			var cell := Vector2i(x, y)
			var elevation_id := _elevation_at(cell)
			var height_value := _value(_height_map, cell)
			var moisture_value := _value(_moisture_map, cell)
			var vegetation_value := _value(_vegetation_map, cell)
			var roughness_value := _value(_roughness_map, cell)
			var rock_value := _value(_rock_map, cell)
			var water_value := _value(_water_map, cell)
			var near_water_strength := _nearby_water_strength(cell, 4)
			var woodland_mass := _fbm_unit(cell, 347, maxf(22.0, max_dimension * 0.62), 3)
			var open_mass := _fbm_unit(cell, 359, maxf(20.0, max_dimension * 0.55), 3)
			var landform_id := "meadow"

			if water_value >= shallow_water_threshold:
				landform_id = "water"
			elif near_water_strength >= marsh_water_threshold or (near_water_strength >= wet_meadow_water_threshold and moisture_value >= 0.54):
				landform_id = "wetland"
			elif elevation_id == "lowland" or (height_value <= float(_profile.get("lowland_height_threshold", 0.46)) + 0.03 and moisture_value >= 0.52):
				landform_id = "lowland"
			elif elevation_id == "ridge":
				landform_id = "rocky_ridge" if rock_value >= 0.42 or roughness_value >= 0.45 else "upland_ridge"
			elif elevation_id == "slope":
				landform_id = "rocky_slope" if rock_value >= 0.50 or roughness_value >= 0.55 else "hillside"
			elif elevation_id == "highland":
				landform_id = "rocky_upland" if rock_value >= 0.54 and roughness_value >= 0.46 else "upland"
			elif woodland_mass >= woodland_threshold and vegetation_value >= 0.46 and moisture_value >= 0.36:
				landform_id = "woodland"
			elif open_mass <= open_threshold or vegetation_value <= 0.34:
				landform_id = "open_meadow"

			_set_grid_value(_landform_map, cell, landform_id)


func _derive_tiles() -> void:
	for y in range(_height):
		for x in range(_width):
			var cell := Vector2i(x, y)
			var height_value := _value(_height_map, cell)
			var moisture_value := _value(_moisture_map, cell)
			var roughness_value := _value(_roughness_map, cell)
			var vegetation_value := _value(_vegetation_map, cell)
			var rock_value := _value(_rock_map, cell)
			var water_value := _value(_water_map, cell)
			var near_water_strength := _nearby_water_strength(cell, 3)
			var tile_id := "grass"
			var biome_id := "meadow"
			var blocks := false
			var walk_cost := 1.0
			var deep_water_threshold := float(_profile.get("deep_water_threshold", 0.70))
			var shallow_water_threshold := float(_profile.get("shallow_water_threshold", 0.34))
			var marsh_water_threshold := float(_profile.get("marsh_water_threshold", 0.52))
			var wet_meadow_water_threshold := float(_profile.get("wet_meadow_water_threshold", 0.34))
			var mud_moisture_threshold := float(_profile.get("mud_moisture_threshold", 0.56))
			var forest_threshold := float(_profile.get("forest_threshold", 0.68))
			var rocky_threshold := float(_profile.get("rocky_threshold", 0.66))
			var stone_threshold := float(_profile.get("stone_threshold", 0.55))

			if water_value >= deep_water_threshold:
				tile_id = "deep_water"
				biome_id = "deep_water"
				blocks = true
				walk_cost = 999.0
			elif water_value >= shallow_water_threshold:
				tile_id = "shallow_water"
				biome_id = "shallow_water"
				walk_cost = 4.0
			elif near_water_strength >= marsh_water_threshold and moisture_value >= mud_moisture_threshold:
				tile_id = "mud"
				biome_id = "marsh"
				walk_cost = 3.0
			elif near_water_strength >= wet_meadow_water_threshold or (moisture_value >= 0.70 and height_value <= 0.52):
				tile_id = "wet_grass"
				biome_id = "wet_meadow"
				walk_cost = 1.6
			elif rock_value >= rocky_threshold and (height_value >= 0.52 or roughness_value >= 0.55):
				tile_id = "rocky_ground"
				biome_id = "rocky_slope" if height_value >= 0.58 else "rocky_scrub"
				walk_cost = 2.3
			elif rock_value >= stone_threshold and roughness_value >= 0.50:
				tile_id = "stone"
				biome_id = "scrub_rock"
				walk_cost = 1.8
			elif vegetation_value >= forest_threshold and moisture_value >= 0.42:
				tile_id = "forest_floor"
				biome_id = "dense_woods" if vegetation_value >= forest_threshold + 0.10 else "forest_edge"
				walk_cost = 2.0
			elif moisture_value <= 0.32 or roughness_value >= 0.62:
				tile_id = "dirt"
				biome_id = "dry_grass"
				walk_cost = 1.3

			var landform_adjustment := _apply_landform_semantics_to_tile(cell, tile_id, biome_id, blocks, walk_cost)
			tile_id = str(landform_adjustment.get("tile_id", tile_id))
			biome_id = str(landform_adjustment.get("biome_id", biome_id))
			blocks = bool(landform_adjustment.get("blocks", blocks))
			walk_cost = float(landform_adjustment.get("walk_cost", walk_cost))

			var elevation_adjustment := _apply_elevation_semantics_to_tile(cell, tile_id, biome_id, blocks, walk_cost)
			tile_id = str(elevation_adjustment.get("tile_id", tile_id))
			biome_id = str(elevation_adjustment.get("biome_id", biome_id))
			blocks = bool(elevation_adjustment.get("blocks", blocks))
			walk_cost = float(elevation_adjustment.get("walk_cost", walk_cost))

			_set_grid_value(_tile_map, cell, tile_id)
			_set_grid_value(_biome_map, cell, biome_id)
			_set_grid_value(_blocker_map, cell, blocks)
			_set_grid_value(_walk_cost_map, cell, walk_cost)


func _apply_landform_semantics_to_tile(
	cell: Vector2i,
	tile_id: String,
	biome_id: String,
	blocks: bool,
	walk_cost: float
) -> Dictionary:
	var landform_id := _landform_at(cell)
	var rock_value := _value(_rock_map, cell)
	var roughness_value := _value(_roughness_map, cell)
	var moisture_value := _value(_moisture_map, cell)
	var water_value := _value(_water_map, cell)
	var is_water := tile_id == "deep_water" or tile_id == "shallow_water"

	if blocks or is_water:
		return {
			"tile_id": tile_id,
			"biome_id": biome_id,
			"blocks": blocks,
			"walk_cost": walk_cost,
		}

	match landform_id:
		"wetland":
			if ["grass", "lowland_grass"].has(tile_id):
				tile_id = "wet_grass"
			if tile_id != "mud":
				biome_id = "wetland_transition"
				walk_cost = maxf(walk_cost, 1.65)
		"lowland":
			if tile_id == "grass":
				tile_id = "lowland_grass"
			if ["grass", "lowland_grass", "wet_grass"].has(tile_id):
				biome_id = "lowland_meadow"
				walk_cost = maxf(walk_cost, 1.20)
		"woodland":
			if ["grass", "lowland_grass", "highland_grass", "slope_grass"].has(tile_id):
				tile_id = "forest_floor"
				biome_id = "woodland_core"
				walk_cost = maxf(walk_cost, 2.0)
			elif tile_id == "wet_grass" and water_value < 0.18:
				tile_id = "forest_floor"
				biome_id = "damp_woodland"
				walk_cost = maxf(walk_cost, 2.05)
		"open_meadow":
			if tile_id == "forest_floor" and moisture_value < 0.68:
				tile_id = "grass"
			if ["grass", "lowland_grass"].has(tile_id):
				biome_id = "open_meadow"
				walk_cost = minf(walk_cost, 1.15)
		"upland":
			if tile_id == "grass":
				tile_id = "highland_grass"
			if ["grass", "highland_grass"].has(tile_id):
				biome_id = "upland_meadow"
				walk_cost = maxf(walk_cost, 1.25)
		"hillside":
			if ["grass", "highland_grass"].has(tile_id):
				tile_id = "slope_grass"
			if ["grass", "highland_grass", "slope_grass"].has(tile_id):
				biome_id = "hillside"
				walk_cost = maxf(walk_cost, 1.45)
		"rocky_upland":
			if rock_value >= 0.66 or roughness_value >= 0.62:
				tile_id = "rocky_ground"
				biome_id = "rocky_upland"
				walk_cost = maxf(walk_cost, 2.25)
			elif tile_id == "grass":
				tile_id = "highland_grass"
				biome_id = "stony_upland"
				walk_cost = maxf(walk_cost, 1.45)
		"rocky_slope":
			if rock_value >= 0.62 or roughness_value >= 0.60:
				tile_id = "rocky_ground"
				biome_id = "rocky_slope"
				walk_cost = maxf(walk_cost, 2.35)
			elif ["grass", "highland_grass"].has(tile_id):
				tile_id = "slope_grass"
				biome_id = "stony_hillside"
				walk_cost = maxf(walk_cost, 1.65)
		"upland_ridge", "rocky_ridge":
			if rock_value >= 0.48 or roughness_value >= 0.46:
				tile_id = "stone" if rock_value < 0.62 else "rocky_ground"
				biome_id = "stony_ridge"
				walk_cost = maxf(walk_cost, 2.10)
			elif ["grass", "highland_grass"].has(tile_id):
				tile_id = "highland_grass"
				biome_id = "ridge_meadow"
				walk_cost = maxf(walk_cost, 1.60)

	return {
		"tile_id": tile_id,
		"biome_id": biome_id,
		"blocks": blocks,
		"walk_cost": _round3(walk_cost),
	}


func _apply_elevation_semantics_to_tile(
	cell: Vector2i,
	tile_id: String,
	biome_id: String,
	blocks: bool,
	walk_cost: float
) -> Dictionary:
	var elevation_id := _elevation_at(cell)
	var slope_value := _value(_slope_map, cell)
	var ridge_value := _value(_ridge_map, cell)
	var rock_value := _value(_rock_map, cell)
	var roughness_value := _value(_roughness_map, cell)
	var moisture_value := _value(_moisture_map, cell)
	var steep_slope_threshold := float(_profile.get("steep_slope_threshold", 0.13))
	var ledge_block_chance := float(_profile.get("ledge_block_chance", 0.04))
	var is_water := tile_id == "deep_water" or tile_id == "shallow_water"

	if blocks or is_water:
		return {
			"tile_id": tile_id,
			"biome_id": biome_id,
			"blocks": blocks,
			"walk_cost": walk_cost,
		}

	match elevation_id:
		"lowland":
			if ["grass", "lowland_grass"].has(tile_id) and moisture_value >= 0.58:
				tile_id = "wet_grass"
				biome_id = "lowland_meadow"
				walk_cost = maxf(walk_cost, 1.5)
			elif tile_id == "grass":
				tile_id = "lowland_grass"
				biome_id = "lowland_meadow"
				walk_cost = maxf(walk_cost, 1.2)
		"highland":
			if tile_id == "grass":
				tile_id = "highland_grass"
			if tile_id == "highland_grass" and moisture_value <= 0.48:
				biome_id = "dry_highland"
				walk_cost = maxf(walk_cost, 1.35)
			elif tile_id == "highland_grass":
				biome_id = "highland_meadow"
				walk_cost = maxf(walk_cost, 1.2)
		"slope":
			if ["grass", "highland_grass"].has(tile_id):
				tile_id = "slope_grass"
			if not ["rocky_slope", "rocky_ground", "stone", "scrub_rock"].has(biome_id):
				biome_id = "hillside"
			walk_cost = maxf(walk_cost, 1.35 + slope_value * 4.0)
		"ridge":
			if rock_value >= 0.46 or roughness_value >= 0.48:
				tile_id = "rocky_ground" if rock_value >= 0.62 else "stone"
				biome_id = "stony_ridge"
				walk_cost = maxf(walk_cost, 2.15 + ridge_value * 0.65)
			else:
				if tile_id == "grass":
					tile_id = "highland_grass"
				biome_id = "ridge_meadow"
				walk_cost = maxf(walk_cost, 1.55 + ridge_value * 0.35)

	if slope_value >= steep_slope_threshold and (ridge_value >= 0.30 or rock_value >= 0.58):
		var ledge_roll := _unit_hash_cell(cell, 947)
		if ledge_roll < ledge_block_chance:
			tile_id = "rocky_ground"
			biome_id = "rock_ledge"
			blocks = true
			walk_cost = 999.0

	return {
		"tile_id": tile_id,
		"biome_id": biome_id,
		"blocks": blocks,
		"walk_cost": _round3(walk_cost),
	}


func _sample_natural_objects() -> Array[Dictionary]:
	var objects: Array[Dictionary] = []
	var occupied: Dictionary = {}
	for kind in ["tree", "large_rock", "ore_vein", "herb_patch", "berry_bush", "fallen_branch"]:
		objects.append_array(_sample_natural_object_kind(kind, occupied))
	return objects


func _sample_natural_object_kind(kind: String, occupied: Dictionary) -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	var area := _width * _height
	var max_count := int(floor(float(area) * _density_for_kind(kind)))
	if max_count <= 0:
		return results
	var min_distance := _min_distance_for_kind(kind)
	var attempts: int = maxi(area * 3, max_count * 32)
	var salt := _salt_for_kind(kind)
	for attempt in range(attempts):
		if results.size() >= max_count:
			break
		var cell := Vector2i(
			clampi(int(floor(_unit_hash_xy(attempt, 0, salt) * float(_width))), 0, _width - 1),
			clampi(int(floor(_unit_hash_xy(0, attempt, salt + 17) * float(_height))), 0, _height - 1)
		)
		var key := _cell_key(cell)
		if occupied.has(key):
			continue
		if not _natural_object_cell_allowed(kind, cell):
			continue
		if _too_close_to_existing(cell, occupied, min_distance):
			continue
		var score := _natural_object_score(kind, cell)
		if _unit_hash_cell(cell, salt + attempt) > score:
			continue
		occupied[key] = true
		results.append({
			"id": "%s_%03d" % [kind, results.size() + 1],
			"kind": kind,
			"grid_position": _dict_cell(cell),
			"blocks_movement": _object_blocks_movement(kind),
			"blocks_sight": kind == "tree",
			"sample_score": _round3(score),
			"source_layers": {
				"height": _value(_height_map, cell),
				"moisture": _value(_moisture_map, cell),
				"roughness": _value(_roughness_map, cell),
				"vegetation": _value(_vegetation_map, cell),
				"rock": _value(_rock_map, cell),
				"water": _value(_water_map, cell),
				"elevation": _elevation_at(cell),
				"landform": _landform_at(cell),
				"slope": _value(_slope_map, cell),
				"ridge": _value(_ridge_map, cell),
				"biome": str(((_biome_map[cell.y] as Array)[cell.x])),
			},
		})
	return results


func _apply_natural_object_blockers(objects: Array[Dictionary]) -> void:
	for object_value in objects:
		var object_data: Dictionary = object_value as Dictionary
		if not bool(object_data.get("blocks_movement", false)):
			continue
		var cell := _cell_from_dict(object_data.get("grid_position", {}) as Dictionary)
		if _in_bounds(cell):
			_set_grid_value(_blocker_map, cell, true)
			_set_grid_value(_walk_cost_map, cell, 999.0)


func _select_spawn_candidates() -> Array[Dictionary]:
	var scored: Array[Dictionary] = []
	var target := _hint_target_cell(_spawn_hint, Vector2i(int(_width / 2), int(_height / 2)))
	for y in range(_height):
		for x in range(_width):
			var cell := Vector2i(x, y)
			if _blocks(cell):
				continue
			var edge_distance: int = mini(mini(x, _width - 1 - x), mini(y, _height - 1 - y))
			var score := 100.0
			score -= float(cell.distance_squared_to(target)) * 0.05
			score += minf(12.0, float(edge_distance))
			score -= _value(_walk_cost_map, cell) * 6.0
			score -= _value(_roughness_map, cell) * 4.0
			score -= _value(_slope_map, cell) * 18.0
			score -= _value(_ridge_map, cell) * 6.0
			score += _unit_hash_cell(cell, 373) * 0.1
			scored.append({ "cell": cell, "score": score })
	var candidates := _take_top_scored_cells(scored, MAX_SPAWN_CANDIDATES)
	if candidates.is_empty():
		_warnings.append("No passable spawn candidate was found.")
	return candidates


func _select_exit_candidates(spawn_candidates: Array[Dictionary]) -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	var reachable_cells := _reachable_cells_for_exit_selection(spawn_candidates)
	for hint_value in _exit_hints:
		var hint: Dictionary = hint_value as Dictionary
		var scored: Array[Dictionary] = []
		var target := _hint_target_cell(hint, _default_edge_target(str(hint.get("side", ""))))
		for y in range(_height):
			for x in range(_width):
				var cell := Vector2i(x, y)
				if _blocks(cell):
					continue
				if not reachable_cells.is_empty() and not reachable_cells.has(_cell_key(cell)):
					continue
				var score := 100.0
				score -= float(cell.distance_squared_to(target)) * 0.06
				score -= _edge_distance_for_side(cell, str(hint.get("side", ""))) * 1.8
				score -= _value(_walk_cost_map, cell) * 5.0
				score -= _value(_slope_map, cell) * 16.0
				score -= _value(_ridge_map, cell) * 5.0
				score += _unit_hash_cell(cell, 421) * 0.1
				scored.append({ "cell": cell, "score": score })
		var candidates := _take_top_scored_cells(scored, MAX_EXIT_CANDIDATES_PER_HINT)
		if candidates.is_empty():
			_errors.append("No reachable passable exit candidate for hint: %s" % str(hint))
			continue
		for candidate_value in candidates:
			var candidate: Dictionary = candidate_value as Dictionary
			var cell := _cell_from_dict(candidate.get("grid_position", {}) as Dictionary)
			results.append({
				"id": str(hint.get("id", "exit_%02d" % (results.size() + 1))),
				"grid_position": _dict_cell(cell),
				"facing": str(hint.get("facing", _facing_for_side(str(hint.get("side", ""))))),
				"side": str(hint.get("side", "")),
				"world_exit_id": str(hint.get("world_exit_id", "")),
				"entry_entrance_id": str(hint.get("entry_entrance_id", "")),
				"target_scene_path": str(hint.get("target_scene_path", "")),
				"target_entrance_id": str(hint.get("target_entrance_id", "")),
				"selection_score": float(candidate.get("score", 0.0)),
				"hint": hint.duplicate(true),
			})
	return results


func _reachable_cells_for_exit_selection(spawn_candidates: Array[Dictionary]) -> Dictionary:
	if spawn_candidates.is_empty():
		return {}
	var first_spawn: Dictionary = spawn_candidates[0] as Dictionary
	var start_cell := _cell_from_dict(first_spawn.get("grid_position", {}) as Dictionary)
	if _blocks(start_cell):
		return {}
	return _flood_passable_cells(start_cell)


func _flood_passable_cells(start_cell: Vector2i) -> Dictionary:
	var visited := {}
	var queue: Array[Vector2i] = [start_cell]
	visited[_cell_key(start_cell)] = true
	var read_index := 0
	while read_index < queue.size():
		var cell := queue[read_index]
		read_index += 1
		for offset_value in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var offset: Vector2i = offset_value as Vector2i
			var next_cell: Vector2i = cell + offset
			var key := _cell_key(next_cell)
			if visited.has(key) or _blocks(next_cell):
				continue
			visited[key] = true
			queue.append(next_cell)
	return visited


func _take_top_scored_cells(scored: Array[Dictionary], limit: int) -> Array[Dictionary]:
	var remaining := scored.duplicate(true)
	var result: Array[Dictionary] = []
	while result.size() < limit and not remaining.is_empty():
		var best_index := 0
		var best_score := -INF
		for index in range(remaining.size()):
			var row: Dictionary = remaining[index] as Dictionary
			var score := float(row.get("score", 0.0))
			if score > best_score:
				best_score = score
				best_index = index
		var best: Dictionary = remaining[best_index] as Dictionary
		var cell: Vector2i = best.get("cell", Vector2i.ZERO) as Vector2i
		result.append({
			"grid_position": _dict_cell(cell),
			"score": _round3(float(best.get("score", 0.0))),
			"tile": str((_tile_map[cell.y] as Array)[cell.x]),
			"walk_cost": _value(_walk_cost_map, cell),
		})
		remaining.remove_at(best_index)
	return result


func _build_debug_summary(
	natural_objects: Array[Dictionary],
	spawn_candidates: Array[Dictionary],
	exit_candidates: Array[Dictionary]
) -> Dictionary:
	var total := _width * _height
	var passable := 0
	var water := 0
	var wetland := 0
	var forest := 0
	var rock := 0
	var lowland := 0
	var highland := 0
	var slope := 0
	var ridge := 0
	var landform_lowland := 0
	var landform_wetland := 0
	var landform_woodland := 0
	var landform_open := 0
	var landform_upland := 0
	var ledge_blockers := 0
	var slope_walk_total := 0.0
	var slope_walk_count := 0
	var flat_walk_total := 0.0
	var flat_walk_count := 0
	var tile_counts: Dictionary = {}
	var biome_counts: Dictionary = {}
	var elevation_counts: Dictionary = {}
	var landform_counts: Dictionary = {}
	var slope_threshold := float(_profile.get("slope_threshold", 0.08))
	for y in range(_height):
		for x in range(_width):
			var cell := Vector2i(x, y)
			if not _blocks(cell):
				passable += 1
			var tile_id := str((_tile_map[y] as Array)[x])
			var biome_id := str((_biome_map[y] as Array)[x])
			var elevation_id := _elevation_at(cell)
			var landform_id := _landform_at(cell)
			var slope_value := _value(_slope_map, cell)
			var is_water := tile_id == "deep_water" or tile_id == "shallow_water"
			tile_counts[tile_id] = int(tile_counts.get(tile_id, 0)) + 1
			biome_counts[biome_id] = int(biome_counts.get(biome_id, 0)) + 1
			elevation_counts[elevation_id] = int(elevation_counts.get(elevation_id, 0)) + 1
			landform_counts[landform_id] = int(landform_counts.get(landform_id, 0)) + 1
			if tile_id == "deep_water" or tile_id == "shallow_water":
				water += 1
			if tile_id == "wet_grass" or tile_id == "mud":
				wetland += 1
			if tile_id == "forest_floor":
				forest += 1
			if tile_id == "stone" or tile_id == "rocky_ground":
				rock += 1
			if elevation_id == "lowland":
				lowland += 1
			if elevation_id == "highland":
				highland += 1
			if elevation_id == "slope":
				slope += 1
			if elevation_id == "ridge":
				ridge += 1
			if landform_id == "lowland":
				landform_lowland += 1
			if landform_id == "wetland":
				landform_wetland += 1
			if landform_id == "woodland":
				landform_woodland += 1
			if landform_id == "open_meadow":
				landform_open += 1
			if ["upland", "hillside", "rocky_upland", "rocky_slope", "upland_ridge", "rocky_ridge"].has(landform_id):
				landform_upland += 1
			if biome_id == "rock_ledge":
				ledge_blockers += 1
			if not _blocks(cell) and not is_water:
				if slope_value >= slope_threshold:
					slope_walk_total += _value(_walk_cost_map, cell)
					slope_walk_count += 1
				elif elevation_id == "midland":
					flat_walk_total += _value(_walk_cost_map, cell)
					flat_walk_count += 1

	var object_counts: Dictionary = {}
	for object_value in natural_objects:
		var object_data: Dictionary = object_value as Dictionary
		var kind := str(object_data.get("kind", ""))
		object_counts[kind] = int(object_counts.get(kind, 0)) + 1

	return {
		"seed": _seed,
		"profile": _profile_id,
		"size": { "width": _width, "height": _height },
		"passable_ratio": _round3(float(passable) / maxf(1.0, float(total))),
		"water_ratio": _round3(float(water) / maxf(1.0, float(total))),
		"wetland_ratio": _round3(float(wetland) / maxf(1.0, float(total))),
		"forest_ratio": _round3(float(forest) / maxf(1.0, float(total))),
		"rock_ratio": _round3(float(rock) / maxf(1.0, float(total))),
		"lowland_ratio": _round3(float(lowland) / maxf(1.0, float(total))),
		"highland_ratio": _round3(float(highland) / maxf(1.0, float(total))),
		"slope_ratio": _round3(float(slope) / maxf(1.0, float(total))),
		"ridge_ratio": _round3(float(ridge) / maxf(1.0, float(total))),
		"landform_lowland_ratio": _round3(float(landform_lowland) / maxf(1.0, float(total))),
		"landform_wetland_ratio": _round3(float(landform_wetland) / maxf(1.0, float(total))),
		"woodland_ratio": _round3(float(landform_woodland) / maxf(1.0, float(total))),
		"open_ground_ratio": _round3(float(landform_open) / maxf(1.0, float(total))),
		"upland_landform_ratio": _round3(float(landform_upland) / maxf(1.0, float(total))),
		"ledge_blocker_ratio": _round3(float(ledge_blockers) / maxf(1.0, float(total))),
		"slope_walk_cost_avg": _round3(slope_walk_total / maxf(1.0, float(slope_walk_count))),
		"flat_walk_cost_avg": _round3(flat_walk_total / maxf(1.0, float(flat_walk_count))),
		"tile_counts": tile_counts,
		"biome_counts": biome_counts,
		"elevation_counts": elevation_counts,
		"landform_counts": landform_counts,
		"object_counts": object_counts,
		"spawn_candidate_count": spawn_candidates.size(),
		"exit_candidate_count": exit_candidates.size(),
		"region_patch_applied": not _region_patch.is_empty(),
		"region_patch": _region_patch.duplicate(true),
		"generation_warnings": _warnings.duplicate(),
		"generation_errors": _errors.duplicate(),
	}


func _layer_value(cell: Vector2i, salt: int, bias: float, amplitude: float, scale: float) -> float:
	return clampf(bias + (_fbm_unit(cell, salt, scale, 4) - 0.5) * amplitude, 0.0, 1.0)


func _height_neighbor_stats(cell: Vector2i) -> Dictionary:
	var center := _value(_height_map, cell)
	var max_delta := 0.0
	var total := 0.0
	var count := 0
	var offsets: Array[Vector2i] = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
	for offset in offsets:
		var other: Vector2i = cell + offset
		if not _in_bounds(other):
			continue
		var neighbor_height := _value(_height_map, other)
		max_delta = maxf(max_delta, absf(center - neighbor_height))
		total += neighbor_height
		count += 1
	return {
		"max_delta": max_delta,
		"average": total / maxf(1.0, float(count)),
	}


func _water_value(cell: Vector2i, height_value: float) -> float:
	var water_level := float(_profile.get("water_level", 0.38))
	var softness := maxf(0.01, float(_profile.get("water_softness", 0.18)))
	var lowland_water := clampf((water_level - height_value) / softness, 0.0, 1.0)
	var pond_water := _pond_value(cell) * (1.0 - clampf((height_value - water_level) * 1.6, 0.0, 0.7))
	var drainage_water := _drainage_value(cell, height_value)
	var river_influence := float(_profile.get("river_influence", 0.0))
	var river := _river_band_value(cell) * river_influence if river_influence > 0.0 else 0.0
	return clampf(maxf(maxf(lowland_water, river), maxf(pond_water, drainage_water)), 0.0, 1.0)


func _pond_value(cell: Vector2i) -> float:
	var pond_influence := float(_profile.get("pond_influence", 0.0))
	if pond_influence <= 0.0:
		return 0.0
	var pond_scale := float(_profile.get("pond_scale", 18.0))
	var pond_threshold := float(_profile.get("pond_threshold", 0.66))
	var basin := _fbm_unit(cell, 239, pond_scale, 3)
	var basin_shape := _fbm_unit(cell, 251, pond_scale * 1.7, 2)
	return smoothstep(pond_threshold, 1.0, basin) * lerpf(0.65, 1.0, basin_shape) * pond_influence


func _drainage_value(cell: Vector2i, height_value: float) -> float:
	var drainage_influence := float(_profile.get("drainage_influence", 0.0))
	if drainage_influence <= 0.0:
		return 0.0
	var water_level := float(_profile.get("water_level", 0.38))
	var lowland_factor := clampf((water_level + 0.18 - height_value) / 0.34, 0.0, 1.0)
	var x_ridge := 1.0 - absf(_value_noise(Vector2(float(cell.x) / 9.0, float(cell.y) / 23.0), 263) * 2.0 - 1.0)
	var y_ridge := 1.0 - absf(_value_noise(Vector2(float(cell.x) / 21.0, float(cell.y) / 10.0), 277) * 2.0 - 1.0)
	var drainage_line := maxf(x_ridge, y_ridge)
	return smoothstep(0.72, 0.96, drainage_line) * lowland_factor * drainage_influence


func _river_band_value(cell: Vector2i) -> float:
	var vertical := _unit_hash_xy(_seed, 17, 571) >= 0.5
	var length_axis := float(cell.y if vertical else cell.x)
	var cross_axis := float(cell.x if vertical else cell.y)
	var max_cross := float(_width if vertical else _height)
	var base := max_cross * lerpf(0.32, 0.68, _unit_hash_xy(_seed, 23, 593))
	var curve := (_value_noise(Vector2(length_axis / 8.0, 0.0), 601) - 0.5) * max_cross * 0.22
	var river_width := maxf(2.5, max_cross * lerpf(0.045, 0.085, _unit_hash_xy(_seed, 31, 607)))
	var distance := absf(cross_axis - (base + curve))
	if distance >= river_width:
		return 0.0
	return 1.0 - smoothstep(river_width * 0.35, river_width, distance)


func _fbm_unit(cell: Vector2i, salt: int, scale: float, octaves: int) -> float:
	var total := 0.0
	var amplitude := 1.0
	var frequency := 1.0
	var amplitude_sum := 0.0
	for octave in range(octaves):
		var pos := Vector2(float(cell.x) / maxf(1.0, scale) * frequency, float(cell.y) / maxf(1.0, scale) * frequency)
		total += _value_noise(pos, salt + octave * 101) * amplitude
		amplitude_sum += amplitude
		amplitude *= 0.52
		frequency *= 2.0
	return total / maxf(0.0001, amplitude_sum)


func _value_noise(pos: Vector2, salt: int) -> float:
	var x0 := floori(pos.x)
	var y0 := floori(pos.y)
	var x1 := x0 + 1
	var y1 := y0 + 1
	var sx := smoothstep(0.0, 1.0, pos.x - float(x0))
	var sy := smoothstep(0.0, 1.0, pos.y - float(y0))
	var n00 := _unit_hash_xy(x0, y0, salt)
	var n10 := _unit_hash_xy(x1, y0, salt)
	var n01 := _unit_hash_xy(x0, y1, salt)
	var n11 := _unit_hash_xy(x1, y1, salt)
	return lerpf(lerpf(n00, n10, sx), lerpf(n01, n11, sx), sy)


func _unit_hash_cell(cell: Vector2i, salt: int) -> float:
	return _unit_hash_xy(cell.x, cell.y, salt)


func _unit_hash_xy(x: int, y: int, salt: int) -> float:
	var value := sin(float(x) * 12.9898 + float(y) * 78.233 + float(_seed + salt) * 37.719) * 43758.5453123
	return value - floor(value)


func _natural_object_cell_allowed(kind: String, cell: Vector2i) -> bool:
	if not _in_bounds(cell):
		return false
	if _blocks(cell):
		return false
	var tile_id := str((_tile_map[cell.y] as Array)[cell.x])
	var elevation_id := _elevation_at(cell)
	var landform_id := _landform_at(cell)
	var slope_value := _value(_slope_map, cell)
	if tile_id == "deep_water" or tile_id == "shallow_water":
		return false
	match kind:
		"tree":
			return ["forest_floor", "wet_grass", "grass", "lowland_grass", "highland_grass"].has(tile_id) and not (slope_value >= 0.16 or elevation_id == "ridge" or landform_id == "open_meadow")
		"large_rock", "ore_vein":
			return ["stone", "rocky_ground", "dirt", "grass", "highland_grass", "slope_grass"].has(tile_id)
		"herb_patch":
			return not ["rocky_ground", "stone"].has(tile_id) and elevation_id != "ridge"
		"berry_bush", "fallen_branch":
			return ["forest_floor", "wet_grass", "grass", "lowland_grass", "highland_grass", "dirt"].has(tile_id)
		_:
			return true


func _natural_object_score(kind: String, cell: Vector2i) -> float:
	var moisture := _value(_moisture_map, cell)
	var vegetation := _value(_vegetation_map, cell)
	var rock := _value(_rock_map, cell)
	var roughness := _value(_roughness_map, cell)
	var water := _value(_water_map, cell)
	var slope := _value(_slope_map, cell)
	var ridge := _value(_ridge_map, cell)
	var elevation_id := _elevation_at(cell)
	var landform_id := _landform_at(cell)
	var biome_id := str((_biome_map[cell.y] as Array)[cell.x])
	match kind:
		"tree":
			var forest_bonus := 0.16 if ["forest_edge", "dense_woods", "woodland_core", "damp_woodland"].has(biome_id) else 0.0
			forest_bonus += 0.36 if landform_id == "woodland" else 0.0
			forest_bonus += 0.04 if ["lowland", "wetland"].has(landform_id) else 0.0
			forest_bonus -= 0.08 if landform_id == "meadow" else 0.0
			forest_bonus -= 0.28 if ["open_meadow", "upland", "hillside", "rocky_upland", "rocky_slope"].has(landform_id) else 0.0
			var elevation_penalty := slope * 0.70 + (0.16 if elevation_id == "ridge" else 0.0)
			return clampf((vegetation - 0.30) * 1.60 + forest_bonus - elevation_penalty, 0.0, 0.86)
		"large_rock":
			var rocky_landform_bonus := 0.18 if ["rocky_upland", "rocky_slope", "rocky_ridge", "upland_ridge"].has(landform_id) else 0.0
			return clampf((rock - 0.30) * 1.30 + roughness * 0.25 + slope * 0.75 + ridge * 0.18 + rocky_landform_bonus, 0.0, 0.84)
		"ore_vein":
			var height_bonus := 0.08 if ["highland", "slope", "ridge"].has(elevation_id) else -0.04
			height_bonus += 0.08 if ["rocky_upland", "rocky_slope", "rocky_ridge"].has(landform_id) else 0.0
			return clampf((rock - 0.56) * 0.80 + roughness * 0.12 + slope * 0.20 + ridge * 0.12 + height_bonus, 0.0, 0.30)
		"herb_patch":
			var lowland_bonus := 0.08 if elevation_id == "lowland" else 0.0
			lowland_bonus += 0.12 if ["wetland", "lowland"].has(landform_id) else 0.0
			var dry_height_penalty := 0.10 if ["highland", "ridge"].has(elevation_id) else 0.0
			return clampf((moisture - 0.42) * 0.70 + vegetation * 0.22 - water * 0.20 + lowland_bonus - dry_height_penalty, 0.0, 0.42)
		"berry_bush":
			var edge_bonus := 0.12 if ["wet_meadow", "forest_edge", "dense_woods", "woodland_core"].has(biome_id) else 0.0
			edge_bonus += 0.08 if landform_id == "woodland" else 0.0
			return clampf((vegetation - 0.52) * 0.65 + edge_bonus - slope * 0.20, 0.0, 0.34)
		"fallen_branch":
			var branch_bonus := 0.10 if landform_id == "woodland" else 0.0
			return clampf((vegetation - 0.55) * 0.35 + roughness * 0.08 + branch_bonus - ridge * 0.08, 0.0, 0.22)
		_:
			return 0.0


func _density_for_kind(kind: String) -> float:
	match kind:
		"tree":
			return float(_profile.get("tree_density", 0.02))
		"large_rock":
			return float(_profile.get("rock_density", 0.01))
		"ore_vein":
			return float(_profile.get("ore_density", 0.001))
		"herb_patch":
			return float(_profile.get("herb_density", 0.01))
		"berry_bush":
			return float(_profile.get("berry_density", 0.006))
		"fallen_branch":
			return float(_profile.get("fallen_branch_density", 0.006))
		_:
			return 0.0


func _min_distance_for_kind(kind: String) -> int:
	match kind:
		"tree":
			return 2
		"large_rock":
			return 2
		"ore_vein":
			return 5
		"herb_patch":
			return 2
		"berry_bush":
			return 3
		"fallen_branch":
			return 3
		_:
			return 2


func _object_blocks_movement(kind: String) -> bool:
	return ["tree", "large_rock", "ore_vein"].has(kind)


func _too_close_to_existing(cell: Vector2i, occupied: Dictionary, min_distance: int) -> bool:
	if min_distance <= 0:
		return false
	for y in range(cell.y - min_distance, cell.y + min_distance + 1):
		for x in range(cell.x - min_distance, cell.x + min_distance + 1):
			var other := Vector2i(x, y)
			if occupied.has(_cell_key(other)) and cell.distance_squared_to(other) < min_distance * min_distance:
				return true
	return false


func _nearby_water_strength(cell: Vector2i, radius: int) -> float:
	var best := 0.0
	for y in range(cell.y - radius, cell.y + radius + 1):
		for x in range(cell.x - radius, cell.x + radius + 1):
			var other := Vector2i(x, y)
			if not _in_bounds(other):
				continue
			var distance := maxf(1.0, sqrt(float(cell.distance_squared_to(other))))
			best = maxf(best, _value(_water_map, other) / distance)
	return best


func _hint_target_cell(hint: Dictionary, fallback: Vector2i) -> Vector2i:
	if hint.has("grid_position"):
		return _cell_from_dict(hint.get("grid_position", {}) as Dictionary)
	if hint.has("x") or hint.has("y"):
		return Vector2i(int(hint.get("x", fallback.x)), int(hint.get("y", fallback.y)))
	var side := str(hint.get("side", ""))
	if not side.is_empty():
		return _default_edge_target(side)
	return fallback


func _default_edge_target(side: String) -> Vector2i:
	match side:
		"west", "left":
			return Vector2i(1, int(_height / 2))
		"east", "right":
			return Vector2i(_width - 2, int(_height / 2))
		"north", "up":
			return Vector2i(int(_width / 2), 1)
		"south", "down":
			return Vector2i(int(_width / 2), _height - 2)
		_:
			return Vector2i(int(_width / 2), int(_height / 2))


func _edge_distance_for_side(cell: Vector2i, side: String) -> float:
	match side:
		"west", "left":
			return float(cell.x)
		"east", "right":
			return float(_width - 1 - cell.x)
		"north", "up":
			return float(cell.y)
		"south", "down":
			return float(_height - 1 - cell.y)
		_:
			return 0.0


func _facing_for_side(side: String) -> String:
	match side:
		"west", "left":
			return "right"
		"east", "right":
			return "left"
		"north", "up":
			return "down"
		"south", "down":
			return "up"
		_:
			return "down"


func _map_has_size(map_data: Array, width: int, height: int) -> bool:
	if map_data.size() != height:
		return false
	for row_value in map_data:
		var row: Array = row_value as Array
		if row.size() != width:
			return false
	return true


func _empty_grid(default_value: Variant) -> Array:
	var rows: Array = []
	for _y in range(_height):
		var row: Array = []
		for _x in range(_width):
			row.append(default_value)
		rows.append(row)
	return rows


func _set_grid_value(map_data: Array, cell: Vector2i, value: Variant) -> void:
	(map_data[cell.y] as Array)[cell.x] = value


func _value(map_data: Array, cell: Vector2i) -> float:
	if not _in_bounds(cell):
		return 0.0
	return float((map_data[cell.y] as Array)[cell.x])


func _elevation_at(cell: Vector2i) -> String:
	if not _in_bounds(cell):
		return ""
	return str((_elevation_map[cell.y] as Array)[cell.x])


func _landform_at(cell: Vector2i) -> String:
	if not _in_bounds(cell):
		return ""
	return str((_landform_map[cell.y] as Array)[cell.x])


func _blocks(cell: Vector2i) -> bool:
	if not _in_bounds(cell):
		return true
	return bool((_blocker_map[cell.y] as Array)[cell.x])


func _in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < _width and cell.y < _height


func _cell_from_dict(value: Dictionary) -> Vector2i:
	return Vector2i(int(value.get("x", -1)), int(value.get("y", -1)))


func _dict_cell(cell: Vector2i) -> Dictionary:
	return { "x": cell.x, "y": cell.y }


func _cell_key(cell: Vector2i) -> String:
	return "%d,%d" % [cell.x, cell.y]


func _salt_for_kind(kind: String) -> int:
	match kind:
		"tree":
			return 701
		"large_rock":
			return 733
		"ore_vein":
			return 761
		"herb_patch":
			return 797
		"berry_bush":
			return 821
		"fallen_branch":
			return 857
		_:
			return 911


func _round3(value: float) -> float:
	return floor(value * 1000.0 + 0.5) / 1000.0

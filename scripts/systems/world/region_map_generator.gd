class_name RegionMapGenerator
extends RefCounted

const HYDRO_CONTEXTS := ["sea", "near_sea", "lake_or_water", "near_water", "dry"]
const LANDFORM_CLASSES := ["lowland", "plain", "hills", "highland", "mountain", "valley"]
const VEGETATION_CLASSES := ["forest", "grassland", "wetland", "sparse"]
const SURFACE_CLASSES := ["soil", "sand", "rock", "mixed"]
const REQUIRED_FACT_MAPS := [
	"elevation_map",
	"moisture_map",
	"water_map",
	"forest_map",
	"rock_map",
	"slope_map",
	"water_distance_map",
]
const REQUIRED_DERIVED_MAPS := [
	"hydro_context_map",
	"landform_class_map",
	"vegetation_class_map",
	"surface_class_map",
	"local_feature_map",
]


func generate_region_map(config: Dictionary) -> Dictionary:
	var map_config: Dictionary = config.get("region_map", {}) as Dictionary
	var size: Dictionary = map_config.get("size", {}) as Dictionary
	var width := maxi(4, int(map_config.get("width", size.get("width", 18))))
	var height := maxi(4, int(map_config.get("height", size.get("height", 12))))
	var seed := int(config.get("world_seed", config.get("seed", 6501)))
	var profile_id := str(config.get("region_profile_id", config.get("profile_id", "")))
	var elevation_map := _empty_grid(height, width, 0.0)
	var moisture_map := _empty_grid(height, width, 0.0)
	var water_map := _empty_grid(height, width, 0.0)
	var forest_map := _empty_grid(height, width, 0.0)
	var rock_map := _empty_grid(height, width, 0.0)
	var hydro_context_map := _empty_grid(height, width, "")
	var landform_class_map := _empty_grid(height, width, "")
	var vegetation_class_map := _empty_grid(height, width, "")
	var surface_class_map := _empty_grid(height, width, "")
	var local_feature_map := _empty_grid(height, width, [])
	var sea_side := int(floor(_unit_hash(seed, profile_id, 701) * 4.0))
	var river_strength := float(map_config.get("river_strength", lerpf(0.20, 0.72, _unit_hash(seed, profile_id, 709))))

	for y in range(height):
		for x in range(width):
			var cell := Vector2i(x, y)
			var elevation := _layer_value(cell, seed, profile_id, 11, 0.52, 0.45, float(map_config.get("elevation_scale", 7.0)))
			var roughness := _layer_value(cell, seed, profile_id, 29, 0.42, 0.44, float(map_config.get("roughness_scale", 5.0)))
			var moisture := _layer_value(cell, seed, profile_id, 47, 0.46, 0.46, float(map_config.get("moisture_scale", 6.0)))
			var forest := _layer_value(cell, seed, profile_id, 83, 0.42, 0.50, float(map_config.get("forest_scale", 5.5)))
			var rock := _layer_value(cell, seed, profile_id, 131, 0.28, 0.48, float(map_config.get("rock_scale", 4.8)))
			var sea := _sea_influence(cell, width, height, seed, profile_id, sea_side)
			var river := _river_influence(cell, width, height, seed, profile_id) * river_strength
			var lowland_water := clampf((0.34 - elevation) / 0.22, 0.0, 1.0)
			var water := clampf(maxf(sea, maxf(river, lowland_water)), 0.0, 1.0)

			moisture = clampf(moisture + water * 0.28 - maxf(0.0, elevation - 0.62) * 0.12, 0.0, 1.0)
			forest = clampf(forest + moisture * 0.20 - rock * 0.08 - roughness * 0.06, 0.0, 1.0)
			rock = clampf(rock + roughness * 0.18 + maxf(0.0, elevation - 0.60) * 0.26, 0.0, 1.0)

			_set_grid_value(elevation_map, cell, _round3(elevation))
			_set_grid_value(moisture_map, cell, _round3(moisture))
			_set_grid_value(water_map, cell, _round3(water))
			_set_grid_value(forest_map, cell, _round3(forest))
			_set_grid_value(rock_map, cell, _round3(rock))

	var slope_map := _derive_slope_map(elevation_map, width, height)
	var water_distance_map := _derive_water_distance_map(water_map, width, height)

	for y in range(height):
		for x in range(width):
			var cell := Vector2i(x, y)
			var hydro_context := _hydro_context_for_cell(cell, elevation_map, water_map, water_distance_map, width, height)
			var landform_class := _landform_class_for_cell(cell, elevation_map, water_map, slope_map, water_distance_map)
			var vegetation_class := _vegetation_class_for_cell(cell, moisture_map, water_map, forest_map, rock_map, water_distance_map)
			var surface_class := _surface_class_for_cell(cell, hydro_context, rock_map, slope_map)
			_set_grid_value(hydro_context_map, cell, hydro_context)
			_set_grid_value(landform_class_map, cell, landform_class)
			_set_grid_value(vegetation_class_map, cell, vegetation_class)
			_set_grid_value(surface_class_map, cell, surface_class)
			_set_grid_value(local_feature_map, cell, _local_features_for_cell(
				cell,
				hydro_context,
				landform_class,
				vegetation_class,
				surface_class,
				elevation_map,
				moisture_map,
				water_map,
				forest_map,
				rock_map,
				slope_map,
				water_distance_map
			))

	return {
		"width": width,
		"height": height,
		"seed": seed,
		"region_profile_id": profile_id,
		"elevation_map": elevation_map,
		"moisture_map": moisture_map,
		"water_map": water_map,
		"forest_map": forest_map,
		"rock_map": rock_map,
		"slope_map": slope_map,
		"water_distance_map": water_distance_map,
		"hydro_context_map": hydro_context_map,
		"landform_class_map": landform_class_map,
		"vegetation_class_map": vegetation_class_map,
		"surface_class_map": surface_class_map,
		"local_feature_map": local_feature_map,
	}


func validate_region_map(region_map: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var width := int(region_map.get("width", 0))
	var height := int(region_map.get("height", 0))
	if width <= 0 or height <= 0:
		errors.append("RegionMap has invalid size")
	if region_map.has("biome_map"):
		errors.append("RegionMap contains removed biome_map world semantic path")
	for key in REQUIRED_FACT_MAPS:
		if not _map_has_size(region_map.get(key, []) as Array, width, height):
			errors.append("RegionMap %s size mismatch" % key)
	for key in REQUIRED_DERIVED_MAPS:
		if not _map_has_size(region_map.get(key, []) as Array, width, height):
			errors.append("RegionMap %s size mismatch" % key)
	_validate_class_map(region_map.get("hydro_context_map", []) as Array, HYDRO_CONTEXTS, "hydro_context", errors)
	_validate_class_map(region_map.get("landform_class_map", []) as Array, LANDFORM_CLASSES, "landform_class", errors)
	_validate_class_map(region_map.get("vegetation_class_map", []) as Array, VEGETATION_CLASSES, "vegetation_class", errors)
	_validate_class_map(region_map.get("surface_class_map", []) as Array, SURFACE_CLASSES, "surface_class", errors)
	return errors


func cell_at(region_map: Dictionary, position: Vector2i) -> Dictionary:
	if not _in_bounds(region_map, position):
		return {}
	return {
		"position": _dict_from_cell(position),
		"elevation": _map_value(region_map.get("elevation_map", []) as Array, position),
		"moisture": _map_value(region_map.get("moisture_map", []) as Array, position),
		"water": _map_value(region_map.get("water_map", []) as Array, position),
		"forest": _map_value(region_map.get("forest_map", []) as Array, position),
		"rock": _map_value(region_map.get("rock_map", []) as Array, position),
		"slope": _map_value(region_map.get("slope_map", []) as Array, position),
		"water_distance": _map_value(region_map.get("water_distance_map", []) as Array, position),
		"hydro_context": _map_string(region_map.get("hydro_context_map", []) as Array, position),
		"landform_class": _map_string(region_map.get("landform_class_map", []) as Array, position),
		"vegetation_class": _map_string(region_map.get("vegetation_class_map", []) as Array, position),
		"surface_class": _map_string(region_map.get("surface_class_map", []) as Array, position),
		"local_features": _map_array(region_map.get("local_feature_map", []) as Array, position),
	}


func patch_for(region_map: Dictionary, center: Vector2i, radius: int = 1) -> Dictionary:
	if not _in_bounds(region_map, center):
		return {}
	var positions: Array[Vector2i] = []
	var hydro_counts: Dictionary = {}
	var landform_counts: Dictionary = {}
	var vegetation_counts: Dictionary = {}
	var surface_counts: Dictionary = {}
	var elevation_total := 0.0
	var moisture_total := 0.0
	var water_total := 0.0
	var forest_total := 0.0
	var rock_total := 0.0
	var slope_total := 0.0
	var water_distance_total := 0.0
	var coast_influence := 0.0
	var river_influence := 0.0
	var features: Dictionary = {}
	for y in range(center.y - radius, center.y + radius + 1):
		for x in range(center.x - radius, center.x + radius + 1):
			var cell := Vector2i(x, y)
			if not _in_bounds(region_map, cell):
				continue
			positions.append(cell)
			var hydro_context := _map_string(region_map.get("hydro_context_map", []) as Array, cell)
			var landform_class := _map_string(region_map.get("landform_class_map", []) as Array, cell)
			var vegetation_class := _map_string(region_map.get("vegetation_class_map", []) as Array, cell)
			var surface_class := _map_string(region_map.get("surface_class_map", []) as Array, cell)
			hydro_counts[hydro_context] = int(hydro_counts.get(hydro_context, 0)) + 1
			landform_counts[landform_class] = int(landform_counts.get(landform_class, 0)) + 1
			vegetation_counts[vegetation_class] = int(vegetation_counts.get(vegetation_class, 0)) + 1
			surface_counts[surface_class] = int(surface_counts.get(surface_class, 0)) + 1
			elevation_total += _map_value(region_map.get("elevation_map", []) as Array, cell)
			moisture_total += _map_value(region_map.get("moisture_map", []) as Array, cell)
			water_total += _map_value(region_map.get("water_map", []) as Array, cell)
			forest_total += _map_value(region_map.get("forest_map", []) as Array, cell)
			rock_total += _map_value(region_map.get("rock_map", []) as Array, cell)
			slope_total += _map_value(region_map.get("slope_map", []) as Array, cell)
			water_distance_total += _map_value(region_map.get("water_distance_map", []) as Array, cell)
			if ["sea", "near_sea"].has(hydro_context):
				coast_influence += 1.0
			for feature in _map_array(region_map.get("local_feature_map", []) as Array, cell):
				var feature_id := str(feature)
				features[feature_id] = int(features.get(feature_id, 0)) + 1
				if ["riverbank", "creek_side"].has(feature_id):
					river_influence += 1.0
	var count := maxf(1.0, float(positions.size()))
	return {
		"center_position": _dict_from_cell(center),
		"center_hydro_context": _map_string(region_map.get("hydro_context_map", []) as Array, center),
		"center_landform_class": _map_string(region_map.get("landform_class_map", []) as Array, center),
		"center_vegetation_class": _map_string(region_map.get("vegetation_class_map", []) as Array, center),
		"center_surface_class": _map_string(region_map.get("surface_class_map", []) as Array, center),
		"hydro_context_counts": _clean_counts(hydro_counts),
		"landform_class_counts": _clean_counts(landform_counts),
		"vegetation_class_counts": _clean_counts(vegetation_counts),
		"surface_class_counts": _clean_counts(surface_counts),
		"average_elevation": _round3(elevation_total / count),
		"average_moisture": _round3(moisture_total / count),
		"water_influence": _round3(water_total / count),
		"forest_influence": _round3(forest_total / count),
		"rock_influence": _round3(rock_total / count),
		"slope_influence": _round3(slope_total / count),
		"water_distance": _round3(water_distance_total / count),
		"coast_influence": _round3(coast_influence / count),
		"river_influence": _round3(river_influence / count),
		"dominant_features": _dominant_features(features),
		"sample_count": positions.size(),
	}


func fingerprint(region_map: Dictionary) -> String:
	var parts: Array[String] = [
		str(region_map.get("width", "")),
		str(region_map.get("height", "")),
		str(region_map.get("seed", "")),
	]
	for key in REQUIRED_FACT_MAPS + REQUIRED_DERIVED_MAPS:
		parts.append(JSON.stringify(region_map.get(key, [])))
	return "|".join(parts)


func _derive_slope_map(elevation_map: Array, width: int, height: int) -> Array:
	var slope_map := _empty_grid(height, width, 0.0)
	for y in range(height):
		for x in range(width):
			var cell := Vector2i(x, y)
			var center := _map_value(elevation_map, cell)
			var max_delta := 0.0
			var total_delta := 0.0
			var samples := 0.0
			for offset in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var other: Vector2i = cell + offset
				if other.x < 0 or other.y < 0 or other.x >= width or other.y >= height:
					continue
				var delta := absf(center - _map_value(elevation_map, other))
				max_delta = maxf(max_delta, delta)
				total_delta += delta
				samples += 1.0
			var average_delta := total_delta / maxf(1.0, samples)
			_set_grid_value(slope_map, cell, _round3(clampf(max_delta * 1.35 + average_delta * 1.10, 0.0, 1.0)))
	return slope_map


func _derive_water_distance_map(water_map: Array, width: int, height: int) -> Array:
	var water_cells: Array[Vector2i] = []
	for y in range(height):
		for x in range(width):
			var cell := Vector2i(x, y)
			if _map_value(water_map, cell) >= 0.42:
				water_cells.append(cell)
	var result := _empty_grid(height, width, 1.0)
	var max_distance := maxf(1.0, sqrt(float(width * width + height * height)))
	for y in range(height):
		for x in range(width):
			var cell := Vector2i(x, y)
			if water_cells.is_empty():
				_set_grid_value(result, cell, 1.0)
				continue
			var best := INF
			for water_cell in water_cells:
				best = minf(best, sqrt(float(cell.distance_squared_to(water_cell))))
			_set_grid_value(result, cell, _round3(clampf(best / max_distance, 0.0, 1.0)))
	return result


func _hydro_context_for_cell(cell: Vector2i, elevation_map: Array, water_map: Array, water_distance_map: Array, width: int, height: int) -> String:
	var elevation := _map_value(elevation_map, cell)
	var water := _map_value(water_map, cell)
	var water_distance := _map_value(water_distance_map, cell)
	if _is_sea_cell(cell, elevation, water, width, height):
		return "sea"
	if _near_sea_cell(cell, elevation_map, water_map, width, height, 2):
		return "near_sea"
	if water >= 0.48:
		return "lake_or_water"
	if water_distance <= 0.18:
		return "near_water"
	return "dry"


func _landform_class_for_cell(cell: Vector2i, elevation_map: Array, water_map: Array, slope_map: Array, water_distance_map: Array) -> String:
	var elevation := _map_value(elevation_map, cell)
	var water := _map_value(water_map, cell)
	var slope := _map_value(slope_map, cell)
	var water_distance := _map_value(water_distance_map, cell)
	if water_distance <= 0.16 and elevation <= 0.48 and water < 0.78:
		return "valley"
	if elevation >= 0.76 and slope >= 0.26:
		return "mountain"
	if elevation >= 0.66:
		return "highland"
	if elevation >= 0.55 or slope >= 0.22:
		return "hills"
	if elevation <= 0.38:
		return "lowland"
	return "plain"


func _vegetation_class_for_cell(cell: Vector2i, moisture_map: Array, water_map: Array, forest_map: Array, rock_map: Array, water_distance_map: Array) -> String:
	var moisture := _map_value(moisture_map, cell)
	var water := _map_value(water_map, cell)
	var forest := _map_value(forest_map, cell)
	var rock := _map_value(rock_map, cell)
	var water_distance := _map_value(water_distance_map, cell)
	if moisture >= 0.62 and water_distance <= 0.20 and water < 0.84:
		return "wetland"
	if forest >= 0.58 and water < 0.70:
		return "forest"
	if forest <= 0.25 or moisture <= 0.24 or rock >= 0.72:
		return "sparse"
	return "grassland"


func _surface_class_for_cell(cell: Vector2i, hydro_context: String, rock_map: Array, slope_map: Array) -> String:
	var rock := _map_value(rock_map, cell)
	var slope := _map_value(slope_map, cell)
	if rock >= 0.62 or (rock >= 0.50 and slope >= 0.26):
		return "rock"
	if hydro_context == "near_sea" and rock <= 0.46:
		return "sand"
	if rock >= 0.42:
		return "mixed"
	return "soil"


func _local_features_for_cell(
	cell: Vector2i,
	hydro_context: String,
	landform_class: String,
	vegetation_class: String,
	surface_class: String,
	elevation_map: Array,
	moisture_map: Array,
	water_map: Array,
	forest_map: Array,
	rock_map: Array,
	slope_map: Array,
	water_distance_map: Array
) -> Array[String]:
	var features: Array[String] = []
	var elevation := _map_value(elevation_map, cell)
	var moisture := _map_value(moisture_map, cell)
	var water := _map_value(water_map, cell)
	var forest := _map_value(forest_map, cell)
	var rock := _map_value(rock_map, cell)
	var slope := _map_value(slope_map, cell)
	var water_distance := _map_value(water_distance_map, cell)
	if hydro_context == "near_sea":
		features.append("near_sea")
		if surface_class == "sand":
			features.append("beach")
	if ["near_water", "lake_or_water"].has(hydro_context) and water < 0.82:
		features.append("water_influence")
		if water_distance <= 0.12 or landform_class == "valley":
			features.append("riverbank")
		if water_distance <= 0.16 and ["forest", "wetland"].has(vegetation_class):
			features.append("creek_side")
	if moisture >= 0.62:
		features.append("high_moisture")
	if forest >= 0.66:
		features.append("dense_forest")
	if ["hills", "highland"].has(landform_class) and elevation >= 0.48 and elevation <= 0.74 and slope >= 0.16:
		features.append("foothill")
	if (rock >= 0.60 and slope >= 0.18) or surface_class == "rock":
		features.append("rocky_slope")
	if vegetation_class == "forest" and forest <= 0.70 and moisture >= 0.36:
		features.append("clearing")
	return _unique_strings(features)


func _is_sea_cell(cell: Vector2i, elevation: float, water: float, width: int, height: int) -> bool:
	if water < 0.70 or elevation > 0.50:
		return false
	if water >= 0.84 and elevation <= 0.46:
		return true
	return _edge_distance(cell, width, height) <= 3


func _near_sea_cell(cell: Vector2i, elevation_map: Array, water_map: Array, width: int, height: int, radius: int) -> bool:
	for y in range(cell.y - radius, cell.y + radius + 1):
		for x in range(cell.x - radius, cell.x + radius + 1):
			var other := Vector2i(x, y)
			if other == cell or other.x < 0 or other.y < 0 or other.x >= width or other.y >= height:
				continue
			if _is_sea_cell(other, _map_value(elevation_map, other), _map_value(water_map, other), width, height):
				return true
	return false


func _edge_distance(cell: Vector2i, width: int, height: int) -> int:
	return mini(mini(cell.x, cell.y), mini(width - 1 - cell.x, height - 1 - cell.y))


func _validate_class_map(map_data: Array, allowed_values: Array, label: String, errors: Array[String]) -> void:
	for y in range(map_data.size()):
		var row: Array = map_data[y] as Array
		for x in range(row.size()):
			var value := str(row[x])
			if not allowed_values.has(value):
				errors.append("RegionMap contains unsupported %s: %s at %s" % [label, value, str(Vector2i(x, y))])


func _clean_counts(counts: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for key_value in counts.keys():
		var key := str(key_value)
		if not key.is_empty():
			result[key] = int(counts.get(key_value, 0))
	return result


func _dominant_features(features: Dictionary) -> Array[String]:
	var rows: Array[Dictionary] = []
	for feature_value in features.keys():
		rows.append({
			"id": str(feature_value),
			"count": int(features.get(feature_value, 0)),
		})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a.get("count", 0)) == int(b.get("count", 0)):
			return str(a.get("id", "")) < str(b.get("id", ""))
		return int(a.get("count", 0)) > int(b.get("count", 0))
	)
	var result: Array[String] = []
	for row in rows:
		result.append(str(row.get("id", "")))
	return result


func _sea_influence(cell: Vector2i, width: int, height: int, seed: int, profile_id: String, side: int) -> float:
	var cross := 0.0
	var length := 0.0
	var max_cross := 1.0
	match side:
		0:
			cross = float(cell.y)
			length = float(cell.x)
			max_cross = float(height)
		1:
			cross = float(width - 1 - cell.x)
			length = float(cell.y)
			max_cross = float(width)
		2:
			cross = float(height - 1 - cell.y)
			length = float(cell.x)
			max_cross = float(height)
		_:
			cross = float(cell.x)
			length = float(cell.y)
			max_cross = float(width)
	var shoreline := max_cross * lerpf(0.13, 0.28, _unit_hash(seed, profile_id, 733))
	var curve := (_value_noise(Vector2(length / 5.0, float(seed % 37)), seed, profile_id, 739) - 0.5) * max_cross * 0.24
	var distance := cross - (shoreline + curve)
	return clampf(1.0 - smoothstep(-1.0, maxf(1.0, max_cross * 0.12), distance), 0.0, 1.0)


func _river_influence(cell: Vector2i, width: int, height: int, seed: int, profile_id: String) -> float:
	var vertical := _unit_hash(seed, profile_id, 811) >= 0.5
	var length_axis := float(cell.y if vertical else cell.x)
	var cross_axis := float(cell.x if vertical else cell.y)
	var max_cross := float(width if vertical else height)
	var base := max_cross * lerpf(0.28, 0.72, _unit_hash(seed, profile_id, 823))
	var curve := (_value_noise(Vector2(length_axis / 4.5, float(seed % 53)), seed, profile_id, 827) - 0.5) * max_cross * 0.30
	var river_width := maxf(1.0, max_cross * lerpf(0.06, 0.12, _unit_hash(seed, profile_id, 829)))
	var distance := absf(cross_axis - (base + curve))
	if distance >= river_width:
		return 0.0
	return 1.0 - smoothstep(river_width * 0.35, river_width, distance)


func _layer_value(cell: Vector2i, seed: int, profile_id: String, salt: int, bias: float, amplitude: float, scale: float) -> float:
	return clampf(bias + (_fbm_unit(cell, seed, profile_id, salt, scale, 4) - 0.5) * amplitude, 0.0, 1.0)


func _fbm_unit(cell: Vector2i, seed: int, profile_id: String, salt: int, scale: float, octaves: int) -> float:
	var value := 0.0
	var amplitude := 0.5
	var frequency := 1.0
	var total := 0.0
	for _index in range(octaves):
		value += _value_noise(Vector2(float(cell.x) * frequency / maxf(1.0, scale), float(cell.y) * frequency / maxf(1.0, scale)), seed, profile_id, salt) * amplitude
		total += amplitude
		amplitude *= 0.5
		frequency *= 2.0
	return value / maxf(0.001, total)


func _value_noise(point: Vector2, seed: int, profile_id: String, salt: int) -> float:
	var x0 := floori(point.x)
	var y0 := floori(point.y)
	var xf := point.x - float(x0)
	var yf := point.y - float(y0)
	var sx := xf * xf * (3.0 - 2.0 * xf)
	var sy := yf * yf * (3.0 - 2.0 * yf)
	var n00 := _unit_hash_xy(seed, profile_id, x0, y0, salt)
	var n10 := _unit_hash_xy(seed, profile_id, x0 + 1, y0, salt)
	var n01 := _unit_hash_xy(seed, profile_id, x0, y0 + 1, salt)
	var n11 := _unit_hash_xy(seed, profile_id, x0 + 1, y0 + 1, salt)
	return lerpf(lerpf(n00, n10, sx), lerpf(n01, n11, sx), sy)


func _unit_hash(seed: int, profile_id: String, salt: int) -> float:
	return _unit_hash_xy(seed, profile_id, 0, 0, salt)


func _unit_hash_xy(seed: int, profile_id: String, x: int, y: int, salt: int) -> float:
	var value := sin(float(x) * 12.9898 + float(y) * 78.233 + float(seed + salt) * 37.719 + float(abs(hash(profile_id)) % 10000) * 0.017) * 43758.5453123
	return value - floor(value)


func _empty_grid(height: int, width: int, value: Variant) -> Array:
	var result: Array = []
	for _y in range(height):
		var row: Array = []
		for _x in range(width):
			if value is Array:
				row.append((value as Array).duplicate(true))
			else:
				row.append(value)
		result.append(row)
	return result


func _map_has_size(map_data: Array, width: int, height: int) -> bool:
	if map_data.size() != height:
		return false
	for row_value in map_data:
		var row: Array = row_value as Array
		if row.size() != width:
			return false
	return true


func _in_bounds(region_map: Dictionary, cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < int(region_map.get("width", 0)) and cell.y < int(region_map.get("height", 0))


func _map_value(map_data: Array, cell: Vector2i) -> float:
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


func _map_array(map_data: Array, cell: Vector2i) -> Array:
	if cell.y < 0 or cell.y >= map_data.size():
		return []
	var row: Array = map_data[cell.y] as Array
	if cell.x < 0 or cell.x >= row.size():
		return []
	return (row[cell.x] as Array).duplicate(true)


func _set_grid_value(map_data: Array, cell: Vector2i, value: Variant) -> void:
	var row: Array = map_data[cell.y] as Array
	row[cell.x] = value


func _dict_from_cell(cell: Vector2i) -> Dictionary:
	return { "x": cell.x, "y": cell.y }


func _unique_strings(values: Array[String]) -> Array[String]:
	var result: Array[String] = []
	for value in values:
		if not value.is_empty() and not result.has(value):
			result.append(value)
	return result


func _round3(value: float) -> float:
	return snappedf(value, 0.001)

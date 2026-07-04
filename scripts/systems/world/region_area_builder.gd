class_name RegionAreaBuilder
extends RefCounted

const RegionMapGeneratorScript := preload("res://scripts/systems/world/region_map_generator.gd")

const AREA_TYPES := [
	"plain",
	"forest",
	"hills",
	"highland",
	"mountain",
	"river_valley",
	"wetland",
	"lake_region",
	"coastland",
	"rocky_wilds",
	"settlement_area",
]
const SMALL_SCALE_TYPES := [
	"foothill",
	"riverbank",
	"coast_edge",
	"beach",
	"creek_side",
	"clearing",
	"entrance",
	"path",
	"slope",
	"rocky_slope",
	"forest_edge",
]

var _region_map_generator: RefCounted = RegionMapGeneratorScript.new()


func build_region_areas(region_map: Dictionary, config: Dictionary) -> Array[Dictionary]:
	var width := int(region_map.get("width", 0))
	var height := int(region_map.get("height", 0))
	var world_id := str(config.get("world_id", "world"))
	var unplaceable_area_types := _string_array(config.get("unplaceable_area_types", []) as Array)
	var visited: Dictionary = {}
	var cell_to_area: Dictionary = {}
	var area_type_by_cell: Dictionary = {}
	var areas: Array[Dictionary] = []

	for y in range(height):
		for x in range(width):
			var cell := Vector2i(x, y)
			var region_cell: Dictionary = _region_map_generator.cell_at(region_map, cell)
			var area_type := _area_type_for_cell(region_cell)
			area_type_by_cell[_position_key(cell)] = area_type

	for y in range(height):
		for x in range(width):
			var cell := Vector2i(x, y)
			var cell_key := _position_key(cell)
			if visited.has(cell_key):
				continue
			var area_type := str(area_type_by_cell.get(cell_key, ""))
			var cells := _collect_area_cells(region_map, cell, area_type, visited, area_type_by_cell)
			if cells.is_empty():
				continue
			var area_index := areas.size()
			var region_id := "%s_region_%03d" % [world_id, area_index]
			for area_cell in cells:
				cell_to_area[_position_key(area_cell)] = region_id
			var area := _area_from_cells(region_id, area_index, area_type, cells, region_map, config, unplaceable_area_types)
			areas.append(area)

	_assign_adjacency(areas, cell_to_area, width, height)
	return areas


func validate_region_areas(region_map: Dictionary, region_areas: Array) -> Array[String]:
	var errors: Array[String] = []
	var width := int(region_map.get("width", 0))
	var height := int(region_map.get("height", 0))
	var ids: Dictionary = {}
	var cell_owners: Dictionary = {}
	if region_areas.is_empty():
		errors.append("region_areas is missing")
	for area_value in region_areas:
		var area: Dictionary = area_value as Dictionary
		var region_id := str(area.get("region_id", ""))
		var area_type := str(area.get("area_type", ""))
		if region_id.is_empty():
			errors.append("RegionArea missing region_id")
			continue
		if ids.has(region_id):
			errors.append("duplicate RegionArea id: %s" % region_id)
			continue
		ids[region_id] = true
		if area.has("dominant_biome"):
			errors.append("RegionArea contains removed dominant_biome main path: %s" % region_id)
		if area_type.is_empty():
			errors.append("RegionArea missing area_type: %s" % region_id)
		elif not AREA_TYPES.has(area_type):
			errors.append("RegionArea has unsupported area_type: %s/%s" % [region_id, area_type])
		elif SMALL_SCALE_TYPES.has(area_type):
			errors.append("RegionArea uses small-scale area_type: %s/%s" % [region_id, area_type])
		var display_name := str(area.get("display_name", ""))
		if display_name.is_empty():
			errors.append("RegionArea missing display_name: %s" % region_id)
		elif _display_name_uses_small_scale_term(display_name):
			errors.append("RegionArea display_name uses local-scale term: %s/%s" % [region_id, display_name])
		if (area.get("center_position", {}) as Dictionary).is_empty():
			errors.append("RegionArea missing center_position: %s" % region_id)
		var cells: Array = area.get("cells", []) as Array
		if cells.is_empty():
			errors.append("RegionArea has no cells: %s" % region_id)
		for cell_value in cells:
			var cell := _cell_from_dict(cell_value as Dictionary)
			if cell.x < 0 or cell.y < 0 or cell.x >= width or cell.y >= height:
				errors.append("RegionArea cell out of bounds: %s/%s" % [region_id, str(cell)])
				continue
			var cell_key := _position_key(cell)
			if cell_owners.has(cell_key):
				errors.append("RegionArea cell belongs to multiple areas: %s" % cell_key)
			cell_owners[cell_key] = region_id
			var expected_type := _area_type_for_cell(_region_map_generator.cell_at(region_map, cell))
			if expected_type != area_type:
				errors.append("RegionArea cell area_type mismatch: %s/%s" % [region_id, cell_key])
		var generated_ids: Array = area.get("generated_location_node_ids", []) as Array
		for generated_id_value in generated_ids:
			if str(generated_id_value).is_empty():
				errors.append("RegionArea has empty generated location id: %s" % region_id)
	for area_value in region_areas:
		var area: Dictionary = area_value as Dictionary
		var region_id := str(area.get("region_id", ""))
		for adjacent_value in (area.get("adjacent_region_ids", []) as Array):
			var adjacent_id := str(adjacent_value)
			if adjacent_id == region_id:
				errors.append("RegionArea is adjacent to itself: %s" % region_id)
			elif not ids.has(adjacent_id):
				errors.append("RegionArea references unknown adjacent region: %s -> %s" % [region_id, adjacent_id])
	return errors


func area_for_position(region_areas: Array, position: Vector2i) -> Dictionary:
	var key := _position_key(position)
	for area_value in region_areas:
		var area: Dictionary = area_value as Dictionary
		for cell_value in (area.get("cells", []) as Array):
			if _position_key(_cell_from_dict(cell_value as Dictionary)) == key:
				return area.duplicate(true)
	return {}


func _collect_area_cells(region_map: Dictionary, start: Vector2i, area_type: String, visited: Dictionary, area_type_by_cell: Dictionary) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var open: Array[Vector2i] = [start]
	while not open.is_empty():
		var cell: Vector2i = open.pop_front()
		var cell_key := _position_key(cell)
		if visited.has(cell_key):
			continue
		visited[cell_key] = true
		if str(area_type_by_cell.get(cell_key, "")) != area_type:
			continue
		result.append(cell)
		for offset in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var next: Vector2i = cell + offset
			if not _in_bounds(region_map, next):
				continue
			if visited.has(_position_key(next)):
				continue
			if str(area_type_by_cell.get(_position_key(next), "")) == area_type:
				open.append(next)
	return result


func _area_from_cells(
	region_id: String,
	area_index: int,
	area_type: String,
	cells: Array[Vector2i],
	region_map: Dictionary,
	config: Dictionary,
	unplaceable_area_types: Array[String]
) -> Dictionary:
	var min_x := 999999
	var min_y := 999999
	var max_x := -999999
	var max_y := -999999
	var total := Vector2.ZERO
	var features: Dictionary = {}
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
	for cell in cells:
		min_x = mini(min_x, cell.x)
		min_y = mini(min_y, cell.y)
		max_x = maxi(max_x, cell.x)
		max_y = maxi(max_y, cell.y)
		total += Vector2(float(cell.x), float(cell.y))
		var region_cell: Dictionary = _region_map_generator.cell_at(region_map, cell)
		_count_value(hydro_counts, str(region_cell.get("hydro_context", "")))
		_count_value(landform_counts, str(region_cell.get("landform_class", "")))
		_count_value(vegetation_counts, str(region_cell.get("vegetation_class", "")))
		_count_value(surface_counts, str(region_cell.get("surface_class", "")))
		elevation_total += float(region_cell.get("elevation", 0.0))
		moisture_total += float(region_cell.get("moisture", 0.0))
		water_total += float(region_cell.get("water", 0.0))
		forest_total += float(region_cell.get("forest", 0.0))
		rock_total += float(region_cell.get("rock", 0.0))
		slope_total += float(region_cell.get("slope", 0.0))
		water_distance_total += float(region_cell.get("water_distance", 1.0))
		for feature_value in (region_cell.get("local_features", []) as Array):
			_count_value(features, str(feature_value))
	var center_float := total / maxf(1.0, float(cells.size()))
	var center := _nearest_cell(cells, Vector2i(roundi(center_float.x), roundi(center_float.y)))
	var node_budget := _node_budget_for_area(area_type, cells.size(), config, unplaceable_area_types)
	var count := maxf(1.0, float(cells.size()))
	return {
		"region_id": region_id,
		"display_name": "%s %02d" % [_area_type_label(area_type), area_index],
		"area_type": area_type,
		"cells": _cell_dicts(cells),
		"bounds": {
			"min_x": min_x,
			"min_y": min_y,
			"max_x": max_x,
			"max_y": max_y,
			"width": max_x - min_x + 1,
			"height": max_y - min_y + 1,
		},
		"center_position": _dict_from_cell(center),
		"features": _dominant_features(features),
		"context_summary": {
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
		},
		"adjacent_region_ids": [],
		"node_budget": node_budget,
		"generated_location_node_ids": [],
		"metadata": {
			"source": "region_area_builder",
			"cell_count": cells.size(),
			"placeable": node_budget > 0,
		},
	}


func _area_type_for_cell(region_cell: Dictionary) -> String:
	var hydro_context := str(region_cell.get("hydro_context", ""))
	var landform_class := str(region_cell.get("landform_class", ""))
	var vegetation_class := str(region_cell.get("vegetation_class", ""))
	var surface_class := str(region_cell.get("surface_class", ""))
	var water := float(region_cell.get("water", 0.0))
	var moisture := float(region_cell.get("moisture", 0.0))
	var rock := float(region_cell.get("rock", 0.0))
	var slope := float(region_cell.get("slope", 0.0))
	var water_distance := float(region_cell.get("water_distance", 1.0))
	if hydro_context == "sea" or (hydro_context == "lake_or_water" and water >= 0.66):
		return "lake_region"
	if hydro_context == "near_sea":
		return "coastland"
	if vegetation_class == "wetland" or (moisture >= 0.64 and water_distance <= 0.18):
		return "wetland"
	if landform_class == "valley" and ["near_water", "lake_or_water"].has(hydro_context):
		return "river_valley"
	if vegetation_class == "forest" and water < 0.66:
		return "forest"
	if surface_class == "rock" and (rock >= 0.66 or slope >= 0.24):
		return "rocky_wilds"
	match landform_class:
		"mountain":
			return "mountain"
		"highland":
			return "highland"
		"hills":
			return "hills"
		"lowland":
			return "wetland" if moisture >= 0.56 and water_distance <= 0.28 else "plain"
		_:
			return "plain"


func _assign_adjacency(areas: Array[Dictionary], cell_to_area: Dictionary, width: int, height: int) -> void:
	var index_by_id: Dictionary = {}
	for index in range(areas.size()):
		var area: Dictionary = areas[index] as Dictionary
		index_by_id[str(area.get("region_id", ""))] = index
	var adjacency: Dictionary = {}
	for y in range(height):
		for x in range(width):
			var cell := Vector2i(x, y)
			var area_id := str(cell_to_area.get(_position_key(cell), ""))
			if area_id.is_empty():
				continue
			for offset in [Vector2i.RIGHT, Vector2i.DOWN]:
				var next: Vector2i = cell + offset
				if next.x >= width or next.y >= height:
					continue
				var other_id := str(cell_to_area.get(_position_key(next), ""))
				if other_id.is_empty() or other_id == area_id:
					continue
				_add_adjacency(adjacency, area_id, other_id)
				_add_adjacency(adjacency, other_id, area_id)
	for region_id_value in adjacency.keys():
		var region_id := str(region_id_value)
		var index := int(index_by_id.get(region_id, -1))
		if index < 0:
			continue
		var area: Dictionary = areas[index] as Dictionary
		var adjacent: Array = adjacency.get(region_id, []) as Array
		adjacent.sort()
		area["adjacent_region_ids"] = adjacent
		areas[index] = area


func _add_adjacency(adjacency: Dictionary, from_id: String, to_id: String) -> void:
	var rows: Array = adjacency.get(from_id, []) as Array
	if not rows.has(to_id):
		rows.append(to_id)
	adjacency[from_id] = rows


func _node_budget_for_area(area_type: String, cell_count: int, config: Dictionary, unplaceable_area_types: Array[String]) -> int:
	if unplaceable_area_types.has(area_type):
		return 0
	var area_config: Dictionary = config.get("region_area", {}) as Dictionary
	var min_budget := int(area_config.get("min_node_budget", 1))
	var max_budget := int(area_config.get("max_node_budget", 4))
	var size_step := maxf(1.0, float(area_config.get("cells_per_node_budget", 5.0)))
	return clampi(int(ceil(float(cell_count) / size_step)), min_budget, max_budget)


func _area_type_label(area_type: String) -> String:
	match area_type:
		"forest":
			return "森林区域"
		"hills":
			return "丘陵区域"
		"highland":
			return "高地区域"
		"mountain":
			return "山地区域"
		"river_valley":
			return "河谷区域"
		"wetland":
			return "湿地区域"
		"lake_region":
			return "湖区"
		"coastland":
			return "海岸带区域"
		"rocky_wilds":
			return "岩地荒野区域"
		"settlement_area":
			return "聚居区域"
		_:
			return "平原区域"


func _display_name_uses_small_scale_term(display_name: String) -> bool:
	for term in ["山脚区域", "河岸区域", "入口区域", "小路区域", "空地区域", "岩坡区域", "溪流边区域"]:
		if display_name.contains(term):
			return true
	return false


func _nearest_cell(cells: Array[Vector2i], target: Vector2i) -> Vector2i:
	var best := cells[0]
	var best_distance := INF
	for cell in cells:
		var distance := float(cell.distance_squared_to(target))
		if distance < best_distance:
			best_distance = distance
			best = cell
	return best


func _count_value(counts: Dictionary, value: String) -> void:
	if value.is_empty():
		return
	counts[value] = int(counts.get(value, 0)) + 1


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


func _clean_counts(counts: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for key_value in counts.keys():
		var key := str(key_value)
		if not key.is_empty():
			result[key] = int(counts.get(key_value, 0))
	return result


func _cell_dicts(cells: Array[Vector2i]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for cell in cells:
		result.append(_dict_from_cell(cell))
	return result


func _in_bounds(region_map: Dictionary, cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < int(region_map.get("width", 0)) and cell.y < int(region_map.get("height", 0))


func _cell_from_dict(value: Dictionary) -> Vector2i:
	return Vector2i(int(value.get("x", -1)), int(value.get("y", -1)))


func _dict_from_cell(cell: Vector2i) -> Dictionary:
	return { "x": cell.x, "y": cell.y }


func _position_key(cell: Vector2i) -> String:
	return "%d,%d" % [cell.x, cell.y]


func _string_array(values: Array) -> Array[String]:
	var result: Array[String] = []
	for value in values:
		var text := str(value)
		if not text.is_empty():
			result.append(text)
	return result


func _round3(value: float) -> float:
	return snappedf(value, 0.001)

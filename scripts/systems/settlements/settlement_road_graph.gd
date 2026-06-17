class_name SettlementRoadGraph
extends RefCounted


static func analyze_blueprint(blueprint: Dictionary, entrances: Array, map_size: Vector2i = Vector2i.ZERO) -> Dictionary:
	var road_cells := _collect_blueprint_road_cells(blueprint)
	var road_segment_rows := _collect_blueprint_road_segments(blueprint)
	var entrance_cells := _cell_array(entrances)
	var core_cells := _collect_blueprint_core_cells(blueprint)
	var plot_access_rows := _collect_blueprint_plot_access(blueprint)
	var building_access_rows := _collect_blueprint_building_access(blueprint)
	var public_access_rows := _filter_public_plot_access(plot_access_rows)
	return _analyze(road_cells, road_segment_rows, entrance_cells, core_cells, plot_access_rows, building_access_rows, public_access_rows, map_size)


static func analyze_compiled_location(location_data: Dictionary) -> Dictionary:
	var road_cells := _collect_compiled_road_cells(location_data)
	var entrance_cells := _collect_compiled_entrances(location_data)
	var core_cells := _collect_compiled_core_cells(location_data)
	var summary: Dictionary = location_data.get("generation_summary", {}) as Dictionary
	var road_segment_rows := _normalize_road_segments(summary.get("road_segments", []))
	var plot_access_rows := _normalize_access_rows(summary.get("plot_access", []), "road_access_cell")
	var building_access_rows := _normalize_access_rows(summary.get("building_access", []), "front_access_cell")
	var public_access_rows := _filter_public_plot_access(plot_access_rows)
	var size: Dictionary = location_data.get("size", {}) as Dictionary
	var map_size := Vector2i(int(size.get("width", 0)), int(size.get("height", 0)))
	var result := _analyze(road_cells, road_segment_rows, entrance_cells, core_cells, plot_access_rows, building_access_rows, public_access_rows, map_size)
	result["compiled_road_connected"] = bool(result.get("all_roads_connected_to_entrance", false))
	result["compiled_entrance_connected"] = bool(result.get("entrance_connected", false))
	result["compiled_core_connected"] = bool(result.get("core_connected", false))
	result["compiled_plot_access_connected"] = bool(result.get("all_plot_access_connected", false))
	result["compiled_building_front_connected"] = bool(result.get("all_building_front_connected", false))
	return result


static func road_segment_summary(blueprint: Dictionary) -> Array[Dictionary]:
	return _collect_blueprint_road_segments(blueprint)


static func plot_access_summary(blueprint: Dictionary) -> Array[Dictionary]:
	return _collect_blueprint_plot_access(blueprint)


static func building_access_summary(blueprint: Dictionary) -> Array[Dictionary]:
	return _collect_blueprint_building_access(blueprint)


static func _analyze(
	road_cells: Array[Vector2i],
	road_segment_rows: Array[Dictionary],
	entrance_cells: Array[Vector2i],
	core_cells: Array[Vector2i],
	plot_access_rows: Array[Dictionary],
	building_access_rows: Array[Dictionary],
	public_access_rows: Array[Dictionary],
	map_size: Vector2i
) -> Dictionary:
	var road_lookup := _cell_lookup(road_cells)
	var main_component := _main_component_from_entrances(road_lookup, entrance_cells)
	var main_lookup := _cell_lookup(main_component)
	var components := _road_components(road_lookup)
	var failed_entrances := _failed_entrances(entrance_cells, main_lookup)
	var disconnected_core_cells: Array[Dictionary] = []
	var disconnected_road_cells: Array[Vector2i] = []
	var disconnected_road_segment_ids: Array[String] = []
	var disconnected_plot_ids: Array[String] = []
	var disconnected_plot_access: Array[Dictionary] = []
	var disconnected_building_ids: Array[String] = []
	var disconnected_building_front_access: Array[Dictionary] = []
	var public_connected := false

	for road_cell in road_cells:
		if not main_lookup.has(_cell_key(road_cell)):
			disconnected_road_cells.append(road_cell)
	for row in road_segment_rows:
		if not _road_segment_on_main_component(row, main_lookup):
			disconnected_road_segment_ids.append(str(row.get("id", "")))

	for core_cell in core_cells:
		if not _cell_touches_component(core_cell, main_lookup):
			disconnected_core_cells.append(_dict_cell(core_cell))

	for row in plot_access_rows:
		var access_cell := _cell_from_variant(row.get("road_access_cell", {}))
		if not main_lookup.has(_cell_key(access_cell)):
			disconnected_plot_ids.append(str(row.get("id", "")))
			disconnected_plot_access.append({
				"id": str(row.get("id", "")),
				"road_access_cell": _dict_cell(access_cell),
			})
	for row in public_access_rows:
		var access_cell := _cell_from_variant(row.get("road_access_cell", {}))
		if main_lookup.has(_cell_key(access_cell)):
			public_connected = true
			break

	for row in building_access_rows:
		var front_access_cell := _cell_from_variant(row.get("front_access_cell", {}))
		if not main_lookup.has(_cell_key(front_access_cell)):
			disconnected_building_ids.append(str(row.get("id", "")))
			disconnected_building_front_access.append({
				"id": str(row.get("id", "")),
				"front_access_cell": _dict_cell(front_access_cell),
			})

	var disconnected_road_cell_count: int = max(0, road_cells.size() - main_component.size())
	var roads_connected := road_cells.size() > 0 and components.size() == 1 and disconnected_road_cell_count == 0
	var core_connected := not core_cells.is_empty() and disconnected_core_cells.is_empty()
	var entrance_connected := not main_component.is_empty() and failed_entrances.is_empty() and (core_connected or public_connected)
	var plot_access_connected := disconnected_plot_ids.is_empty()
	var building_front_connected := disconnected_building_ids.is_empty()
	return {
		"map_size": { "width": map_size.x, "height": map_size.y },
		"road_cell_count": road_cells.size(),
		"road_component_count": components.size(),
		"main_road_cell_count": main_component.size(),
		"main_road_cells": _cells_to_dicts(main_component),
		"disconnected_road_cells": _cells_to_dicts(disconnected_road_cells),
		"disconnected_road_segment_ids": disconnected_road_segment_ids,
		"disconnected_road_cell_count": disconnected_road_cell_count,
		"entrance_count": entrance_cells.size(),
		"entrance_connected_to_road": not main_component.is_empty(),
		"entrance_connected": entrance_connected,
		"failed_entrances": failed_entrances,
		"all_roads_connected_to_entrance": roads_connected,
		"core_count": core_cells.size(),
		"main_component_reaches_core": core_connected,
		"core_connected": core_connected,
		"public_connected": public_connected,
		"disconnected_core_cells": disconnected_core_cells,
		"plot_access_count": plot_access_rows.size(),
		"all_plots_access_main_road": plot_access_connected,
		"all_plot_access_connected": plot_access_connected,
		"disconnected_plot_ids": disconnected_plot_ids,
		"disconnected_plot_access": disconnected_plot_access,
		"building_access_count": building_access_rows.size(),
		"all_buildings_access_main_road": building_front_connected,
		"all_building_front_connected": building_front_connected,
		"disconnected_building_ids": disconnected_building_ids,
		"disconnected_building_front_access": disconnected_building_front_access,
	}


static func _main_component_from_entrances(road_lookup: Dictionary, entrance_cells: Array[Vector2i]) -> Array[Vector2i]:
	var seeds: Array[Vector2i] = _entrance_road_seeds(road_lookup, entrance_cells[0] if not entrance_cells.is_empty() else Vector2i(-9999, -9999))
	if seeds.is_empty():
		return []
	return _flood_fill(road_lookup, seeds)


static func _entrance_road_seeds(road_lookup: Dictionary, entrance: Vector2i) -> Array[Vector2i]:
	var seeds: Array[Vector2i] = []
	if entrance.x < 0 or entrance.y < 0:
		return seeds
	for direction in _directions_with_zero():
		var candidate := entrance + direction
		if road_lookup.has(_cell_key(candidate)) and not seeds.has(candidate):
			seeds.append(candidate)
	return seeds


static func _failed_entrances(entrance_cells: Array[Vector2i], main_lookup: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for index in range(entrance_cells.size()):
		var entrance := entrance_cells[index]
		if _cell_touches_component(entrance, main_lookup):
			continue
		result.append({
			"id": "entrance_%d" % index,
			"cell": _dict_cell(entrance),
		})
	return result


static func _road_segment_on_main_component(row: Dictionary, main_lookup: Dictionary) -> bool:
	var cells: Array = row.get("path", []) as Array
	if cells.is_empty():
		return false
	for cell_value in cells:
		var cell := _cell_from_variant(cell_value)
		if not main_lookup.has(_cell_key(cell)):
			return false
	return true


static func _road_components(road_lookup: Dictionary) -> Array:
	var components: Array = []
	var visited: Dictionary = {}
	for key in road_lookup.keys():
		if visited.has(key):
			continue
		var cell := _cell_from_key(str(key))
		var component := _flood_fill(road_lookup, [cell], visited)
		components.append(component)
	return components


static func _flood_fill(road_lookup: Dictionary, seeds: Array[Vector2i], external_visited: Dictionary = {}) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var visited := external_visited
	var queue: Array[Vector2i] = []
	for seed in seeds:
		var seed_key := _cell_key(seed)
		if not road_lookup.has(seed_key) or visited.has(seed_key):
			continue
		queue.append(seed)
		visited[seed_key] = true

	while not queue.is_empty():
		var cell: Vector2i = queue.pop_front()
		result.append(cell)
		for direction in _directions():
			var next := cell + direction
			var next_key := _cell_key(next)
			if not road_lookup.has(next_key) or visited.has(next_key):
				continue
			visited[next_key] = true
			queue.append(next)
	return result


static func _cell_touches_component(cell: Vector2i, component_lookup: Dictionary) -> bool:
	for direction in _directions_with_zero():
		if component_lookup.has(_cell_key(cell + direction)):
			return true
	return false


static func _collect_blueprint_road_cells(blueprint: Dictionary) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for road_value in (blueprint.get("roads", []) as Array):
		var road: Dictionary = road_value as Dictionary
		for cell_value in (road.get("path", []) as Array):
			_append_unique_cell(result, _cell_from_variant(cell_value))
	return result


static func _collect_blueprint_road_segments(blueprint: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for index in range((blueprint.get("roads", []) as Array).size()):
		var road: Dictionary = (blueprint.get("roads", []) as Array)[index] as Dictionary
		var path: Array[Dictionary] = []
		for cell_value in (road.get("path", []) as Array):
			path.append(_dict_cell(_cell_from_variant(cell_value)))
		result.append({
			"id": str(road.get("id", "road_%d" % index)),
			"kind": str(road.get("kind", "settlement_road")),
			"path": path,
		})
	return result


static func _collect_blueprint_core_cells(blueprint: Dictionary) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for core_value in (blueprint.get("cores", []) as Array):
		var core: Dictionary = core_value as Dictionary
		_append_unique_cell(result, _cell_from_variant(core.get("cell", {})))
	return result


static func _collect_blueprint_plot_access(blueprint: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for plot_value in (blueprint.get("plots", []) as Array):
		var plot: Dictionary = plot_value as Dictionary
		var cell := _cell_from_variant(plot.get("road_access_cell", {}))
		result.append({
			"id": str(plot.get("id", "")),
			"use": str(plot.get("use", "")),
			"status": str(plot.get("status", "")),
			"road_access_cell": _dict_cell(cell),
		})
	return result


static func _collect_blueprint_building_access(blueprint: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for building_value in (blueprint.get("buildings", []) as Array):
		var building: Dictionary = building_value as Dictionary
		var cell := _cell_from_variant(building.get("front_access_cell", {}))
		result.append({
			"id": str(building.get("id", "")),
			"plot_id": str(building.get("plot_id", "")),
			"use_type": str(building.get("use_type", "")),
			"front_access_cell": _dict_cell(cell),
		})
	return result


static func _collect_compiled_road_cells(location_data: Dictionary) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var terrain: Dictionary = location_data.get("terrain", {}) as Dictionary
	var rows: Array = location_data.get("tiles", []) as Array
	for y in range(rows.size()):
		var row := str(rows[y])
		for x in range(row.length()):
			var key := row.substr(x, 1)
			var terrain_row: Dictionary = terrain.get(key, {}) as Dictionary
			if str(terrain_row.get("id", "")) == "path":
				result.append(Vector2i(x, y))
	return result


static func _collect_compiled_entrances(location_data: Dictionary) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for entrance_value in (location_data.get("entrances", []) as Array):
		var entrance: Dictionary = entrance_value as Dictionary
		result.append(_cell_from_variant(entrance.get("grid_position", {})))
	return result


static func _collect_compiled_core_cells(location_data: Dictionary) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for anchor_value in (location_data.get("anchors", []) as Array):
		var anchor: Dictionary = anchor_value as Dictionary
		if str(anchor.get("kind", "")) != "core":
			continue
		_append_unique_cell(result, _cell_from_variant(anchor.get("grid_position", {})))
	return result


static func _normalize_access_rows(value: Variant, cell_key: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for row_value in (value as Array):
		var row: Dictionary = row_value as Dictionary
		var cell := _cell_from_variant(row.get(cell_key, row.get("cell", {})))
		var normalized := row.duplicate(true)
		normalized[cell_key] = _dict_cell(cell)
		result.append(normalized)
	return result


static func _normalize_road_segments(value: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for index in range((value as Array).size()):
		var row: Dictionary = (value as Array)[index] as Dictionary
		var path: Array[Dictionary] = []
		for cell_value in (row.get("path", []) as Array):
			path.append(_dict_cell(_cell_from_variant(cell_value)))
		result.append({
			"id": str(row.get("id", "road_%d" % index)),
			"kind": str(row.get("kind", "settlement_road")),
			"path": path,
		})
	return result


static func _filter_public_plot_access(plot_access_rows: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for row in plot_access_rows:
		if str(row.get("use", "")) == "public":
			result.append(row)
	return result


static func _cell_array(value: Array) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for item in value:
		_append_unique_cell(result, _cell_from_variant(item))
	return result


static func _cell_lookup(cells: Array[Vector2i]) -> Dictionary:
	var result: Dictionary = {}
	for cell in cells:
		result[_cell_key(cell)] = true
	return result


static func _append_unique_cell(cells: Array[Vector2i], cell: Vector2i) -> void:
	if cell.x < 0 or cell.y < 0:
		return
	if not cells.has(cell):
		cells.append(cell)


static func _directions() -> Array[Vector2i]:
	return [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]


static func _directions_with_zero() -> Array[Vector2i]:
	return [Vector2i.ZERO, Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]


static func _cell_key(cell: Vector2i) -> String:
	return "%d,%d" % [cell.x, cell.y]


static func _cell_from_key(key: String) -> Vector2i:
	var parts := key.split(",")
	if parts.size() != 2:
		return Vector2i(-9999, -9999)
	return Vector2i(int(parts[0]), int(parts[1]))


static func _dict_cell(cell: Vector2i) -> Dictionary:
	return { "x": cell.x, "y": cell.y }


static func _cells_to_dicts(cells: Array[Vector2i]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for cell in cells:
		result.append(_dict_cell(cell))
	return result


static func _cell_from_variant(value: Variant) -> Vector2i:
	if typeof(value) == TYPE_VECTOR2I:
		return value as Vector2i
	if typeof(value) == TYPE_DICTIONARY:
		var data: Dictionary = value as Dictionary
		return Vector2i(int(data.get("x", -9999)), int(data.get("y", -9999)))
	return Vector2i(-9999, -9999)

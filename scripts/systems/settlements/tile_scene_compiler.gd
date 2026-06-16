class_name TileSceneCompiler
extends RefCounted

const DEFAULT_TILE_SIZE := 32

var _tiles: Array[Array] = []
var _width: int = 0
var _height: int = 0
var _compiled: Dictionary = {}


func generate_location(source_data: Dictionary) -> Dictionary:
	var generator_data: Dictionary = source_data.get("generator", {}) as Dictionary
	var policy := SettlementPolicy.from_dictionary(generator_data.get("policy", {}) as Dictionary)
	if policy.seed_override < 0:
		policy.seed_override = int(generator_data.get("seed", 6301))

	var context_data: Dictionary = generator_data.get("context", {}) as Dictionary
	if context_data.is_empty():
		context_data = _default_context_data(generator_data)
	var context := SettlementContext.from_dictionary(context_data)
	var session := SettlementGenerationSession.new(policy, context)
	var session_result: Dictionary = session.run()
	return compile_session_result(source_data, session_result)


func compile_session_result(source_data: Dictionary, session_result: Dictionary) -> Dictionary:
	var context: Dictionary = session_result.get("context", {}) as Dictionary
	var map_size: Dictionary = context.get("map_size", {}) as Dictionary
	_width = int(map_size.get("width", 20))
	_height = int(map_size.get("height", 14))
	_reset_tiles()

	_compiled = _base_location(source_data, session_result)
	var blueprint: Dictionary = session_result.get("blueprint", {}) as Dictionary

	_apply_roads(blueprint)
	_apply_plots(blueprint)
	_apply_cores(blueprint)
	_apply_buildings(blueprint)
	_apply_landmarks(blueprint)
	_add_player_spawn(context)
	_compiled["tiles"] = _stringify_tiles()
	_compiled["generation_summary"] = _generation_summary(session_result)
	return _compiled.duplicate(true)


func validate_compiled_location(location_data: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var grid := LocationGrid.from_dictionary(location_data)
	if not grid.is_valid():
		errors.append("compiled LocationGrid is invalid")
		return errors
	var summary: Dictionary = location_data.get("generation_summary", {}) as Dictionary
	for key in ["road_count", "building_count"]:
		if int(summary.get(key, 0)) <= 0:
			errors.append("missing compiled layer count: %s" % key)
	var entrance_cell := _cell_from_dict(_first_entrance(location_data).get("grid_position", {}) as Dictionary)
	if not grid.can_enter(entrance_cell):
		errors.append("compiled entrance is not walkable")
	var blocked_count := (location_data.get("collision_overrides", []) as Array).size()
	if blocked_count <= 0:
		errors.append("compiled location has no collision overrides")
	return errors


func _base_location(source_data: Dictionary, session_result: Dictionary) -> Dictionary:
	var policy: Dictionary = session_result.get("policy", {}) as Dictionary
	var trace: Dictionary = session_result.get("trace", {}) as Dictionary
	var summary: Dictionary = trace.get("summary", {}) as Dictionary
	return {
		"id": str(source_data.get("id", "generated_settlement")),
		"display_name": str(source_data.get("display_name", "Generated Settlement")),
		"size": { "width": _width, "height": _height },
		"tile_size": int(source_data.get("tile_size", DEFAULT_TILE_SIZE)),
		"default_entrance": "main_entrance",
		"tiles": [],
		"terrain": _terrain_definitions(),
		"zones": [],
		"town_zones": [],
		"floor_overlays": [],
		"floor_decorations": [],
		"structures": [],
		"roofs": [],
		"entrances": [],
		"anchors": [],
		"exits": [],
		"shops": [],
		"objects": [],
		"characters": [],
		"collision_overrides": [],
		"state": {
			"danger_level": 0,
			"owner_faction": "field_neutral",
			"generation": "settlement_blueprint_v63",
			"settlement_type": str(policy.get("settlement_type", "")),
			"seed": int(policy.get("seed_override", -1)),
			"blueprint_commits": int(summary.get("committed_count", 0)),
			"proposal_count": int(summary.get("proposal_count", 0)),
			"rejected_count": int(summary.get("rejected_count", 0)),
		},
	}


func _terrain_definitions() -> Dictionary:
	return {
		"g": { "id": "grass", "label": "Grass", "walkable": true, "color": "#5fa35f" },
		"p": { "id": "path", "label": "Settlement Road", "walkable": true, "color": "#b5975d" },
		"s": { "id": "plaza", "label": "Settlement Core", "walkable": true, "color": "#8a8170" },
		"f": { "id": "field_plot", "label": "Accepted Plot", "walkable": true, "plantable": true, "color": "#6f8f4d" },
		"h": { "id": "house_floor", "label": "Building Footprint", "walkable": true, "color": "#927047" },
		"e": { "id": "exit", "label": "Entrance", "walkable": true, "color": "#c8b642" },
	}


func _apply_roads(blueprint: Dictionary) -> void:
	for road_value in (blueprint.get("roads", []) as Array):
		var road: Dictionary = road_value as Dictionary
		for cell_value in (road.get("path", []) as Array):
			var cell := _cell_from_variant(cell_value)
			_set_tile(cell, "p")
			_add_debug_overlay("road", cell, str(road.get("id", "")))


func _apply_plots(blueprint: Dictionary) -> void:
	for plot_value in (blueprint.get("plots", []) as Array):
		var plot: Dictionary = plot_value as Dictionary
		var area: Dictionary = plot.get("area", {}) as Dictionary
		for cell in _area_cells(area):
			_set_tile(cell, "f")
		_add_zone(str(plot.get("id", "")), "settlement_plot", area)


func _apply_cores(blueprint: Dictionary) -> void:
	for core_value in (blueprint.get("cores", []) as Array):
		var core: Dictionary = core_value as Dictionary
		var cell := _cell_from_variant(core.get("cell", {}))
		_paint_square(cell, 1, "s")
		_add_anchor("settlement_core", "core", cell, "down")
		_add_debug_overlay("core", cell, str(core.get("id", "")))


func _apply_buildings(blueprint: Dictionary) -> void:
	var index := 0
	for building_value in (blueprint.get("buildings", []) as Array):
		var building: Dictionary = building_value as Dictionary
		var area: Dictionary = building.get("area", {}) as Dictionary
		var bounds := _area_to_bounds(area)
		for cell in _area_cells(area):
			_set_tile(cell, "h")
			_add_collision(cell, true, true, str(building.get("id", "")))
		(_compiled.get("floor_overlays", []) as Array).append({
			"type": "foundation",
			"bounds": bounds,
			"source_blueprint_id": str(building.get("id", "")),
		})
		(_compiled.get("roofs", []) as Array).append({
			"id": "roof_%s" % str(building.get("id", index)),
			"bounds": bounds,
			"hide_bounds": {},
			"palette": "brown",
			"source_blueprint_id": str(building.get("id", "")),
		})
		_add_debug_bounds("building_debug_%d" % index, "building", bounds, str(building.get("id", "")))
		index += 1


func _apply_landmarks(blueprint: Dictionary) -> void:
	for landmark_value in (blueprint.get("landmarks", []) as Array):
		var landmark: Dictionary = landmark_value as Dictionary
		var cell := _cell_from_variant(landmark.get("cell", {}))
		(_compiled.get("structures", []) as Array).append({
			"type": "fountain" if str(landmark.get("kind", "")) == "well" else "notice_board",
			"grid_position": _dict_cell(cell),
			"blocks_movement": true,
			"blocks_sight": false,
			"source_blueprint_id": str(landmark.get("id", "")),
		})
		_add_debug_overlay("landmark", cell, str(landmark.get("id", "")))


func _add_player_spawn(context: Dictionary) -> void:
	var entrances: Array = context.get("entrances", []) as Array
	var entrance_cell := Vector2i(0, int(_height / 2))
	if not entrances.is_empty():
		entrance_cell = _cell_from_variant(entrances[0])
	_set_tile(entrance_cell, "e")
	(_compiled.get("entrances", []) as Array).append({
		"id": "main_entrance",
		"grid_position": _dict_cell(entrance_cell),
		"facing": "right",
	})
	(_compiled.get("characters", []) as Array).append({
		"id": "debug_player",
		"source": "res://data/characters/debug_player.json",
		"spawn_at_entrance": true,
		"facing": "right",
	})


func _generation_summary(session_result: Dictionary) -> Dictionary:
	var blueprint: Dictionary = session_result.get("blueprint", {}) as Dictionary
	var policy: Dictionary = session_result.get("policy", {}) as Dictionary
	return {
		"type": "settlement_blueprint_v63",
		"seed": int(policy.get("seed_override", -1)),
		"core_count": (blueprint.get("cores", []) as Array).size(),
		"road_count": (blueprint.get("roads", []) as Array).size(),
		"plot_count": (blueprint.get("plots", []) as Array).size(),
		"building_count": (blueprint.get("buildings", []) as Array).size(),
		"landmark_count": (blueprint.get("landmarks", []) as Array).size(),
		"trace_summary": ((session_result.get("trace", {}) as Dictionary).get("summary", {}) as Dictionary).duplicate(true),
		"result_signature": str((session_result.get("session_summary", {}) as Dictionary).get("result_signature", "")),
	}


func _default_context_data(generator_data: Dictionary) -> Dictionary:
	var size: Dictionary = generator_data.get("size", {}) as Dictionary
	var width := int(size.get("width", 20))
	var height := int(size.get("height", 14))
	return {
		"map_size": { "width": width, "height": height },
		"entrances": [{ "x": 0, "y": int(height / 2) }],
		"existing_obstacles": generator_data.get("existing_obstacles", []),
		"existing_water": generator_data.get("existing_water", []),
		"important_world_points": generator_data.get("important_world_points", [{ "x": width - 5, "y": int(height / 2) }]),
		"world_seed": int(generator_data.get("seed", 6301)),
	}


func _reset_tiles() -> void:
	_tiles.clear()
	for _y in range(_height):
		var row: Array = []
		for _x in range(_width):
			row.append("g")
		_tiles.append(row)


func _stringify_tiles() -> Array[String]:
	var result: Array[String] = []
	for row_value in _tiles:
		var row: Array = row_value as Array
		var text := ""
		for key in row:
			text += str(key)
		result.append(text)
	return result


func _set_tile(cell: Vector2i, key: String) -> void:
	if not _in_bounds(cell):
		return
	(_tiles[cell.y] as Array)[cell.x] = key


func _paint_square(center: Vector2i, radius: int, key: String) -> void:
	for y in range(center.y - radius, center.y + radius + 1):
		for x in range(center.x - radius, center.x + radius + 1):
			_set_tile(Vector2i(x, y), key)


func _add_zone(zone_id: String, zone_type: String, area: Dictionary) -> void:
	var bounds := _area_to_bounds(area)
	(_compiled.get("zones", []) as Array).append({
		"id": "%s_zone" % zone_id,
		"type": zone_type,
		"display_name": zone_id,
		"bounds": bounds,
	})
	(_compiled.get("town_zones", []) as Array).append({
		"id": zone_id,
		"type": zone_type,
		"bounds": bounds,
		"source": "settlement_blueprint",
	})


func _add_anchor(anchor_id: String, kind: String, cell: Vector2i, facing: String) -> void:
	(_compiled.get("anchors", []) as Array).append({
		"id": anchor_id,
		"kind": kind,
		"grid_position": _dict_cell(cell),
		"facing": facing,
	})


func _add_collision(cell: Vector2i, blocks_movement: bool, blocks_sight: bool, source_id: String) -> void:
	(_compiled.get("collision_overrides", []) as Array).append({
		"grid_position": _dict_cell(cell),
		"blocks_movement": blocks_movement,
		"blocks_sight": blocks_sight,
		"source_blueprint_id": source_id,
	})


func _add_debug_overlay(kind: String, cell: Vector2i, source_id: String) -> void:
	(_compiled.get("floor_overlays", []) as Array).append({
		"type": "marker",
		"grid_position": _dict_cell(cell),
		"presentation_layer": "debug",
		"debug_kind": kind,
		"source_blueprint_id": source_id,
	})


func _add_debug_bounds(overlay_id: String, kind: String, bounds: Dictionary, source_id: String) -> void:
	(_compiled.get("floor_overlays", []) as Array).append({
		"id": overlay_id,
		"type": "foundation",
		"bounds": bounds,
		"presentation_layer": "debug",
		"debug_kind": kind,
		"source_blueprint_id": source_id,
	})


func _area_cells(area: Dictionary) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var x0 := int(area.get("x", 0))
	var y0 := int(area.get("y", 0))
	var width := int(area.get("width", area.get("w", 0)))
	var height := int(area.get("height", area.get("h", 0)))
	for y in range(y0, y0 + height):
		for x in range(x0, x0 + width):
			result.append(Vector2i(x, y))
	return result


func _area_to_bounds(area: Dictionary) -> Dictionary:
	return {
		"x": int(area.get("x", 0)),
		"y": int(area.get("y", 0)),
		"w": int(area.get("width", area.get("w", 1))),
		"h": int(area.get("height", area.get("h", 1))),
	}


func _first_entrance(location_data: Dictionary) -> Dictionary:
	var entrances: Array = location_data.get("entrances", []) as Array
	if entrances.is_empty():
		return {}
	return entrances[0] as Dictionary


func _cell_from_variant(value: Variant) -> Vector2i:
	if typeof(value) == TYPE_VECTOR2I:
		return value as Vector2i
	if typeof(value) == TYPE_DICTIONARY:
		var data: Dictionary = value as Dictionary
		return Vector2i(int(data.get("x", -9999)), int(data.get("y", -9999)))
	return Vector2i(-9999, -9999)


func _cell_from_dict(data: Dictionary) -> Vector2i:
	return Vector2i(int(data.get("x", -9999)), int(data.get("y", -9999)))


func _dict_cell(cell: Vector2i) -> Dictionary:
	return { "x": cell.x, "y": cell.y }


func _in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < _width and cell.y < _height

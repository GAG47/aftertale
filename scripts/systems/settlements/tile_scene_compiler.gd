class_name TileSceneCompiler
extends RefCounted

const DEFAULT_TILE_SIZE := 32
const GENERATED_INTERIOR_SCENE := "res://scenes/locations/generated_basic_interior.tscn"
const RoadGraphScript := preload("res://scripts/systems/settlements/settlement_road_graph.gd")

var _tiles: Array[Array] = []
var _width: int = 0
var _height: int = 0
var _compiled: Dictionary = {}


func generate_location(source_data: Dictionary) -> Dictionary:
	var generator_data: Dictionary = source_data.get("generator", {}) as Dictionary
	var policy := SettlementPolicy.from_generator_data(generator_data)

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

	_apply_plots(blueprint)
	_apply_cores(blueprint)
	_apply_roads(blueprint)
	_apply_buildings(blueprint)
	_apply_landmarks(blueprint)
	_add_player_spawn(context)
	_apply_blueprint_anchors(blueprint)
	_apply_gameplay_hooks(blueprint, session_result)
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
	var connectivity := RoadGraphScript.analyze_compiled_location(location_data)
	var blueprint_connectivity: Dictionary = summary.get("road_connectivity", {}) as Dictionary
	if int(blueprint_connectivity.get("road_cell_count", 0)) > 0 and int(connectivity.get("road_cell_count", 0)) != int(blueprint_connectivity.get("road_cell_count", 0)):
		errors.append("compiled road tile count changed:%d!=%d" % [int(connectivity.get("road_cell_count", 0)), int(blueprint_connectivity.get("road_cell_count", 0))])
	if int(connectivity.get("road_cell_count", 0)) <= 0:
		errors.append("compiled road graph has no road cells")
	if not bool(connectivity.get("compiled_road_connected", false)):
		errors.append("compiled road graph has disconnected segments:%s" % ", ".join(_string_array(connectivity.get("disconnected_road_segment_ids", []) as Array)))
	if not bool(connectivity.get("compiled_entrance_connected", false)):
		errors.append("compiled entrance is not connected:%s" % _failure_rows_text(connectivity.get("failed_entrances", []) as Array, "cell"))
	if int(connectivity.get("core_count", 0)) > 0 and not bool(connectivity.get("compiled_core_connected", false)):
		errors.append("compiled entrance cannot reach the settlement core by road graph")
	var disconnected_plots: Array = connectivity.get("disconnected_plot_ids", []) as Array
	if not bool(connectivity.get("compiled_plot_access_connected", false)):
		errors.append("compiled plot access is not on the main road:%s" % ", ".join(_string_array(disconnected_plots)))
	var disconnected_buildings: Array = connectivity.get("disconnected_building_ids", []) as Array
	if not bool(connectivity.get("compiled_building_front_connected", false)):
		errors.append("compiled building front access is not on the main road:%s" % _failure_rows_text(connectivity.get("disconnected_building_front_access", []) as Array, "front_access_cell"))
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
			"generation": "settlement_blueprint_v64",
			"settlement_policy_id": str(policy.get("policy_id", "")),
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
		"l": { "id": "settlement_plot", "label": "Settlement Plot", "walkable": true, "color": "#68735b" },
		"u": { "id": "public_plot", "label": "Public Plot", "walkable": true, "color": "#9b8655" },
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
		var tile_key := _plot_tile_key(plot)
		for cell in _area_cells(area):
			_set_tile(cell, tile_key)
		_add_zone(str(plot.get("id", "")), _plot_zone_type(plot), area)


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
			"building_type": str(building.get("building_type", building.get("kind", ""))),
			"use_type": str(building.get("use_type", "")),
		})
		(_compiled.get("roofs", []) as Array).append({
			"id": "roof_%s" % str(building.get("id", index)),
			"bounds": bounds,
			"hide_bounds": {},
			"palette": "brown",
			"source_blueprint_id": str(building.get("id", "")),
			"asset_family": str(building.get("asset_family", "")),
			"building_type": str(building.get("building_type", building.get("kind", ""))),
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
	_add_anchor("player_spawn_anchor", "player_spawn", entrance_cell, "right")
	_add_anchor("settlement_entrance_anchor", "settlement_entrance", entrance_cell, "right")


func _generation_summary(session_result: Dictionary) -> Dictionary:
	var blueprint: Dictionary = session_result.get("blueprint", {}) as Dictionary
	var policy: Dictionary = session_result.get("policy", {}) as Dictionary
	var context: Dictionary = session_result.get("context", {}) as Dictionary
	var map_size: Dictionary = context.get("map_size", {}) as Dictionary
	var entrance_cells: Array = context.get("entrances", []) as Array
	var connectivity := RoadGraphScript.analyze_blueprint(
		blueprint,
		entrance_cells,
		Vector2i(int(map_size.get("width", 0)), int(map_size.get("height", 0)))
	)
	return {
		"type": "settlement_blueprint_v64",
		"policy_id": str(policy.get("policy_id", "")),
		"settlement_type": str(policy.get("settlement_type", "")),
		"road_style": str(policy.get("road_style", "")),
		"density": float(policy.get("density", 0.0)),
		"asset_family": _asset_family_summary(policy),
		"seed": int(policy.get("seed_override", -1)),
		"core_count": (blueprint.get("cores", []) as Array).size(),
		"road_count": (blueprint.get("roads", []) as Array).size(),
		"plot_count": (blueprint.get("plots", []) as Array).size(),
		"building_count": (blueprint.get("buildings", []) as Array).size(),
		"landmark_count": (blueprint.get("landmarks", []) as Array).size(),
		"plot_use_counts": _plot_use_counts(blueprint),
		"building_type_counts": _building_type_counts(blueprint),
		"agent_weight_summary": ((session_result.get("session_summary", {}) as Dictionary).get("agent_weight_summary", {}) as Dictionary).duplicate(true),
		"demand_ledger": ((session_result.get("session_summary", {}) as Dictionary).get("demand_ledger", {}) as Dictionary).duplicate(true),
		"required_landmarks_status": _required_landmarks_status(policy, blueprint),
		"gameplay_hooks": _gameplay_hook_summary(blueprint),
		"road_connectivity": connectivity,
		"road_segments": RoadGraphScript.road_segment_summary(blueprint),
		"plot_access": RoadGraphScript.plot_access_summary(blueprint),
		"building_access": RoadGraphScript.building_access_summary(blueprint),
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


func _plot_tile_key(plot: Dictionary) -> String:
	if str(plot.get("use", "")) == "public":
		return "u"
	return "l"


func _plot_zone_type(plot: Dictionary) -> String:
	var use := str(plot.get("use", "generic"))
	if use.is_empty():
		use = "generic"
	return "settlement_%s_plot" % use


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


func _apply_blueprint_anchors(blueprint: Dictionary) -> void:
	var seen: Dictionary = {}
	for existing_value in (_compiled.get("anchors", []) as Array):
		var existing: Dictionary = existing_value as Dictionary
		seen[str(existing.get("id", ""))] = true
	for anchor_value in (blueprint.get("interaction_anchors", []) as Array):
		var anchor: Dictionary = anchor_value as Dictionary
		var anchor_id := str(anchor.get("id", ""))
		if anchor_id.is_empty() or seen.has(anchor_id):
			continue
		var cell := _cell_from_variant(anchor.get("cell", {}))
		(_compiled.get("anchors", []) as Array).append({
			"id": anchor_id,
			"kind": str(anchor.get("kind", "")),
			"grid_position": _dict_cell(cell),
			"facing": _facing_for_anchor(str(anchor.get("kind", ""))),
			"source_blueprint_id": str(anchor.get("source_id", "")),
			"step": int(anchor.get("step", -1)),
		})
		seen[anchor_id] = true


func _apply_gameplay_hooks(blueprint: Dictionary, session_result: Dictionary) -> void:
	var npc_anchor := ""
	var npc_cell := Vector2i(-1, -1)
	var public_anchor := ""
	var generated_shop_id := ""
	var building_rows: Array = blueprint.get("buildings", []) as Array
	for building_value in building_rows:
		var building: Dictionary = building_value as Dictionary
		_add_building_interaction_object(building)
		if str(building.get("use_type", "")) == "commercial":
			generated_shop_id = _add_shop_hook_object(building)
		if npc_anchor.is_empty():
			npc_anchor = _first_non_empty([
				str(building.get("npc_work_anchor", "")),
				str(building.get("npc_home_anchor", "")),
				str(building.get("interaction_anchor", "")),
			])
			npc_cell = _cell_from_variant(building.get("entrance_cell", {}))
	for plot_value in (blueprint.get("plots", []) as Array):
		var plot: Dictionary = plot_value as Dictionary
		if str(plot.get("use", "")) != "public":
			continue
		public_anchor = str(plot.get("npc_gather_anchor", plot.get("public_anchor", "")))
		_add_public_hook_object(plot)
		if npc_anchor.is_empty():
			npc_anchor = public_anchor
			npc_cell = _area_center(plot.get("area", {}) as Dictionary)
	if not npc_anchor.is_empty() and npc_cell.x >= 0:
		_add_generated_npc(npc_anchor, npc_cell, generated_shop_id, session_result)


func _add_building_interaction_object(building: Dictionary) -> void:
	var building_id := str(building.get("id", ""))
	var template_id := str(building.get("interior_template_id", ""))
	var entrance_cell := _cell_from_variant(building.get("entrance_cell", {}))
	if building_id.is_empty() or template_id.is_empty() or entrance_cell.x < 0:
		return
	(_compiled.get("objects", []) as Array).append({
		"id": "door_%s" % building_id,
		"display_name": _building_display_name(building),
		"grid_position": _dict_cell(entrance_cell),
		"blocks_movement": true,
		"kind": "door",
		"is_inspectable": true,
		"is_usable": true,
		"facility_type": "scene_transition",
		"target_scene_path": GENERATED_INTERIOR_SCENE,
		"target_entrance_id": "entry",
		"return_entrance_id": "main_entrance",
		"interior_template_id": template_id,
		"source_blueprint_id": building_id,
		"transition_context": {
			"interior_template_id": template_id,
			"source_building_id": building_id,
			"use_type": str(building.get("use_type", "")),
		},
		"inspect_text": "Generated building entrance: %s" % template_id,
	})


func _add_shop_hook_object(building: Dictionary) -> String:
	var shop_anchor := str(building.get("shop_anchor", ""))
	if shop_anchor.is_empty():
		return ""
	var cell := _cell_from_variant(building.get("front_access_cell", {}))
	var shop_id := "generated_shop_%s" % str(building.get("id", ""))
	(_compiled.get("shops", []) as Array).append({
		"id": shop_id,
		"display_name": "Generated Shop",
		"source_blueprint_id": str(building.get("id", "")),
	})
	(_compiled.get("objects", []) as Array).append({
		"id": "%s_object" % shop_id,
		"display_name": "Generated Shop Counter",
		"grid_position": _dict_cell(cell),
		"blocks_movement": false,
		"kind": "shop",
		"is_inspectable": true,
		"is_usable": true,
		"facility_type": "shop",
		"shop_id": "field_stall",
		"vendor_character_id": "generated_settlement_npc_00",
		"source_blueprint_id": str(building.get("id", "")),
		"source_anchor_id": shop_anchor,
		"inspect_text": "A generated commercial hook bound to %s." % shop_anchor,
	})
	return shop_id


func _add_public_hook_object(plot: Dictionary) -> void:
	var anchor_id := str(plot.get("notice_anchor", plot.get("interaction_anchor", "")))
	if anchor_id.is_empty():
		return
	var cell := _area_center(plot.get("area", {}) as Dictionary)
	(_compiled.get("objects", []) as Array).append({
		"id": "notice_%s" % str(plot.get("id", "public")),
		"display_name": "Generated Notice Board",
		"grid_position": _dict_cell(cell),
		"blocks_movement": false,
		"kind": "inspectable",
		"is_inspectable": true,
		"is_usable": true,
		"facility_type": "",
		"source_blueprint_id": str(plot.get("id", "")),
		"source_anchor_id": anchor_id,
		"inspect_text": "A generated public activity hook.",
	})


func _add_generated_npc(anchor_id: String, cell: Vector2i, shop_id: String, session_result: Dictionary) -> void:
	var location_id := str(_compiled.get("id", "generated_settlement"))
	var schedule := [
		_schedule_row("generated_morning_work", "06:00", "11:59", location_id, anchor_id, cell, "work", "working at generated settlement"),
		_schedule_row("generated_afternoon_social", "12:00", "17:59", location_id, anchor_id, cell, "social", "using generated activity point"),
		_schedule_row("generated_evening_rest", "18:00", "05:59", location_id, anchor_id, cell, "idle", "resting near generated anchor"),
	]
	(_compiled.get("characters", []) as Array).append({
		"id": "generated_settlement_npc_00",
		"display_name": "Generated Settler",
		"source": "res://data/characters/debug_villager.json",
		"grid_position": _dict_cell(cell),
		"facing": "down",
		"anchor_id": anchor_id,
		"activity_type": "work",
		"activity": "working at generated settlement",
		"schedule": schedule,
		"generated_from_blueprint": true,
		"source_anchor_id": anchor_id,
		"shop_id": shop_id,
		"policy_id": str((session_result.get("policy", {}) as Dictionary).get("policy_id", "")),
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


func _area_center(area: Dictionary) -> Vector2i:
	return Vector2i(
		int(area.get("x", 0)) + int(area.get("width", area.get("w", 1))) / 2,
		int(area.get("y", 0)) + int(area.get("height", area.get("h", 1))) / 2
	)


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


func _string_array(values: Array) -> Array[String]:
	var result: Array[String] = []
	for value in values:
		result.append(str(value))
	return result


func _failure_rows_text(rows: Array, cell_key: String) -> String:
	if rows.is_empty():
		return "-"
	var result: Array[String] = []
	for row_value in rows:
		var row: Dictionary = row_value as Dictionary
		var id := str(row.get("id", ""))
		var cell: Variant = row.get(cell_key, {})
		if id.is_empty():
			result.append(str(cell))
		else:
			result.append("%s@%s" % [id, str(cell)])
	return ", ".join(result)


func _plot_use_counts(blueprint: Dictionary) -> Dictionary:
	var result := {
		"generic": 0,
		"residential": 0,
		"commercial": 0,
		"production": 0,
		"public": 0,
	}
	for plot_value in (blueprint.get("plots", []) as Array):
		var plot: Dictionary = plot_value as Dictionary
		var use := str(plot.get("use", "generic"))
		result[use] = int(result.get(use, 0)) + 1
	return result


func _building_type_counts(blueprint: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for building_value in (blueprint.get("buildings", []) as Array):
		var building: Dictionary = building_value as Dictionary
		var type := str(building.get("building_type", building.get("kind", "")))
		result[type] = int(result.get(type, 0)) + 1
	return result


func _required_landmarks_status(policy: Dictionary, blueprint: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	var landmarks: Array = blueprint.get("landmarks", []) as Array
	for landmark_value in (policy.get("required_landmarks", []) as Array):
		var landmark_id := str(landmark_value)
		result[landmark_id] = _landmark_exists(landmarks, landmark_id)
	return result


func _landmark_exists(landmarks: Array, landmark_id: String) -> bool:
	for landmark_value in landmarks:
		var landmark: Dictionary = landmark_value as Dictionary
		if str(landmark.get("kind", landmark.get("id", ""))) == landmark_id:
			return true
	return false


func _gameplay_hook_summary(blueprint: Dictionary) -> Dictionary:
	var buildings_with_interior := 0
	var shop_anchor_count := 0
	var npc_anchor_count := 0
	for building_value in (blueprint.get("buildings", []) as Array):
		var building: Dictionary = building_value as Dictionary
		if not str(building.get("interior_template_id", "")).is_empty():
			buildings_with_interior += 1
		if not str(building.get("shop_anchor", "")).is_empty():
			shop_anchor_count += 1
		if not str(building.get("npc_home_anchor", "")).is_empty() or not str(building.get("npc_work_anchor", "")).is_empty():
			npc_anchor_count += 1
	return {
		"buildings_with_interior": buildings_with_interior,
		"shop_anchor_count": shop_anchor_count,
		"npc_anchor_count": npc_anchor_count,
		"public_hook_count": _public_hook_count(blueprint),
	}


func _public_hook_count(blueprint: Dictionary) -> int:
	var count := 0
	for plot_value in (blueprint.get("plots", []) as Array):
		var plot: Dictionary = plot_value as Dictionary
		if not str(plot.get("npc_gather_anchor", "")).is_empty():
			count += 1
	return count


func _asset_family_summary(policy: Dictionary) -> String:
	var families: Array = policy.get("asset_family_preferences", []) as Array
	if families.is_empty():
		return "common"
	return str(families[0])


func _building_display_name(building: Dictionary) -> String:
	var building_type := str(building.get("building_type", building.get("kind", "building")))
	return "Generated %s" % building_type.capitalize()


func _facing_for_anchor(kind: String) -> String:
	match kind:
		"entrance", "player_spawn", "settlement_entrance":
			return "right"
		_:
			return "down"


func _first_non_empty(values: Array) -> String:
	for value in values:
		var text := str(value)
		if not text.is_empty():
			return text
	return ""


func _schedule_row(row_id: String, start: String, end: String, location_id: String, anchor_id: String, cell: Vector2i, activity_type: String, activity: String) -> Dictionary:
	return {
		"id": row_id,
		"start": start,
		"end": end,
		"location_id": location_id,
		"anchor_id": anchor_id,
		"grid_position": _dict_cell(cell),
		"facing": "down",
		"activity_type": activity_type,
		"activity": activity,
		"movement": "walk",
	}


func _in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < _width and cell.y < _height

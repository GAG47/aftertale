class_name WildLocationCompiler
extends RefCounted

const WildTerrainGeneratorScript := preload("res://scripts/systems/terrain/wild_terrain_generator.gd")

const DEFAULT_TILE_SIZE := 32


func generate_location(source_data: Dictionary, context: Dictionary = {}) -> Dictionary:
	var generator_data: Dictionary = (source_data.get("generator", {}) as Dictionary).duplicate(true)
	_apply_context_overrides(generator_data, context)
	var generator: RefCounted = WildTerrainGeneratorScript.new()
	var blueprint: RefCounted = generator.generate_blueprint(generator_data)
	var location_data := _base_location(source_data, blueprint)
	_compile_tiles(location_data, blueprint)
	_compile_elevation_presentation(location_data, blueprint)
	_compile_natural_objects(location_data, blueprint)
	_compile_entrances(location_data, blueprint)
	_compile_exits(location_data, blueprint)
	location_data["wild_terrain_blueprint"] = blueprint.to_dictionary()
	location_data["generation_summary"] = blueprint.debug_summary.duplicate(true)
	var summary: Dictionary = location_data.get("generation_summary", {}) as Dictionary
	summary["type"] = "wild_terrain"
	summary["generator"] = "WildTerrainGenerator"
	summary["compiler"] = "WildLocationCompiler"
	location_data["generation_summary"] = summary
	var state: Dictionary = location_data.get("state", {}) as Dictionary
	state["generation"] = "wild_terrain"
	state["wild_seed"] = blueprint.seed
	state["terrain_profile_id"] = blueprint.terrain_profile_id
	state["generated_size"] = { "width": blueprint.width, "height": blueprint.height }
	location_data["state"] = state
	return location_data


func validate_location(location_data: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var grid: LocationGrid = LocationGrid.from_dictionary(location_data)
	if not grid.is_valid():
		return ["compiled wild LocationGrid is invalid"]
	var default_entrance := str(location_data.get("default_entrance", ""))
	var entrance_cell := grid.get_entrance_cell(default_entrance)
	if not grid.in_bounds(entrance_cell) or not grid.is_walkable(entrance_cell):
		errors.append("default wild entrance is missing or blocked")
	if (location_data.get("wild_terrain_blueprint", {}) as Dictionary).is_empty():
		errors.append("compiled wild location is missing blueprint data")
	var summary: Dictionary = location_data.get("generation_summary", {}) as Dictionary
	if str(summary.get("type", "")) != "wild_terrain":
		errors.append("compiled wild location missing wild_terrain summary")
	for exit_value in (location_data.get("exits", []) as Array):
		var exit_data: Dictionary = exit_value as Dictionary
		var exit_cell := _cell_from_dict(exit_data.get("grid_position", {}) as Dictionary)
		if not grid.in_bounds(exit_cell) or not grid.is_walkable(exit_cell):
			errors.append("wild exit is missing or blocked: %s" % str(exit_data.get("id", "")))
	return errors


func _apply_context_overrides(generator_data: Dictionary, context: Dictionary) -> void:
	if context.is_empty():
		return
	if context.has("seed"):
		generator_data["seed"] = int(context.get("seed", generator_data.get("seed", 6201)))
	if context.has("wild_seed"):
		generator_data["seed"] = int(context.get("wild_seed", generator_data.get("seed", 6201)))
	if context.has("terrain_profile_id"):
		generator_data["terrain_profile_id"] = str(context.get("terrain_profile_id", generator_data.get("terrain_profile_id", "plain")))
	if context.has("wild_terrain_profile_id"):
		generator_data["terrain_profile_id"] = str(context.get("wild_terrain_profile_id", generator_data.get("terrain_profile_id", "plain")))
	if context.has("size"):
		generator_data["size"] = (context.get("size", {}) as Dictionary).duplicate(true)


func _base_location(source_data: Dictionary, blueprint: RefCounted) -> Dictionary:
	return {
		"id": str(source_data.get("id", "test_wild_plain")),
		"display_name": str(source_data.get("display_name", "Generated Wild Plain")),
		"size": { "width": blueprint.width, "height": blueprint.height },
		"tile_size": int(source_data.get("tile_size", DEFAULT_TILE_SIZE)),
		"default_entrance": "wild_spawn",
		"tiles": [],
		"terrain": _terrain_definitions(),
		"zones": [
			{
				"id": "generated_wild_bounds",
				"type": "wild_terrain",
				"display_name": "Generated Wild Terrain",
				"bounds": { "x": 0, "y": 0, "w": blueprint.width, "h": blueprint.height },
				"presentation_layer": "debug",
			},
		],
		"floor_overlays": [],
		"floor_decorations": [],
		"structures": [],
		"roofs": [],
		"entrances": [],
		"anchors": [],
		"exits": [],
		"shops": [],
		"objects": [],
		"characters": [
			{
				"id": "debug_player",
				"source": "res://data/characters/debug_player.json",
				"spawn_at_entrance": true,
				"facing": "right",
			},
		],
		"state": {
			"danger_level": 0,
			"owner_faction": "field_neutral",
		},
	}


func _terrain_definitions() -> Dictionary:
	return {
		"g": { "id": "grass", "label": "Grass", "walkable": true, "color": "#5fa35f" },
		"l": { "id": "lowland_grass", "label": "Lowland Grass", "walkable": true, "walk_cost": 1.2, "color": "#4f8f62" },
		"h": { "id": "highland_grass", "label": "Highland Grass", "walkable": true, "walk_cost": 1.25, "color": "#7fa65a" },
		"q": { "id": "slope_grass", "label": "Slope Grass", "walkable": true, "walk_cost": 1.7, "color": "#6f9652" },
		"d": { "id": "dirt", "label": "Dirt", "walkable": true, "color": "#8b734f" },
		"m": { "id": "mud", "label": "Mud", "walkable": true, "walk_cost": 3.0, "color": "#6a5940" },
		"v": { "id": "wet_grass", "label": "Wet Grass", "walkable": true, "walk_cost": 1.6, "color": "#4f8f62" },
		"f": { "id": "forest_floor", "label": "Forest Floor", "walkable": true, "walk_cost": 2.0, "color": "#3f6f3d" },
		"s": { "id": "stone", "label": "Stone", "walkable": true, "walk_cost": 1.8, "color": "#77776e" },
		"r": { "id": "rocky_ground", "label": "Rocky Ground", "walkable": true, "walk_cost": 2.3, "color": "#69665d" },
		"w": { "id": "shallow_water", "label": "Shallow Water", "walkable": true, "walk_cost": 4.0, "color": "#4a86ad" },
		"W": { "id": "deep_water", "label": "Deep Water", "walkable": false, "blocks_sight": false, "color": "#2f5f8f" },
		"e": { "id": "exit", "label": "Exit", "walkable": true, "color": "#c8b642" },
	}


func _compile_tiles(location_data: Dictionary, blueprint: RefCounted) -> void:
	var rows: Array[String] = []
	for y in range(blueprint.height):
		var row := ""
		for x in range(blueprint.width):
			var tile_id := str((blueprint.tile_map[y] as Array)[x])
			row += _tile_char(tile_id)
		rows.append(row)
	location_data["tiles"] = rows


func _compile_elevation_presentation(location_data: Dictionary, blueprint: RefCounted) -> void:
	if blueprint.elevation_map.is_empty() or blueprint.slope_map.is_empty():
		return

	for y in range(blueprint.height):
		for x in range(blueprint.width):
			var cell := Vector2i(x, y)
			var tile_id := str((blueprint.tile_map[y] as Array)[x])
			if tile_id == "deep_water" or tile_id == "shallow_water":
				continue
			var elevation_id := _map_string(blueprint.elevation_map, cell)
			var overlay_type := _elevation_overlay_type(elevation_id)
			if not overlay_type.is_empty():
				_add_elevation_overlay(location_data, overlay_type, cell, blueprint)
			_try_add_elevation_decoration(location_data, cell, tile_id, elevation_id, blueprint)


func _compile_natural_objects(location_data: Dictionary, blueprint: RefCounted) -> void:
	for object_value in blueprint.natural_objects:
		var object_data: Dictionary = object_value as Dictionary
		var kind := str(object_data.get("kind", ""))
		match kind:
			"tree":
				_add_structure(location_data, "tree", object_data, true, true)
			"large_rock":
				_add_structure(location_data, "large_rock", object_data, true, true)
			"ore_vein":
				_add_structure(location_data, "ore_vein", object_data, true, true)
			"herb_patch":
				_add_floor_decoration(location_data, "herb_patch", object_data)
				_add_pickup_object(location_data, object_data, "Wild Herb", "res://data/items/debug_herb.json", 1)
			"berry_bush":
				_add_floor_decoration(location_data, "berry_bush", object_data)
				_add_pickup_object(location_data, object_data, "Wild Berries", "res://data/items/debug_apple.json", 1)
			"fallen_branch":
				_add_floor_decoration(location_data, "fallen_branch", object_data)
				_add_pickup_object(location_data, object_data, "Fallen Branch", "res://data/items/debug_stick.json", 1)


func _compile_entrances(location_data: Dictionary, blueprint: RefCounted) -> void:
	var spawn_cell := Vector2i(int(blueprint.width / 2), int(blueprint.height / 2))
	if not blueprint.spawn_candidates.is_empty():
		var primary_spawn: Dictionary = blueprint.spawn_candidates[0] as Dictionary
		spawn_cell = _cell_from_dict(primary_spawn.get("grid_position", {}) as Dictionary)
	_add_entrance(location_data, "wild_spawn", spawn_cell, "right")
	_add_anchor(location_data, "wild_spawn", "spawn", spawn_cell, "right")


func _compile_exits(location_data: Dictionary, blueprint: RefCounted) -> void:
	var rows: Array = location_data.get("tiles", []) as Array
	for exit_value in blueprint.exit_candidates:
		var exit_data: Dictionary = exit_value as Dictionary
		var target_scene_path := str(exit_data.get("target_scene_path", ""))
		if target_scene_path.is_empty():
			continue
		var cell := _cell_from_dict(exit_data.get("grid_position", {}) as Dictionary)
		if not blueprint.in_bounds(cell):
			continue
		rows[cell.y] = _replace_char(rows[cell.y], cell.x, "e")
		(location_data.get("exits", []) as Array).append({
			"id": str(exit_data.get("id", "wild_exit")),
			"grid_position": _dict_cell(cell),
			"target_scene_path": target_scene_path,
			"target_entrance_id": str(exit_data.get("target_entrance_id", "")),
		})
		_add_anchor(location_data, str(exit_data.get("id", "wild_exit")), "exit", cell, str(exit_data.get("facing", "left")))
	location_data["tiles"] = rows


func _add_structure(
	location_data: Dictionary,
	structure_type: String,
	object_data: Dictionary,
	blocks_movement: bool,
	blocks_sight: bool
) -> void:
	var cell := _cell_from_dict(object_data.get("grid_position", {}) as Dictionary)
	(location_data.get("structures", []) as Array).append({
		"id": str(object_data.get("id", structure_type)),
		"type": structure_type,
		"grid_position": _dict_cell(cell),
		"blocks_movement": blocks_movement,
		"blocks_sight": blocks_sight,
		"source_layers": (object_data.get("source_layers", {}) as Dictionary).duplicate(true),
	})


func _add_floor_decoration(location_data: Dictionary, decoration_type: String, object_data: Dictionary) -> void:
	var cell := _cell_from_dict(object_data.get("grid_position", {}) as Dictionary)
	(location_data.get("floor_decorations", []) as Array).append({
		"id": str(object_data.get("id", decoration_type)),
		"type": decoration_type,
		"grid_position": _dict_cell(cell),
	})


func _add_elevation_overlay(location_data: Dictionary, overlay_type: String, cell: Vector2i, blueprint: RefCounted) -> void:
	(location_data.get("floor_overlays", []) as Array).append({
		"id": "%s_%d_%d" % [overlay_type, cell.x, cell.y],
		"type": overlay_type,
		"grid_position": _dict_cell(cell),
		"presentation_layer": "game",
		"elevation": _map_string(blueprint.elevation_map, cell),
		"landform": _map_string(blueprint.landform_map, cell),
		"height": _map_value(blueprint.height_map, cell),
		"slope": _map_value(blueprint.slope_map, cell),
		"ridge": _map_value(blueprint.ridge_map, cell),
		"drop_edges": _drop_edges_for_cell(blueprint, cell),
	})


func _try_add_elevation_decoration(location_data: Dictionary, cell: Vector2i, tile_id: String, elevation_id: String, blueprint: RefCounted) -> void:
	var roll := _cell_roll(cell, blueprint.seed, 991)
	var slope_value := _map_value(blueprint.slope_map, cell)
	var ridge_value := _map_value(blueprint.ridge_map, cell)
	if elevation_id == "ridge" and roll < 0.14:
		_add_floor_decoration(location_data, "scree", {
			"id": "ridge_scree_%d_%d" % [cell.x, cell.y],
			"grid_position": _dict_cell(cell),
		})
		return
	if elevation_id == "slope" and slope_value >= 0.09 and roll < 0.10:
		_add_floor_decoration(location_data, "scree", {
			"id": "slope_scree_%d_%d" % [cell.x, cell.y],
			"grid_position": _dict_cell(cell),
		})
		return
	if elevation_id == "highland" and ["dirt", "highland_grass"].has(tile_id) and ridge_value < 0.20 and roll < 0.04:
		_add_floor_decoration(location_data, "grass_clump", {
			"id": "highland_dry_grass_%d_%d" % [cell.x, cell.y],
			"grid_position": _dict_cell(cell),
		})


func _add_pickup_object(
	location_data: Dictionary,
	object_data: Dictionary,
	display_name: String,
	item_source: String,
	quantity: int
) -> void:
	var cell := _cell_from_dict(object_data.get("grid_position", {}) as Dictionary)
	(location_data.get("objects", []) as Array).append({
		"id": str(object_data.get("id", "wild_pickup")),
		"display_name": display_name,
		"grid_position": _dict_cell(cell),
		"blocks_movement": false,
		"kind": "drop",
		"is_inspectable": true,
		"is_pickable": true,
		"inspect_text": "A naturally sampled wild resource.",
		"item": {
			"source": item_source,
			"quantity": quantity,
		},
	})


func _add_entrance(location_data: Dictionary, entrance_id: String, cell: Vector2i, facing: String) -> void:
	(location_data.get("entrances", []) as Array).append({
		"id": entrance_id,
		"grid_position": _dict_cell(cell),
		"facing": facing,
	})


func _add_anchor(location_data: Dictionary, anchor_id: String, kind: String, cell: Vector2i, facing: String) -> void:
	(location_data.get("anchors", []) as Array).append({
		"id": anchor_id,
		"kind": kind,
		"grid_position": _dict_cell(cell),
		"facing": facing,
	})


func _tile_char(tile_id: String) -> String:
	match tile_id:
		"grass":
			return "g"
		"lowland_grass":
			return "l"
		"highland_grass":
			return "h"
		"slope_grass":
			return "q"
		"dirt":
			return "d"
		"mud":
			return "m"
		"wet_grass":
			return "v"
		"forest_floor":
			return "f"
		"stone":
			return "s"
		"rocky_ground":
			return "r"
		"shallow_water":
			return "w"
		"deep_water":
			return "W"
		_:
			return "g"


func _elevation_overlay_type(elevation_id: String) -> String:
	match elevation_id:
		"lowland":
			return "elevation_lowland"
		"highland":
			return "elevation_highland"
		"slope":
			return "elevation_slope"
		"ridge":
			return "elevation_ridge"
		_:
			return ""


func _drop_edges_for_cell(blueprint: RefCounted, cell: Vector2i) -> Array[String]:
	var result: Array[String] = []
	var height_value := _map_value(blueprint.height_map, cell)
	var threshold := 0.026
	var checks := {
		"north": Vector2i.UP,
		"south": Vector2i.DOWN,
		"west": Vector2i.LEFT,
		"east": Vector2i.RIGHT,
	}
	for edge_name in checks.keys():
		var other: Vector2i = cell + (checks[edge_name] as Vector2i)
		if not blueprint.in_bounds(other):
			continue
		if height_value - _map_value(blueprint.height_map, other) >= threshold:
			result.append(str(edge_name))
	return result


func _map_string(map_data: Array, cell: Vector2i) -> String:
	if cell.y < 0 or cell.y >= map_data.size():
		return ""
	var row: Array = map_data[cell.y] as Array
	if cell.x < 0 or cell.x >= row.size():
		return ""
	return str(row[cell.x])


func _map_value(map_data: Array, cell: Vector2i) -> float:
	if cell.y < 0 or cell.y >= map_data.size():
		return 0.0
	var row: Array = map_data[cell.y] as Array
	if cell.x < 0 or cell.x >= row.size():
		return 0.0
	return float(row[cell.x])


func _cell_roll(cell: Vector2i, seed: int, salt: int) -> float:
	var value := sin(float(cell.x) * 12.9898 + float(cell.y) * 78.233 + float(seed + salt) * 37.719) * 43758.5453123
	return value - floor(value)


func _replace_char(row: String, index: int, value: String) -> String:
	if index < 0 or index >= row.length():
		return row
	return row.substr(0, index) + value + row.substr(index + 1)


func _cell_from_dict(value: Dictionary) -> Vector2i:
	return Vector2i(int(value.get("x", -1)), int(value.get("y", -1)))


func _dict_cell(cell: Vector2i) -> Dictionary:
	return { "x": cell.x, "y": cell.y }

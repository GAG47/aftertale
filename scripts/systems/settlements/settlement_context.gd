class_name SettlementContext
extends RefCounted

var map_size: Vector2i = Vector2i(16, 12)
var terrain_grid: Array[String] = []
var existing_roads: Array[Vector2i] = []
var existing_water: Array[Vector2i] = []
var existing_obstacles: Array[Vector2i] = []
var entrances: Array[Vector2i] = []
var important_world_points: Array[Vector2i] = []
var asset_catalog: Dictionary = {}
var world_seed: int = 6101


static func from_dictionary(data: Dictionary) -> SettlementContext:
	var context := SettlementContext.new()
	var size_data: Dictionary = data.get("map_size", data.get("size", {})) as Dictionary
	context.map_size = Vector2i(
		int(size_data.get("width", context.map_size.x)),
		int(size_data.get("height", context.map_size.y))
	)
	context.terrain_grid.clear()
	for row in (data.get("terrain_grid", []) as Array):
		context.terrain_grid.append(str(row))
	context.existing_roads = _cell_array(data.get("existing_roads", []))
	context.existing_water = _cell_array(data.get("existing_water", []))
	context.existing_obstacles = _cell_array(data.get("existing_obstacles", []))
	context.entrances = _cell_array(data.get("entrances", []))
	context.important_world_points = _cell_array(data.get("important_world_points", []))
	context.asset_catalog = (data.get("asset_catalog", {}) as Dictionary).duplicate(true)
	context.world_seed = int(data.get("world_seed", context.world_seed))
	context.ensure_defaults()
	return context


func ensure_defaults() -> void:
	if map_size.x <= 0 or map_size.y <= 0:
		map_size = Vector2i(16, 12)
	if terrain_grid.is_empty():
		for _y in range(map_size.y):
			terrain_grid.append(".".repeat(map_size.x))
	if entrances.is_empty():
		entrances.append(Vector2i(0, map_size.y / 2))


func in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < map_size.x and cell.y < map_size.y


func is_obstacle(cell: Vector2i) -> bool:
	return existing_obstacles.has(cell)


func to_dictionary() -> Dictionary:
	return {
		"map_size": { "width": map_size.x, "height": map_size.y },
		"terrain_grid": terrain_grid.duplicate(),
		"existing_roads": _cells_to_dicts(existing_roads),
		"existing_water": _cells_to_dicts(existing_water),
		"existing_obstacles": _cells_to_dicts(existing_obstacles),
		"entrances": _cells_to_dicts(entrances),
		"important_world_points": _cells_to_dicts(important_world_points),
		"asset_catalog": asset_catalog.duplicate(true),
		"world_seed": world_seed,
	}


static func _cell_array(value: Variant) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for item in (value as Array):
		var data: Dictionary = item as Dictionary
		result.append(Vector2i(int(data.get("x", 0)), int(data.get("y", 0))))
	return result


static func _cells_to_dicts(cells: Array[Vector2i]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for cell in cells:
		result.append({ "x": cell.x, "y": cell.y })
	return result

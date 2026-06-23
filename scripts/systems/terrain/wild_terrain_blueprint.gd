class_name WildTerrainBlueprint
extends RefCounted

var width: int = 0
var height: int = 0
var seed: int = 0
var terrain_profile_id: String = ""
var profile: Dictionary = {}
var generation_metadata: Dictionary = {}
var height_map: Array = []
var moisture_map: Array = []
var roughness_map: Array = []
var vegetation_map: Array = []
var rock_map: Array = []
var water_map: Array = []
var elevation_map: Array = []
var slope_map: Array = []
var ridge_map: Array = []
var landform_map: Array = []
var biome_map: Array = []
var tile_map: Array = []
var blocker_map: Array = []
var walk_cost_map: Array = []
var natural_objects: Array[Dictionary] = []
var spawn_candidates: Array[Dictionary] = []
var exit_candidates: Array[Dictionary] = []
var debug_summary: Dictionary = {}


func to_dictionary() -> Dictionary:
	return {
		"width": width,
		"height": height,
		"seed": seed,
		"terrain_profile_id": terrain_profile_id,
		"profile": profile.duplicate(true),
		"generation_metadata": generation_metadata.duplicate(true),
		"height_map": height_map.duplicate(true),
		"moisture_map": moisture_map.duplicate(true),
		"roughness_map": roughness_map.duplicate(true),
		"vegetation_map": vegetation_map.duplicate(true),
		"rock_map": rock_map.duplicate(true),
		"water_map": water_map.duplicate(true),
		"elevation_map": elevation_map.duplicate(true),
		"slope_map": slope_map.duplicate(true),
		"ridge_map": ridge_map.duplicate(true),
		"landform_map": landform_map.duplicate(true),
		"biome_map": biome_map.duplicate(true),
		"tile_map": tile_map.duplicate(true),
		"blocker_map": blocker_map.duplicate(true),
		"walk_cost_map": walk_cost_map.duplicate(true),
		"natural_objects": natural_objects.duplicate(true),
		"object_candidates": natural_objects.duplicate(true),
		"spawn_candidates": spawn_candidates.duplicate(true),
		"exit_candidates": exit_candidates.duplicate(true),
		"debug_summary": debug_summary.duplicate(true),
	}


func in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < width and cell.y < height


func tile_at(cell: Vector2i) -> String:
	if not in_bounds(cell):
		return ""
	return str((tile_map[cell.y] as Array)[cell.x])


func biome_at(cell: Vector2i) -> String:
	if not in_bounds(cell):
		return ""
	return str((biome_map[cell.y] as Array)[cell.x])


func blocks_at(cell: Vector2i) -> bool:
	if not in_bounds(cell):
		return true
	return bool((blocker_map[cell.y] as Array)[cell.x])


func walk_cost_at(cell: Vector2i) -> float:
	if not in_bounds(cell):
		return INF
	return float((walk_cost_map[cell.y] as Array)[cell.x])


func fingerprint() -> String:
	var parts: Array[String] = [
		"%d" % seed,
		terrain_profile_id,
		"%dx%d" % [width, height],
	]
	for y in range(tile_map.size()):
		parts.append(",".join((tile_map[y] as Array)))
		parts.append(_bool_row_fingerprint(blocker_map[y] as Array))
	for object_value in natural_objects:
		var object_data: Dictionary = object_value as Dictionary
		var cell: Dictionary = object_data.get("grid_position", {}) as Dictionary
		parts.append("%s:%d,%d" % [
			str(object_data.get("kind", "")),
			int(cell.get("x", -1)),
			int(cell.get("y", -1)),
		])
	for spawn_value in spawn_candidates:
		var spawn: Dictionary = spawn_value as Dictionary
		var cell: Dictionary = spawn.get("grid_position", {}) as Dictionary
		parts.append("spawn:%d,%d" % [int(cell.get("x", -1)), int(cell.get("y", -1))])
	for exit_value in exit_candidates:
		var exit_data: Dictionary = exit_value as Dictionary
		var cell: Dictionary = exit_data.get("grid_position", {}) as Dictionary
		parts.append("exit:%s:%d,%d" % [
			str(exit_data.get("id", "")),
			int(cell.get("x", -1)),
			int(cell.get("y", -1)),
		])
	return "|".join(parts)


func _bool_row_fingerprint(row: Array) -> String:
	var text := ""
	for value in row:
		text += "1" if bool(value) else "0"
	return text

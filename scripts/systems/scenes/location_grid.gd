class_name LocationGrid
extends RefCounted

var location_id: String = ""
var display_name: String = ""
var width: int = 0
var height: int = 0
var tile_size: int = 32
var tiles: Array[String] = []
var terrain: Dictionary = {}
var entrances: Dictionary = {}
var exits_by_cell: Dictionary = {}
var state: Dictionary = {}
var blocking_occupants: Dictionary = {}
var objects_by_cell: Dictionary = {}
var objects_by_id: Dictionary = {}
var characters_by_cell: Dictionary = {}
var characters_by_id: Dictionary = {}


static func from_dictionary(data: Dictionary) -> LocationGrid:
	var grid := LocationGrid.new()
	grid.location_id = str(data.get("id", ""))
	grid.display_name = str(data.get("display_name", grid.location_id))

	var size: Dictionary = data.get("size", {}) as Dictionary
	grid.width = int(size.get("width", 0))
	grid.height = int(size.get("height", 0))
	grid.tile_size = int(data.get("tile_size", 32))

	var tile_rows: Array = data.get("tiles", []) as Array
	for row in tile_rows:
		grid.tiles.append(str(row))

	var terrain_data: Dictionary = data.get("terrain", {}) as Dictionary
	var state_data: Dictionary = data.get("state", {}) as Dictionary
	grid.terrain = terrain_data.duplicate(true)
	grid.state = state_data.duplicate(true)

	var entrance_rows: Array = data.get("entrances", []) as Array
	for entrance_value in entrance_rows:
		var entrance: Dictionary = entrance_value as Dictionary
		var entrance_id := str(entrance.get("id", ""))
		if entrance_id.is_empty():
			continue
		grid.entrances[entrance_id] = entrance.duplicate(true)

	var exit_rows: Array = data.get("exits", []) as Array
	for exit_value in exit_rows:
		var exit_data: Dictionary = exit_value as Dictionary
		var exit_position: Dictionary = exit_data.get("grid_position", {}) as Dictionary
		var cell := grid._cell_from_dict(exit_position)
		grid.exits_by_cell[grid.cell_key(cell)] = exit_data.duplicate(true)

	return grid


func is_valid() -> bool:
	if location_id.is_empty() or width <= 0 or height <= 0:
		return false

	if tiles.size() != height:
		return false

	for row in tiles:
		if row.length() != width:
			return false

	return true


func in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < width and cell.y < height


func terrain_key_at(cell: Vector2i) -> String:
	if not in_bounds(cell):
		return ""

	return tiles[cell.y].substr(cell.x, 1)


func terrain_at(cell: Vector2i) -> Dictionary:
	return terrain.get(terrain_key_at(cell), {})


func is_walkable(cell: Vector2i) -> bool:
	if not in_bounds(cell):
		return false

	var terrain_data: Dictionary = terrain_at(cell)
	return bool(terrain_data.get("walkable", false))


func is_occupied(cell: Vector2i) -> bool:
	return blocking_occupants.has(cell_key(cell))


func can_enter(cell: Vector2i) -> bool:
	return is_walkable(cell) and not is_occupied(cell)


func register_object(object_id: String, cell: Vector2i, object: Node, blocks_movement: bool) -> bool:
	if object_id.is_empty() or not in_bounds(cell):
		return false

	objects_by_id[object_id] = object

	var key := cell_key(cell)
	if not objects_by_cell.has(key):
		objects_by_cell[key] = []
	objects_by_cell[key].append(object)

	if blocks_movement:
		blocking_occupants[key] = "object:%s" % object_id

	return true


func unregister_object(object_id: String) -> void:
	if not objects_by_id.has(object_id):
		return

	var object_value: Variant = objects_by_id[object_id]
	objects_by_id.erase(object_id)

	for key in objects_by_cell.keys():
		var objects: Array = objects_by_cell[key] as Array
		_erase_object_value(objects, object_value)
		if objects.is_empty():
			objects_by_cell.erase(key)
			break

	for key in blocking_occupants.keys():
		if blocking_occupants[key] == "object:%s" % object_id:
			blocking_occupants.erase(key)
			break


func get_objects_at(cell: Vector2i) -> Array:
	var key: String = cell_key(cell)
	if not objects_by_cell.has(key):
		return []

	var source_objects: Array = objects_by_cell[key] as Array
	var valid_objects: Array = []
	var changed: bool = false
	for object_value in source_objects:
		if _is_valid_object_value(object_value):
			valid_objects.append(object_value)
		else:
			changed = true

	if changed:
		if valid_objects.is_empty():
			objects_by_cell.erase(key)
		else:
			objects_by_cell[key] = valid_objects

	return valid_objects


func get_primary_object_at(cell: Vector2i) -> LocationObject:
	var objects: Array = get_objects_at(cell)
	for object_value in objects:
		var object: LocationObject = _as_location_object(object_value)
		if object != null:
			return object

	return null


func get_object_by_id(object_id: String) -> LocationObject:
	if not objects_by_id.has(object_id):
		return null

	var object_value: Variant = objects_by_id[object_id]
	var object: LocationObject = _as_location_object(object_value)
	if object == null:
		objects_by_id.erase(object_id)
		_remove_blocking_occupant("object:%s" % object_id)

	return object


func register_character(character_id: String, cell: Vector2i, character: CharacterEntity, blocks_movement: bool) -> bool:
	if character_id.is_empty() or not in_bounds(cell):
		return false

	characters_by_id[character_id] = character

	var key: String = cell_key(cell)
	if not characters_by_cell.has(key):
		characters_by_cell[key] = []
	var characters: Array = characters_by_cell[key] as Array
	characters.append(character)

	if blocks_movement:
		blocking_occupants[key] = "character:%s" % character_id

	return true


func move_character(character_id: String, from_cell: Vector2i, to_cell: Vector2i, blocks_movement: bool) -> bool:
	if character_id.is_empty() or not characters_by_id.has(character_id):
		return false

	if not can_enter(to_cell):
		return false

	var character_value: Variant = characters_by_id[character_id]
	var character: CharacterEntity = _as_character(character_value)
	if character == null:
		unregister_character(character_id)
		return false

	var from_key: String = cell_key(from_cell)
	var to_key: String = cell_key(to_cell)

	if characters_by_cell.has(from_key):
		var from_characters: Array = characters_by_cell[from_key] as Array
		from_characters.erase(character)
		if from_characters.is_empty():
			characters_by_cell.erase(from_key)

	if blocking_occupants.get(from_key, "") == "character:%s" % character_id:
		blocking_occupants.erase(from_key)

	if not characters_by_cell.has(to_key):
		characters_by_cell[to_key] = []
	var to_characters: Array = characters_by_cell[to_key] as Array
	to_characters.append(character)

	if blocks_movement:
		blocking_occupants[to_key] = "character:%s" % character_id

	return true


func unregister_character(character_id: String) -> void:
	if not characters_by_id.has(character_id):
		return

	var character_value: Variant = characters_by_id[character_id]
	characters_by_id.erase(character_id)

	for key in characters_by_cell.keys():
		var characters: Array = characters_by_cell[key] as Array
		_erase_object_value(characters, character_value)
		if characters.is_empty():
			characters_by_cell.erase(key)
			break

	for key in blocking_occupants.keys():
		if blocking_occupants[key] == "character:%s" % character_id:
			blocking_occupants.erase(key)
			break


func get_character_at(cell: Vector2i) -> CharacterEntity:
	var key: String = cell_key(cell)
	if not characters_by_cell.has(key):
		return null

	var characters: Array = characters_by_cell[key] as Array
	if characters.is_empty():
		return null

	var valid_characters: Array = []
	var first_character: CharacterEntity
	for character_value in characters:
		var character: CharacterEntity = _as_character(character_value)
		if character != null:
			valid_characters.append(character)
			if first_character == null:
				first_character = character

	if valid_characters.is_empty():
		characters_by_cell.erase(key)
	else:
		characters_by_cell[key] = valid_characters

	return first_character


func get_character_by_id(character_id: String) -> CharacterEntity:
	if not characters_by_id.has(character_id):
		return null

	var character_value: Variant = characters_by_id[character_id]
	var character: CharacterEntity = _as_character(character_value)
	if character == null:
		characters_by_id.erase(character_id)
		_remove_blocking_occupant("character:%s" % character_id)

	return character


func get_exit_at(cell: Vector2i) -> Dictionary:
	return exits_by_cell.get(cell_key(cell), {}) as Dictionary


func get_entrance(entrance_id: String) -> Dictionary:
	return entrances.get(entrance_id, {}) as Dictionary


func get_entrance_cell(entrance_id: String) -> Vector2i:
	var entrance: Dictionary = entrances.get(entrance_id, {}) as Dictionary
	var entrance_position: Dictionary = entrance.get("grid_position", {}) as Dictionary
	return _cell_from_dict(entrance_position)


func grid_to_world(cell: Vector2i) -> Vector2:
	return Vector2(cell.x * tile_size + tile_size / 2.0, cell.y * tile_size + tile_size / 2.0)


func cell_key(cell: Vector2i) -> String:
	return "%d,%d" % [cell.x, cell.y]


func _cell_from_dict(value: Dictionary) -> Vector2i:
	return Vector2i(int(value.get("x", 0)), int(value.get("y", 0)))


func _as_location_object(value: Variant) -> LocationObject:
	if typeof(value) != TYPE_OBJECT or not is_instance_valid(value):
		return null

	return value as LocationObject


func _as_character(value: Variant) -> CharacterEntity:
	if typeof(value) != TYPE_OBJECT or not is_instance_valid(value):
		return null

	return value as CharacterEntity


func _is_valid_object_value(value: Variant) -> bool:
	return typeof(value) == TYPE_OBJECT and is_instance_valid(value)


func _erase_object_value(values: Array, value: Variant) -> void:
	if _is_valid_object_value(value):
		values.erase(value)
		return

	for existing_value in values.duplicate():
		if not _is_valid_object_value(existing_value):
			values.erase(existing_value)


func _remove_blocking_occupant(occupant_id: String) -> void:
	for key in blocking_occupants.keys():
		if blocking_occupants[key] == occupant_id:
			blocking_occupants.erase(key)
			return

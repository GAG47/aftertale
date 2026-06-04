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
var anchors_by_id: Dictionary = {}
var exits_by_cell: Dictionary = {}
var state: Dictionary = {}
var structure_blockers_by_cell: Dictionary = {}
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

	var anchor_rows: Array = data.get("anchors", []) as Array
	for anchor_value in anchor_rows:
		var anchor: Dictionary = anchor_value as Dictionary
		var anchor_id := str(anchor.get("id", ""))
		if anchor_id.is_empty():
			continue
		grid.anchors_by_id[anchor_id] = anchor.duplicate(true)

	var exit_rows: Array = data.get("exits", []) as Array
	for exit_value in exit_rows:
		var exit_data: Dictionary = exit_value as Dictionary
		var exit_position: Dictionary = exit_data.get("grid_position", {}) as Dictionary
		var cell := grid._cell_from_dict(exit_position)
		grid.exits_by_cell[grid.cell_key(cell)] = exit_data.duplicate(true)

	grid._load_structure_blockers(data)
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
	if not bool(terrain_data.get("walkable", false)):
		return false

	var structure_blocker: Dictionary = structure_blockers_by_cell.get(cell_key(cell), {}) as Dictionary
	if bool(structure_blocker.get("blocks_movement", false)):
		return false

	return true


func is_occupied(cell: Vector2i) -> bool:
	return blocking_occupants.has(cell_key(cell))


func can_enter(cell: Vector2i) -> bool:
	return is_walkable(cell) and not is_occupied(cell)


func blocks_line_of_sight(cell: Vector2i, ignore_blocking_occupant: bool = false) -> bool:
	if not in_bounds(cell):
		return true

	var terrain_data: Dictionary = terrain_at(cell)
	if bool(terrain_data.get("blocks_sight", not bool(terrain_data.get("walkable", false)))):
		return true

	var structure_blocker: Dictionary = structure_blockers_by_cell.get(cell_key(cell), {}) as Dictionary
	if bool(structure_blocker.get("blocks_sight", false)):
		return true

	if not ignore_blocking_occupant and blocking_occupants.has(cell_key(cell)):
		return true

	return false


func has_line_of_sight(from_cell: Vector2i, to_cell: Vector2i) -> bool:
	if not in_bounds(from_cell) or not in_bounds(to_cell):
		return false
	if from_cell == to_cell:
		return true

	var cells: Array[Vector2i] = _line_cells(from_cell, to_cell)
	for index in range(cells.size()):
		var cell: Vector2i = cells[index]
		if cell == from_cell:
			continue

		var is_target_cell: bool = cell == to_cell
		if blocks_line_of_sight(cell, is_target_cell):
			return false

	return true


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


func get_anchor(anchor_id: String) -> Dictionary:
	return anchors_by_id.get(anchor_id, {}) as Dictionary


func resolve_anchor_cell(anchor_id: String) -> Vector2i:
	var anchor: Dictionary = get_anchor(anchor_id)
	if anchor.is_empty():
		return Vector2i(-1, -1)

	return _cell_from_dict(anchor.get("grid_position", {}) as Dictionary)


func get_entrance_cell(entrance_id: String) -> Vector2i:
	var entrance: Dictionary = entrances.get(entrance_id, {}) as Dictionary
	var entrance_position: Dictionary = entrance.get("grid_position", {}) as Dictionary
	return _cell_from_dict(entrance_position)


func grid_to_world(cell: Vector2i) -> Vector2:
	return Vector2(cell.x * tile_size + tile_size / 2.0, cell.y * tile_size + tile_size / 2.0)


func cell_key(cell: Vector2i) -> String:
	return "%d,%d" % [cell.x, cell.y]


func _load_structure_blockers(data: Dictionary) -> void:
	var structure_rows: Array = data.get("structures", []) as Array
	for structure_value in structure_rows:
		var structure: Dictionary = structure_value as Dictionary
		_register_structure_collision(structure)

	var override_rows: Array = data.get("collision_overrides", []) as Array
	for override_value in override_rows:
		var override_data: Dictionary = override_value as Dictionary
		var cell := Vector2i(int(override_data.get("x", 0)), int(override_data.get("y", 0)))
		if override_data.has("grid_position"):
			cell = _cell_from_dict(override_data.get("grid_position", {}) as Dictionary)
		_set_structure_blocker(
			cell,
			bool(override_data.get("blocks", override_data.get("blocks_movement", true))),
			bool(override_data.get("blocks_sight", override_data.get("blocks", true)))
		)


func _register_structure_collision(structure: Dictionary) -> void:
	var blocks_movement: bool = bool(structure.get("blocks_movement", false))
	var blocks_sight: bool = bool(structure.get("blocks_sight", blocks_movement))
	if not blocks_movement and not blocks_sight:
		return

	var cells: Array[Vector2i] = _structure_cells(structure)
	for cell in cells:
		_set_structure_blocker(cell, blocks_movement, blocks_sight)


func _structure_cells(structure: Dictionary) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if str(structure.get("type", "")) == "wall_ring":
		var bounds: Dictionary = structure.get("bounds", {}) as Dictionary
		var x: int = int(bounds.get("x", 0))
		var y: int = int(bounds.get("y", 0))
		var w: int = int(bounds.get("w", 0))
		var h: int = int(bounds.get("h", 0))
		for yy in range(y, y + h):
			for xx in range(x, x + w):
				var cell := Vector2i(xx, yy)
				if not _is_ring_edge(xx, yy, x, y, w, h):
					continue
				if _structure_excludes_cell(structure, cell):
					continue
				result.append(cell)
		return result

	var explicit_cells: Array = structure.get("cells", []) as Array
	for cell_value in explicit_cells:
		var cell_data: Dictionary = cell_value as Dictionary
		result.append(_cell_from_dict(cell_data))

	if not explicit_cells.is_empty():
		return result

	var position_data: Dictionary = structure.get("grid_position", {}) as Dictionary
	var size_data: Dictionary = structure.get("grid_size", {}) as Dictionary
	var origin := _cell_from_dict(position_data)
	var w: int = max(1, int(size_data.get("w", 1)))
	var h: int = max(1, int(size_data.get("h", 1)))
	for y in range(origin.y, origin.y + h):
		for x in range(origin.x, origin.x + w):
			result.append(Vector2i(x, y))

	return result


func _is_ring_edge(xx: int, yy: int, x: int, y: int, w: int, h: int) -> bool:
	return xx == x or xx == x + w - 1 or yy == y or yy == y + h - 1


func _structure_excludes_cell(structure: Dictionary, cell: Vector2i) -> bool:
	var excluded_rows: Array = structure.get("exclude_cells", []) as Array
	for excluded_value in excluded_rows:
		var excluded: Dictionary = excluded_value as Dictionary
		if _cell_from_dict(excluded) == cell:
			return true
	return false


func _set_structure_blocker(cell: Vector2i, blocks_movement: bool, blocks_sight: bool) -> void:
	if not in_bounds(cell):
		return

	var key := cell_key(cell)
	if not blocks_movement and not blocks_sight:
		structure_blockers_by_cell.erase(key)
		return

	structure_blockers_by_cell[key] = {
		"blocks_movement": blocks_movement,
		"blocks_sight": blocks_sight,
	}


func _line_cells(from_cell: Vector2i, to_cell: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var x0: int = from_cell.x
	var y0: int = from_cell.y
	var x1: int = to_cell.x
	var y1: int = to_cell.y
	var dx: int = absi(x1 - x0)
	var dy: int = absi(y1 - y0)
	var sx: int = 1 if x0 < x1 else -1
	var sy: int = 1 if y0 < y1 else -1
	var error: int = dx - dy

	while true:
		result.append(Vector2i(x0, y0))
		if x0 == x1 and y0 == y1:
			break

		var doubled_error: int = error * 2
		if doubled_error > -dy:
			error -= dy
			x0 += sx
		if doubled_error < dx:
			error += dx
			y0 += sy

	return result


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

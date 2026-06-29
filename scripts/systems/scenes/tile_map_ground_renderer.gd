class_name TileMapGroundRenderer
extends TileMapLayer

const DEFAULT_MAPPING_PATH := "res://data/rendering/terrain_tile_map.json"

var mapping_path: String = DEFAULT_MAPPING_PATH
var grid: LocationGrid

var _terrain_tiles: Dictionary = {}
var _mapping_loaded: bool = false
var _ready: bool = false
var _mapped_cell_count: int = 0
var _unknown_terrain_ids: Dictionary = {}
var _full_rebuild_count: int = 0
var _single_cell_update_count: int = 0
var _debug_renderer_active: bool = false
var _last_error: String = ""
var _tile_size: int = 0
var _mapping_tile_size: int = 0


func configure(new_mapping_path: String = DEFAULT_MAPPING_PATH) -> bool:
	mapping_path = new_mapping_path
	_mapping_loaded = false
	_terrain_tiles.clear()
	_ready = false
	_last_error = ""
	return _load_mapping()


func rebuild_from_grid(location_grid: LocationGrid) -> bool:
	_ready = false
	grid = location_grid
	_mapped_cell_count = 0
	_unknown_terrain_ids.clear()
	_last_error = ""
	super.clear()

	if grid == null or not grid.is_valid():
		_last_error = "TileMapGroundRenderer requires a valid LocationGrid."
		push_error(_last_error)
		return false

	if not _mapping_loaded and not _load_mapping():
		return false

	if not _build_tile_set_for_grid(grid):
		return false

	for y in range(grid.height):
		for x in range(grid.width):
			var cell := Vector2i(x, y)
			var terrain_id := _terrain_id_at(cell)
			if terrain_id.is_empty():
				_record_unknown_terrain(cell, terrain_id)
				continue
			if not _paint_cell(cell, terrain_id):
				_record_unknown_terrain(cell, terrain_id)
				continue
			_mapped_cell_count += 1

	if not _unknown_terrain_ids.is_empty():
		_last_error = "TileMapGroundRenderer has unmapped terrain ids: %s" % str(_unknown_terrain_ids.keys())
		push_warning(_last_error)
		super.clear()
		_mapped_cell_count = 0
		return false

	_full_rebuild_count += 1
	_ready = true
	return true


func set_cell_terrain(cell: Vector2i, terrain_id: String) -> bool:
	_last_error = ""
	if grid == null or not grid.is_valid():
		_last_error = "TileMapGroundRenderer cannot update a cell without a valid LocationGrid."
		push_error(_last_error)
		return false
	if terrain_id.is_empty():
		_last_error = "TileMapGroundRenderer received an empty terrain_id."
		push_error(_last_error)
		return false
	if not grid.in_bounds(cell):
		_last_error = "TileMapGroundRenderer cell is out of bounds: %s" % str(cell)
		push_error(_last_error)
		return false
	if not _terrain_tiles.has(terrain_id):
		_last_error = "TileMapGroundRenderer cannot map terrain_id: %s" % terrain_id
		push_error(_last_error)
		return false
	if not grid.set_terrain_id_at(cell, terrain_id):
		_last_error = "LocationGrid cannot set terrain_id at %s: %s" % [str(cell), terrain_id]
		push_error(_last_error)
		return false

	if not _paint_cell(cell, terrain_id):
		return false
	_single_cell_update_count += 1
	return true


func clear_renderer_state() -> void:
	super.clear()
	grid = null
	_ready = false
	_mapped_cell_count = 0
	_unknown_terrain_ids.clear()
	_last_error = ""


func is_ready() -> bool:
	return _ready


func set_debug_renderer_active(value: bool) -> void:
	_debug_renderer_active = value


func get_render_summary() -> Dictionary:
	var width := grid.width if grid != null else 0
	var height := grid.height if grid != null else 0
	return {
		"renderer": "TileMapLayer",
		"mapping_path": mapping_path,
		"width": width,
		"height": height,
		"cell_count": width * height,
		"mapped_cell_count": _mapped_cell_count,
		"unknown_terrain_count": _unknown_terrain_ids.size(),
		"unknown_terrain_ids": _unknown_terrain_ids.keys(),
		"full_rebuild_count": _full_rebuild_count,
		"single_cell_update_count": _single_cell_update_count,
		"is_debug_renderer_active": _debug_renderer_active,
		"is_ready": _ready,
		"last_error": _last_error,
	}


func _load_mapping() -> bool:
	_terrain_tiles.clear()
	_last_error = ""
	var resolved_path := mapping_path
	if resolved_path.is_empty():
		_last_error = "TileMapGroundRenderer mapping_path is empty."
		push_error(_last_error)
		return false
	if not FileAccess.file_exists(resolved_path):
		_last_error = "TileMapGroundRenderer mapping file is missing: %s" % resolved_path
		push_error(_last_error)
		return false

	var file := FileAccess.open(resolved_path, FileAccess.READ)
	if file == null:
		_last_error = "TileMapGroundRenderer could not open mapping file: %s" % resolved_path
		push_error(_last_error)
		return false

	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		_last_error = "TileMapGroundRenderer mapping file is not a JSON object: %s" % resolved_path
		push_error(_last_error)
		return false

	var data: Dictionary = parsed as Dictionary
	_mapping_tile_size = int(data.get("tile_size", 0))
	if _mapping_tile_size <= 0:
		_last_error = "TileMapGroundRenderer mapping file has invalid tile_size: %s" % resolved_path
		push_error(_last_error)
		return false
	var terrains: Dictionary = data.get("terrains", {}) as Dictionary
	if terrains.is_empty():
		_last_error = "TileMapGroundRenderer mapping file has no terrains: %s" % resolved_path
		push_error(_last_error)
		return false

	for terrain_id_value in terrains.keys():
		var terrain_id := str(terrain_id_value)
		var row: Dictionary = terrains.get(terrain_id_value, {}) as Dictionary
		if terrain_id.is_empty():
			_last_error = "TileMapGroundRenderer mapping contains an empty terrain id."
			push_error(_last_error)
			return false
		if not row.has("source_id") or not row.has("atlas"):
			_last_error = "TileMapGroundRenderer mapping row missing source_id or atlas: %s" % terrain_id
			push_error(_last_error)
			return false
		var atlas_array: Array = row.get("atlas", []) as Array
		if atlas_array.size() < 2:
			_last_error = "TileMapGroundRenderer mapping atlas must have x and y: %s" % terrain_id
			push_error(_last_error)
			return false
		_terrain_tiles[terrain_id] = {
			"source_id": int(row.get("source_id", 0)),
			"atlas": Vector2i(int(atlas_array[0]), int(atlas_array[1])),
			"alternative": int(row.get("alternative", 0)),
			"color": str(row.get("color", "#ff00ff")),
		}

	_mapping_loaded = true
	return true


func _build_tile_set_for_grid(location_grid: LocationGrid) -> bool:
	if _mapping_tile_size != location_grid.tile_size:
		_last_error = "TileMapGroundRenderer tile_size mismatch: mapping=%d grid=%d" % [_mapping_tile_size, location_grid.tile_size]
		push_error(_last_error)
		return false

	var source_bounds: Dictionary = {}
	for tile_value in _terrain_tiles.values():
		var tile: Dictionary = tile_value as Dictionary
		var source_id := int(tile.get("source_id", 0))
		var atlas: Vector2i = tile.get("atlas", Vector2i.ZERO) as Vector2i
		var bounds: Vector2i = source_bounds.get(source_id, Vector2i.ZERO) as Vector2i
		bounds.x = maxi(bounds.x, atlas.x + 1)
		bounds.y = maxi(bounds.y, atlas.y + 1)
		source_bounds[source_id] = bounds

	var new_tile_set := TileSet.new()
	new_tile_set.tile_size = Vector2i(location_grid.tile_size, location_grid.tile_size)
	_tile_size = location_grid.tile_size

	for source_id_value in source_bounds.keys():
		var source_id := int(source_id_value)
		var bounds: Vector2i = source_bounds.get(source_id_value, Vector2i.ONE) as Vector2i
		var image := Image.create(bounds.x * _tile_size, bounds.y * _tile_size, false, Image.FORMAT_RGBA8)
		image.fill(Color(0, 0, 0, 0))
		for terrain_id_value in _terrain_tiles.keys():
			var terrain_id := str(terrain_id_value)
			var tile: Dictionary = _terrain_tiles.get(terrain_id, {}) as Dictionary
			if int(tile.get("source_id", -1)) != source_id:
				continue
			_fill_atlas_tile(image, tile.get("atlas", Vector2i.ZERO) as Vector2i, Color.html(str(tile.get("color", "#ff00ff"))))
		var texture := ImageTexture.create_from_image(image)
		var atlas_source := TileSetAtlasSource.new()
		atlas_source.texture = texture
		atlas_source.texture_region_size = Vector2i(_tile_size, _tile_size)
		for terrain_id_value in _terrain_tiles.keys():
			var terrain_id := str(terrain_id_value)
			var tile: Dictionary = _terrain_tiles.get(terrain_id, {}) as Dictionary
			if int(tile.get("source_id", -1)) != source_id:
				continue
			atlas_source.create_tile(tile.get("atlas", Vector2i.ZERO) as Vector2i)
		new_tile_set.add_source(atlas_source, source_id)

	tile_set = new_tile_set
	return true


func _fill_atlas_tile(image: Image, atlas: Vector2i, color: Color) -> void:
	var origin := Vector2i(atlas.x * _tile_size, atlas.y * _tile_size)
	var border := Color(color.r * 0.72, color.g * 0.72, color.b * 0.72, color.a)
	var highlight := Color(minf(color.r * 1.14, 1.0), minf(color.g * 1.14, 1.0), minf(color.b * 1.14, 1.0), color.a)
	for y in range(_tile_size):
		for x in range(_tile_size):
			var draw_color := color
			if x == 0 or y == 0 or x == _tile_size - 1 or y == _tile_size - 1:
				draw_color = border
			elif (x + y) % 11 == 0:
				draw_color = highlight
			image.set_pixel(origin.x + x, origin.y + y, draw_color)


func _paint_cell(cell: Vector2i, terrain_id: String) -> bool:
	var tile: Dictionary = _terrain_tiles.get(terrain_id, {}) as Dictionary
	if tile.is_empty():
		return false
	set_cell(
		cell,
		int(tile.get("source_id", 0)),
		tile.get("atlas", Vector2i.ZERO) as Vector2i,
		int(tile.get("alternative", 0))
	)
	return true


func _terrain_id_at(cell: Vector2i) -> String:
	var terrain_data: Dictionary = grid.terrain_at(cell)
	return str(terrain_data.get("id", ""))


func _record_unknown_terrain(cell: Vector2i, terrain_id: String) -> void:
	var resolved_id := terrain_id
	if resolved_id.is_empty():
		resolved_id = "<empty:%s>" % str(cell)
	_unknown_terrain_ids[resolved_id] = int(_unknown_terrain_ids.get(resolved_id, 0)) + 1

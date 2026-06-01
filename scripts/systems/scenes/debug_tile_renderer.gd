class_name DebugTileRenderer
extends Node2D

var grid: LocationGrid
var grid_line_color: Color = Color(0.12, 0.16, 0.12, 0.18)
var tile_inner_line_color: Color = Color(1.0, 1.0, 1.0, 0.06)


func configure(location_grid: LocationGrid) -> void:
	grid = location_grid
	queue_redraw()


func _draw() -> void:
	if grid == null or not grid.is_valid():
		return

	for y in range(grid.height):
		for x in range(grid.width):
			var cell := Vector2i(x, y)
			var terrain_data: Dictionary = grid.terrain_at(cell)
			var rect := Rect2(Vector2(x * grid.tile_size, y * grid.tile_size), Vector2(grid.tile_size, grid.tile_size))
			_draw_tile(cell, terrain_data, rect)

	for exit_key in grid.exits_by_cell.keys():
		var parts: PackedStringArray = str(exit_key).split(",")
		if parts.size() != 2:
			continue
		var exit_cell := Vector2i(int(parts[0]), int(parts[1]))
		var center := grid.grid_to_world(exit_cell)
		_draw_exit_marker(center)


func _draw_tile(cell: Vector2i, terrain_data: Dictionary, rect: Rect2) -> void:
	var base_color: Color = Color.html(str(terrain_data.get("color", "#555555")))
	var terrain_id: String = str(terrain_data.get("id", ""))
	var color: Color = _soften(base_color)
	draw_rect(rect, color, true)

	match terrain_id:
		"grass":
			_draw_grass_detail(cell, rect, color)
		"path":
			_draw_path_detail(cell, rect, color)
		"water":
			_draw_water_detail(cell, rect, color)
		"field_plot":
			_draw_field_detail(cell, rect, color)
		"stone":
			_draw_stone_detail(cell, rect, color)
		"exit":
			_draw_path_detail(cell, rect, color)
		_:
			_draw_soft_noise(cell, rect, color)

	draw_rect(rect, tile_inner_line_color, false, 1.0)
	draw_rect(rect.grow(-0.5), grid_line_color, false, 1.0)


func _draw_grass_detail(cell: Vector2i, rect: Rect2, color: Color) -> void:
	_draw_soft_noise(cell, rect, color)
	var blade_color: Color = Color(0.33, 0.52, 0.30, 0.38)
	for index in range(3):
		var point: Vector2 = rect.position + Vector2(
			6.0 + float(_pattern_value(cell, index, 19) % max(1, grid.tile_size - 12)),
			8.0 + float(_pattern_value(cell, index, 31) % max(1, grid.tile_size - 14))
		)
		draw_line(point, point + Vector2(2.0, -4.0), blade_color, 1.0)


func _draw_path_detail(cell: Vector2i, rect: Rect2, color: Color) -> void:
	draw_rect(rect.grow(-3.0), Color(0.65, 0.52, 0.33, 0.16), true)
	var pebble_color: Color = Color(0.36, 0.28, 0.18, 0.20)
	for index in range(4):
		var point: Vector2 = rect.position + Vector2(
			5.0 + float(_pattern_value(cell, index, 13) % max(1, grid.tile_size - 10)),
			5.0 + float(_pattern_value(cell, index, 29) % max(1, grid.tile_size - 10))
		)
		draw_circle(point, 1.2, pebble_color)


func _draw_water_detail(cell: Vector2i, rect: Rect2, color: Color) -> void:
	draw_rect(rect.grow(-2.0), Color(0.55, 0.78, 0.95, 0.10), true)
	var wave_color: Color = Color(0.82, 0.95, 1.0, 0.34)
	for index in range(2):
		var y: float = rect.position.y + 11.0 + float(index * 9)
		var x: float = rect.position.x + 7.0 + float(_pattern_value(cell, index, 17) % 5)
		draw_arc(Vector2(x + 5.0, y), 5.0, PI * 0.08, PI * 0.92, 8, wave_color, 1.2)


func _draw_field_detail(_cell: Vector2i, rect: Rect2, _color: Color) -> void:
	var soil_color: Color = Color(0.44, 0.34, 0.22, 0.26)
	for index in range(4):
		var y: float = rect.position.y + 7.0 + float(index * 6)
		draw_line(Vector2(rect.position.x + 4.0, y), Vector2(rect.end.x - 4.0, y + 1.0), soil_color, 1.1)


func _draw_stone_detail(cell: Vector2i, rect: Rect2, color: Color) -> void:
	draw_rect(rect.grow(-3.0), Color(0.30, 0.32, 0.33, 0.18), true)
	var chip_color: Color = Color(1.0, 1.0, 1.0, 0.08)
	var point: Vector2 = rect.position + Vector2(
		8.0 + float(_pattern_value(cell, 1, 23) % max(1, grid.tile_size - 16)),
		8.0 + float(_pattern_value(cell, 2, 23) % max(1, grid.tile_size - 16))
	)
	draw_line(point, point + Vector2(7.0, -2.0), chip_color, 1.0)
	draw_line(rect.position + Vector2(4.0, 4.0), rect.end - Vector2(4.0, 4.0), Color(0.1, 0.1, 0.1, 0.08), 1.0)


func _draw_soft_noise(cell: Vector2i, rect: Rect2, color: Color) -> void:
	var tint: Color = Color(1.0, 1.0, 1.0, 0.04)
	var shade: Color = Color(0.0, 0.0, 0.0, 0.04)
	if _pattern_value(cell, 0, 7) % 2 == 0:
		draw_rect(rect.grow(-4.0), tint, true)
	else:
		draw_rect(rect.grow(-5.0), shade, true)
	draw_rect(Rect2(rect.position + Vector2(2.0, 2.0), rect.size - Vector2(4.0, 4.0)), Color(color.r, color.g, color.b, 0.08), false, 1.0)


func _draw_exit_marker(center: Vector2) -> void:
	var radius: float = float(grid.tile_size) * 0.24
	draw_circle(center + Vector2(0.0, 1.5), radius + 2.0, Color(0.0, 0.0, 0.0, 0.12))
	draw_circle(center, radius, Color(0.98, 0.86, 0.26, 0.92))
	draw_arc(center, radius, 0.0, TAU, 20, Color(0.48, 0.38, 0.08, 0.45), 1.5)
	var arrow := PackedVector2Array([
		center + Vector2(-4.0, -6.0),
		center + Vector2(6.0, 0.0),
		center + Vector2(-4.0, 6.0),
		center + Vector2(-2.0, 0.0),
	])
	draw_polygon(arrow, _solid_colors(arrow.size(), Color(0.38, 0.28, 0.08, 0.85)))


func _soften(color: Color) -> Color:
	var paper: Color = Color(0.78, 0.76, 0.68)
	return color.lerp(paper, 0.18)


func _pattern_value(cell: Vector2i, index: int, salt: int) -> int:
	return abs(cell.x * 73 + cell.y * 151 + index * 41 + salt * 97)


func _solid_colors(count: int, color: Color) -> PackedColorArray:
	var colors := PackedColorArray()
	for _index in range(count):
		colors.append(color)
	return colors

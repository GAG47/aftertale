class_name DebugTileRenderer
extends Node2D

var grid: LocationGrid
var grid_line_color: Color = Color(0.0, 0.0, 0.0, 0.35)


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
			var color: Color = Color.html(str(terrain_data.get("color", "#555555")))
			var rect := Rect2(Vector2(x * grid.tile_size, y * grid.tile_size), Vector2(grid.tile_size, grid.tile_size))
			draw_rect(rect, color, true)
			draw_rect(rect, grid_line_color, false, 1.0)

	for exit_key in grid.exits_by_cell.keys():
		var parts: PackedStringArray = str(exit_key).split(",")
		if parts.size() != 2:
			continue
		var exit_cell := Vector2i(int(parts[0]), int(parts[1]))
		var center := grid.grid_to_world(exit_cell)
		draw_circle(center, grid.tile_size * 0.22, Color(1.0, 0.9, 0.2))

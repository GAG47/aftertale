class_name DebugTileRenderer
extends Node2D

const SceneComponents := preload("res://scripts/systems/scenes/scene_component_library.gd")

var grid: LocationGrid


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
			SceneComponents.draw_ground_tile(self, grid, cell, terrain_data, rect)

	for exit_key in grid.exits_by_cell.keys():
		var parts: PackedStringArray = str(exit_key).split(",")
		if parts.size() != 2:
			continue
		var exit_cell := Vector2i(int(parts[0]), int(parts[1]))
		SceneComponents.draw_exit_marker(self, grid, grid.grid_to_world(exit_cell))

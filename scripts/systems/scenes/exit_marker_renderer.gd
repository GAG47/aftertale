class_name ExitMarkerRenderer
extends Node2D

const SceneComponents := preload("res://scripts/systems/scenes/scene_component_library.gd")

var grid: LocationGrid


func configure(location_grid: LocationGrid) -> void:
	grid = location_grid
	queue_redraw()


func _draw() -> void:
	if grid == null or not grid.is_valid():
		return

	for exit_key in grid.exits_by_cell.keys():
		var parts: PackedStringArray = str(exit_key).split(",")
		if parts.size() != 2:
			continue
		var exit_cell := Vector2i(int(parts[0]), int(parts[1]))
		SceneComponents.draw_exit_marker(self, grid, grid.grid_to_world(exit_cell))

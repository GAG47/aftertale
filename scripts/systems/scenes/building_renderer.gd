class_name BuildingRenderer
extends Node2D

const SceneComponents := preload("res://scripts/systems/scenes/scene_component_library.gd")

@export_enum("floor", "structures", "roofs", "upper", "all") var render_mode: String = "all"
@export var show_game_layers: bool = true
@export var show_debug_layers: bool = false

var grid: LocationGrid
var floor_overlays: Array[Dictionary] = []
var floor_decorations: Array[Dictionary] = []
var structures: Array[Dictionary] = []
var roofs: Array[Dictionary] = []
var zones: Array[Dictionary] = []
var active_cell: Vector2i = Vector2i(-9999, -9999)


func configure(
	location_grid: LocationGrid,
	floor_overlay_rows: Array = [],
	floor_decoration_rows: Array = [],
	structure_rows: Array = [],
	roof_rows: Array = [],
	zone_rows: Array = []
) -> void:
	grid = location_grid
	floor_overlays = _duplicate_dictionary_rows(floor_overlay_rows)
	floor_decorations = _duplicate_dictionary_rows(floor_decoration_rows)
	structures = _duplicate_dictionary_rows(structure_rows)
	roofs = _duplicate_dictionary_rows(roof_rows)
	zones = _duplicate_dictionary_rows(zone_rows)
	queue_redraw()


func set_active_cell(cell: Vector2i) -> void:
	if active_cell == cell:
		return

	active_cell = cell
	queue_redraw()


func set_debug_layers_visible(value: bool) -> void:
	if show_debug_layers == value:
		return

	show_debug_layers = value
	queue_redraw()


func _draw() -> void:
	if grid == null or not grid.is_valid():
		return

	if render_mode == "floor" or render_mode == "all":
		for zone in zones:
			SceneComponents.draw_zone_hint(self, grid, zone)

		for overlay in floor_overlays:
			if not _should_draw_entry(overlay):
				continue
			SceneComponents.draw_floor_overlay(self, grid, overlay)

		for decoration in floor_decorations:
			if not _should_draw_entry(decoration):
				continue
			SceneComponents.draw_floor_decoration(self, grid, decoration)

	if render_mode == "structures" or render_mode == "upper" or render_mode == "all":
		for structure in structures:
			if not _should_draw_entry(structure):
				continue
			SceneComponents.draw_structure(self, grid, structure)

	if render_mode == "roofs" or render_mode == "upper" or render_mode == "all":
		for roof in roofs:
			if not _should_draw_entry(roof):
				continue
			SceneComponents.draw_roof(self, grid, roof, active_cell)


func _should_draw_entry(entry: Dictionary) -> bool:
	var layer := str(entry.get("presentation_layer", "game"))
	if layer == "debug":
		return show_debug_layers
	if layer == "both":
		return show_game_layers or show_debug_layers
	return show_game_layers


func _duplicate_dictionary_rows(rows: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for row_value in rows:
		var row: Dictionary = row_value as Dictionary
		if row.is_empty():
			continue
		result.append(row.duplicate(true))
	return result

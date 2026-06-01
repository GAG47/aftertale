class_name InteractionTargetOverlay
extends Node2D

const EMPTY_CELL := Vector2i(-9999, -9999)

var grid: LocationGrid
var focus_cell: Vector2i = EMPTY_CELL
var support_cell: Vector2i = EMPTY_CELL
var focus_kind: String = ""
var pulse: float = 0.0


func configure(location_grid: LocationGrid) -> void:
	grid = location_grid
	clear_target()


func set_target(cell: Vector2i, kind: String, related_cell: Vector2i = EMPTY_CELL) -> void:
	if grid == null or not grid.in_bounds(cell):
		clear_target()
		return

	focus_cell = cell
	support_cell = related_cell
	focus_kind = kind
	visible = true
	set_process(true)
	queue_redraw()


func clear_target() -> void:
	focus_cell = EMPTY_CELL
	support_cell = EMPTY_CELL
	focus_kind = ""
	visible = false
	set_process(false)
	queue_redraw()


func _process(delta: float) -> void:
	pulse = fmod(pulse + delta * 3.2, TAU)
	queue_redraw()


func _draw() -> void:
	if grid == null or focus_cell == EMPTY_CELL or not visible:
		return

	if support_cell != EMPTY_CELL and grid.in_bounds(support_cell) and support_cell != focus_cell:
		_draw_cell(support_cell, Color(1.0, 1.0, 1.0, 0.08), Color(1.0, 1.0, 1.0, 0.30), 1.2)

	var colors: Dictionary = _colors_for_kind(focus_kind)
	var fill: Color = colors.get("fill", Color(1.0, 0.95, 0.35, 0.20))
	var outline: Color = colors.get("outline", Color(1.0, 0.88, 0.25, 0.90))
	var pulse_alpha: float = 0.06 + (sin(pulse) + 1.0) * 0.035
	fill.a = min(fill.a + pulse_alpha, 0.42)
	_draw_cell(focus_cell, fill, outline, 2.2)
	_draw_corner_marks(focus_cell, outline)


func _draw_cell(cell: Vector2i, fill_color: Color, outline_color: Color, outline_width: float) -> void:
	var margin: float = 3.0
	var rect := Rect2(
		Vector2(cell.x * grid.tile_size + margin, cell.y * grid.tile_size + margin),
		Vector2(grid.tile_size - margin * 2.0, grid.tile_size - margin * 2.0)
	)
	draw_rect(rect, fill_color, true)
	draw_rect(rect, outline_color, false, outline_width)


func _draw_corner_marks(cell: Vector2i, color: Color) -> void:
	var inset: float = 4.0
	var length: float = 7.0
	var left: float = cell.x * grid.tile_size + inset
	var top: float = cell.y * grid.tile_size + inset
	var right: float = (cell.x + 1) * grid.tile_size - inset
	var bottom: float = (cell.y + 1) * grid.tile_size - inset
	var width: float = 2.0

	draw_line(Vector2(left, top), Vector2(left + length, top), color, width)
	draw_line(Vector2(left, top), Vector2(left, top + length), color, width)
	draw_line(Vector2(right, top), Vector2(right - length, top), color, width)
	draw_line(Vector2(right, top), Vector2(right, top + length), color, width)
	draw_line(Vector2(left, bottom), Vector2(left + length, bottom), color, width)
	draw_line(Vector2(left, bottom), Vector2(left, bottom - length), color, width)
	draw_line(Vector2(right, bottom), Vector2(right - length, bottom), color, width)
	draw_line(Vector2(right, bottom), Vector2(right, bottom - length), color, width)


func _colors_for_kind(kind: String) -> Dictionary:
	match kind:
		"pickup":
			return { "fill": Color(1.0, 0.90, 0.26, 0.18), "outline": Color(1.0, 0.82, 0.18, 0.92) }
		"talk":
			return { "fill": Color(0.40, 0.72, 1.0, 0.16), "outline": Color(0.55, 0.86, 1.0, 0.92) }
		"attack":
			return { "fill": Color(1.0, 0.22, 0.18, 0.18), "outline": Color(1.0, 0.34, 0.28, 0.94) }
		"use":
			return { "fill": Color(0.40, 0.92, 1.0, 0.15), "outline": Color(0.50, 0.92, 1.0, 0.90) }
		"crop":
			return { "fill": Color(0.50, 0.85, 0.38, 0.16), "outline": Color(0.72, 0.95, 0.44, 0.90) }
		"exit":
			return { "fill": Color(1.0, 0.78, 0.24, 0.18), "outline": Color(1.0, 0.76, 0.18, 0.95) }
		_:
			return { "fill": Color(1.0, 1.0, 1.0, 0.10), "outline": Color(1.0, 1.0, 1.0, 0.55) }

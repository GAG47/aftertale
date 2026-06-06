class_name BattleGridOverlay
extends Node2D

var grid: LocationGrid
var move_cells: Array[Vector2i] = []
var attack_cells: Array[Vector2i] = []
var tile_states: Array[Dictionary] = []
var current_cell: Vector2i = Vector2i.ZERO
var hover_cell: Vector2i = Vector2i(-9999, -9999)
var hover_area_cells: Array[Vector2i] = []
var hover_kind: String = ""
var show_current_cell: bool = false


func configure(location_grid: LocationGrid) -> void:
	grid = location_grid
	queue_redraw()


func set_preview(preview: Dictionary) -> void:
	move_cells.clear()
	attack_cells.clear()
	tile_states.clear()
	show_current_cell = bool(preview.get("can_control", false))
	current_cell = preview.get("current_cell", Vector2i.ZERO) as Vector2i

	var raw_move_cells: Array = preview.get("move_cells", []) as Array
	for cell_value in raw_move_cells:
		move_cells.append(cell_value as Vector2i)

	var raw_attack_cells: Array = preview.get("attack_cells", []) as Array
	for cell_value in raw_attack_cells:
		attack_cells.append(cell_value as Vector2i)

	var raw_tile_states: Array = preview.get("tile_states", []) as Array
	for tile_state_value in raw_tile_states:
		var tile_state: Dictionary = tile_state_value as Dictionary
		if not tile_state.is_empty():
			tile_states.append(tile_state)

	visible = bool(preview.get("active", false))
	queue_redraw()


func clear_preview() -> void:
	move_cells.clear()
	attack_cells.clear()
	tile_states.clear()
	hover_cell = Vector2i(-9999, -9999)
	hover_area_cells.clear()
	hover_kind = ""
	show_current_cell = false
	visible = false
	queue_redraw()


func set_hover_cell(cell: Vector2i, kind: String, area_cells: Array = []) -> void:
	var next_area_cells: Array[Vector2i] = []
	for cell_value in area_cells:
		next_area_cells.append(cell_value as Vector2i)

	if hover_cell == cell and hover_kind == kind and _same_cells(hover_area_cells, next_area_cells):
		return

	hover_cell = cell
	hover_area_cells = next_area_cells
	hover_kind = kind
	queue_redraw()


func _draw() -> void:
	if grid == null or not visible:
		return

	for tile_state in tile_states:
		_draw_tile_state(tile_state)

	for cell in move_cells:
		_draw_cell(cell, Color(0.2, 0.65, 1.0, 0.28), Color(0.45, 0.85, 1.0, 0.7))

	for cell in attack_cells:
		_draw_cell(cell, Color(1.0, 0.18, 0.18, 0.32), Color(1.0, 0.35, 0.35, 0.85))

	if show_current_cell:
		_draw_cell(current_cell, Color(1.0, 0.95, 0.25, 0.18), Color(1.0, 0.95, 0.25, 0.95))

	if hover_kind == "attack":
		for cell in hover_area_cells:
			_draw_cell(cell, Color(1.0, 0.0, 0.0, 0.42), Color(1.0, 0.08, 0.08, 0.92), 2.0)
		_draw_cell(hover_cell, Color(1.0, 0.0, 0.0, 0.55), Color(1.0, 0.05, 0.05, 1.0), 3.0)
	elif hover_kind == "move":
		_draw_cell(hover_cell, Color(0.15, 0.9, 1.0, 0.38), Color(0.65, 1.0, 1.0, 0.95), 3.0)


func _draw_cell(cell: Vector2i, fill_color: Color, outline_color: Color, outline_width: float = 2.0) -> void:
	if grid == null or not grid.in_bounds(cell):
		return

	var margin: float = 3.0
	var size: float = float(grid.tile_size) - margin * 2.0
	var rect: Rect2 = Rect2(
		Vector2(cell.x * grid.tile_size + margin, cell.y * grid.tile_size + margin),
		Vector2(size, size)
	)
	draw_rect(rect, fill_color, true)
	draw_rect(rect, outline_color, false, outline_width)


func _draw_tile_state(tile_state: Dictionary) -> void:
	var cell: Vector2i = tile_state.get("cell", Vector2i.ZERO) as Vector2i
	var state_id: String = str(tile_state.get("state_id", tile_state.get("id", "")))
	var color: Color = _tile_state_color(state_id)
	_draw_cell(cell, Color(color.r, color.g, color.b, 0.30), Color(color.r, color.g, color.b, 0.75), 1.5)


func _tile_state_color(state_id: String) -> Color:
	match state_id:
		"burning":
			return Color(1.0, 0.28, 0.08)
		"wet":
			return Color(0.12, 0.55, 1.0)
		"frozen":
			return Color(0.62, 0.92, 1.0)
		"electrified":
			return Color(1.0, 0.90, 0.18)
		_:
			return Color(0.80, 0.72, 0.95)


func _same_cells(left: Array[Vector2i], right: Array[Vector2i]) -> bool:
	if left.size() != right.size():
		return false

	for index in range(left.size()):
		if left[index] != right[index]:
			return false

	return true

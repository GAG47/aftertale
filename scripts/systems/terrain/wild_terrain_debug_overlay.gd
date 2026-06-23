class_name WildTerrainDebugOverlay
extends Node2D

var grid: LocationGrid
var blueprint: Dictionary = {}
var debug_visible: bool = false


func configure(location_grid: LocationGrid, terrain_blueprint: Dictionary) -> void:
	grid = location_grid
	blueprint = terrain_blueprint.duplicate(true)
	visible = false
	queue_redraw()


func set_debug_layers_visible(value: bool) -> void:
	debug_visible = value
	visible = debug_visible
	queue_redraw()


func _draw() -> void:
	if not debug_visible or grid == null or blueprint.is_empty():
		return

	var height_map: Array = blueprint.get("height_map", []) as Array
	var moisture_map: Array = blueprint.get("moisture_map", []) as Array
	var vegetation_map: Array = blueprint.get("vegetation_map", []) as Array
	var rock_map: Array = blueprint.get("rock_map", []) as Array
	var water_map: Array = blueprint.get("water_map", []) as Array
	var elevation_map: Array = blueprint.get("elevation_map", []) as Array
	var slope_map: Array = blueprint.get("slope_map", []) as Array
	var ridge_map: Array = blueprint.get("ridge_map", []) as Array
	var landform_map: Array = blueprint.get("landform_map", []) as Array
	var blocker_map: Array = blueprint.get("blocker_map", []) as Array
	if height_map.is_empty() or moisture_map.is_empty() or water_map.is_empty():
		return

	for y in range(grid.height):
		for x in range(grid.width):
			var cell := Vector2i(x, y)
			var color := _debug_color_for_cell(
				_map_value(height_map, cell),
				_map_value(moisture_map, cell),
				_map_value(vegetation_map, cell),
				_map_value(rock_map, cell),
				_map_value(water_map, cell),
				_map_string(elevation_map, cell),
				_map_string(landform_map, cell),
				_map_value(slope_map, cell),
				_map_value(ridge_map, cell),
				_map_bool(blocker_map, cell)
			)
			if color.a <= 0.0:
				continue
			var rect := Rect2(Vector2(x * grid.tile_size, y * grid.tile_size), Vector2(grid.tile_size, grid.tile_size)).grow(-3.0)
			draw_rect(rect, color, true)
			if _map_bool(blocker_map, cell):
				draw_rect(rect.grow(-1.0), Color(1.0, 0.16, 0.12, 0.48), false, 1.1)

	_draw_debug_summary()


func _debug_color_for_cell(
	height_value: float,
	moisture_value: float,
	vegetation_value: float,
	rock_value: float,
	water_value: float,
	elevation_id: String,
	landform_id: String,
	slope_value: float,
	ridge_value: float,
	blocked: bool
) -> Color:
	if water_value >= 0.34 or landform_id == "water":
		return Color(0.10, 0.38, 0.95, clampf(0.14 + water_value * 0.32, 0.0, 0.48))
	match landform_id:
		"wetland":
			return Color(0.10, 0.72, 0.78, 0.24)
		"lowland":
			return Color(0.10, 0.54, 0.42, 0.22)
		"woodland":
			return Color(0.12, 0.46, 0.12, 0.24)
		"open_meadow":
			return Color(0.74, 0.86, 0.42, 0.14)
		"upland":
			return Color(0.90, 0.72, 0.28, 0.20)
		"hillside", "rocky_slope":
			return Color(0.82, 0.45, 0.16, 0.28)
		"upland_ridge", "rocky_ridge", "rocky_upland":
			return Color(0.94, 0.78, 0.25, 0.30)
	if elevation_id == "ridge" or ridge_value >= 0.36:
		return Color(0.96, 0.82, 0.30, 0.28)
	if elevation_id == "slope" or slope_value >= 0.10:
		return Color(0.82, 0.45, 0.16, 0.24)
	if elevation_id == "highland":
		return Color(0.95, 0.72, 0.28, 0.16)
	if elevation_id == "lowland":
		return Color(0.12, 0.56, 0.44, 0.16)
	if moisture_value >= 0.68:
		return Color(0.16, 0.78, 0.78, 0.20)
	if rock_value >= 0.62:
		return Color(0.72, 0.72, 0.68, 0.20)
	if vegetation_value >= 0.68:
		return Color(0.18, 0.80, 0.28, 0.16)
	if height_value >= 0.68:
		return Color(0.95, 0.72, 0.28, 0.14)
	if blocked:
		return Color(1.0, 0.10, 0.08, 0.12)
	return Color(0.0, 0.0, 0.0, 0.0)


func _draw_debug_summary() -> void:
	var summary: Dictionary = blueprint.get("debug_summary", {}) as Dictionary
	if summary.is_empty():
		return
	var font: Font = ThemeDB.fallback_font
	var font_size := 12
	var lines := PackedStringArray([
		"Wild terrain debug",
		"seed=%s profile=%s size=%sx%s" % [
			str(summary.get("seed", "")),
			str(summary.get("profile", "")),
			str((summary.get("size", {}) as Dictionary).get("width", "")),
			str((summary.get("size", {}) as Dictionary).get("height", "")),
		],
		"passable=%s water=%s wetland=%s forest=%s rock=%s" % [
			str(summary.get("passable_ratio", 0.0)),
			str(summary.get("water_ratio", 0.0)),
			str(summary.get("wetland_ratio", 0.0)),
			str(summary.get("forest_ratio", 0.0)),
			str(summary.get("rock_ratio", 0.0)),
		],
		"elevation low=%s high=%s slope=%s ridge=%s ledge=%s" % [
			str(summary.get("lowland_ratio", 0.0)),
			str(summary.get("highland_ratio", 0.0)),
			str(summary.get("slope_ratio", 0.0)),
			str(summary.get("ridge_ratio", 0.0)),
			str(summary.get("ledge_blocker_ratio", 0.0)),
		],
		"landform low=%s wet=%s wood=%s open=%s upland=%s" % [
			str(summary.get("landform_lowland_ratio", 0.0)),
			str(summary.get("landform_wetland_ratio", 0.0)),
			str(summary.get("woodland_ratio", 0.0)),
			str(summary.get("open_ground_ratio", 0.0)),
			str(summary.get("upland_landform_ratio", 0.0)),
		],
		"objects=%s" % str(summary.get("object_counts", {})),
		"colors: blue water, teal low/wet, green wood, amber high/ridge, orange slope, red blocked",
	])
	var origin := Vector2(12.0, 12.0)
	var max_width := 0.0
	for line in lines:
		max_width = maxf(max_width, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x)
	var rect := Rect2(origin - Vector2(6.0, 4.0), Vector2(max_width + 12.0, float(lines.size()) * 16.0 + 8.0))
	draw_rect(rect, Color(0.03, 0.04, 0.03, 0.66), true)
	draw_rect(rect, Color(0.80, 0.88, 0.72, 0.26), false, 1.0)
	for index in range(lines.size()):
		draw_string(font, origin + Vector2(0.0, 12.0 + float(index) * 16.0), lines[index], HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, Color(0.92, 0.96, 0.88, 0.96))


func _map_value(map_data: Array, cell: Vector2i) -> float:
	if cell.y < 0 or cell.y >= map_data.size():
		return 0.0
	var row: Array = map_data[cell.y] as Array
	if cell.x < 0 or cell.x >= row.size():
		return 0.0
	return float(row[cell.x])


func _map_string(map_data: Array, cell: Vector2i) -> String:
	if cell.y < 0 or cell.y >= map_data.size():
		return ""
	var row: Array = map_data[cell.y] as Array
	if cell.x < 0 or cell.x >= row.size():
		return ""
	return str(row[cell.x])


func _map_bool(map_data: Array, cell: Vector2i) -> bool:
	if cell.y < 0 or cell.y >= map_data.size():
		return false
	var row: Array = map_data[cell.y] as Array
	if cell.x < 0 or cell.x >= row.size():
		return false
	return bool(row[cell.x])

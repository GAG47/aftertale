class_name SceneComponentLibrary
extends RefCounted

const LINE_COLOR := Color(0.11, 0.09, 0.06, 0.52)
const TILE_LINE_COLOR := Color(1.0, 0.92, 0.72, 0.08)


static func draw_ground_tile(canvas: CanvasItem, grid: LocationGrid, cell: Vector2i, terrain_data: Dictionary, rect: Rect2) -> void:
	var terrain_id: String = str(terrain_data.get("id", ""))
	var color: Color = _soften(Color.html(str(terrain_data.get("color", "#555555"))))
	canvas.draw_rect(rect, color, true)

	match terrain_id:
		"grass":
			_draw_grass_floor(canvas, grid, cell, rect, color)
		"path":
			_draw_path_floor(canvas, grid, cell, rect, color)
		"plaza":
			_draw_plaza_floor(canvas, cell, rect)
		"wood_floor", "house_floor", "shop_floor", "tavern_floor":
			_draw_wood_floor(canvas, grid, cell, rect)
		"workshop_floor":
			_draw_workshop_floor(canvas, grid, cell, rect)
		"field_plot":
			_draw_field_floor(canvas, cell, rect)
		"training_ground":
			_draw_training_floor(canvas, grid, cell, rect, color)
		"exit":
			_draw_path_floor(canvas, grid, cell, rect, color)
		_:
			_draw_soft_noise(canvas, grid, cell, rect, color)

	canvas.draw_rect(rect, TILE_LINE_COLOR, false, 1.0)
	canvas.draw_rect(rect.grow(-0.5), Color(0.10, 0.13, 0.10, 0.18), false, 1.0)


static func draw_exit_marker(canvas: CanvasItem, grid: LocationGrid, center: Vector2) -> void:
	var radius: float = float(grid.tile_size) * 0.24
	canvas.draw_circle(center + Vector2(0.0, 1.5), radius + 2.0, Color(0.0, 0.0, 0.0, 0.12))
	canvas.draw_circle(center, radius, Color(0.98, 0.86, 0.26, 0.92))
	canvas.draw_arc(center, radius, 0.0, TAU, 20, Color(0.48, 0.38, 0.08, 0.45), 1.5)
	var arrow := PackedVector2Array([
		center + Vector2(-4.0, -6.0),
		center + Vector2(6.0, 0.0),
		center + Vector2(-4.0, 6.0),
		center + Vector2(-2.0, 0.0),
	])
	canvas.draw_polygon(arrow, _solid_colors(arrow.size(), Color(0.38, 0.28, 0.08, 0.85)))


static func draw_zone_hint(canvas: CanvasItem, grid: LocationGrid, zone: Dictionary) -> void:
	var bounds: Dictionary = zone.get("bounds", {}) as Dictionary
	if bounds.is_empty():
		return

	var rect: Rect2 = _bounds_to_rect(grid, bounds).grow(-2.0)
	var color: Color = _zone_color(str(zone.get("type", "")))
	color.a = 0.12
	canvas.draw_rect(rect, color, false, 2.0)


static func draw_floor_overlay(canvas: CanvasItem, grid: LocationGrid, overlay: Dictionary) -> void:
	var rect: Rect2 = _entry_rect(grid, overlay)
	match str(overlay.get("type", "")):
		"foundation":
			_draw_foundation(canvas, rect)
		"steps":
			_draw_steps(canvas, rect)
		_:
			_draw_marker(canvas, rect, Color(0.58, 0.54, 0.45, 0.55))


static func draw_floor_decoration(canvas: CanvasItem, grid: LocationGrid, decoration: Dictionary) -> void:
	var rect: Rect2 = _entry_rect(grid, decoration)
	match str(decoration.get("type", "")):
		"flower_patch":
			_draw_flower_patch(canvas, rect, str(decoration.get("palette", "spring")))
		"grass_clump":
			_draw_grass_clump(canvas, rect)
		"stone":
			_draw_small_stone(canvas, rect)
		"road_pebbles":
			_draw_road_pebbles(canvas, rect)
		"flower_pot":
			_draw_flower_pot(canvas, rect)
		"mailbox":
			_draw_mailbox(canvas, rect)
		"bucket":
			_draw_bucket(canvas, rect)
		"farm_tool":
			_draw_farm_tool(canvas, rect)
		_:
			_draw_marker(canvas, rect, Color(0.74, 0.68, 0.42))


static func draw_structure(canvas: CanvasItem, grid: LocationGrid, structure: Dictionary) -> void:
	var rect: Rect2 = _entry_rect(grid, structure)
	match str(structure.get("type", "")):
		"wall_ring":
			_draw_wall_ring(canvas, grid, structure)
		"wall":
			_draw_wall(canvas, rect, structure)
		"door":
			_draw_door(canvas, rect, structure)
		"window":
			_draw_window(canvas, rect)
		"sign_badge":
			_draw_sign_badge(canvas, rect, str(structure.get("label", "")))
		"fence":
			_draw_fence(canvas, rect, str(structure.get("orientation", "horizontal")))
		"workbench":
			_draw_workbench(canvas, rect)
		"anvil":
			_draw_anvil(canvas, rect)
		"tool_rack":
			_draw_tool_rack(canvas, rect)
		"material_crates":
			_draw_material_crates(canvas, rect)
		"shop_sign":
			_draw_shop_sign(canvas, rect)
		"shelf":
			_draw_shelf(canvas, rect)
		"counter":
			_draw_counter(canvas, rect)
		"goods_crate":
			_draw_goods_crate(canvas, rect)
		"table_set":
			_draw_table_set(canvas, rect)
		"barrel":
			_draw_barrel(canvas, rect)
		"stove":
			_draw_stove(canvas, rect)
		"scarecrow":
			_draw_scarecrow(canvas, rect)
		"bucket":
			_draw_bucket(canvas, rect)
		"farm_tool":
			_draw_farm_tool(canvas, rect)
		"fountain":
			_draw_fountain(canvas, rect)
		"notice_board":
			_draw_notice_board(canvas, rect)
		"bench":
			_draw_bench(canvas, rect)
		"signpost":
			_draw_signpost(canvas, rect)
		"target":
			_draw_target(canvas, rect)
		"training_dummy":
			_draw_training_dummy(canvas, rect)
		"weapon_rack":
			_draw_weapon_rack(canvas, rect)
		"wood_stump":
			_draw_wood_stump(canvas, rect)
		_:
			_draw_marker(canvas, rect, Color(0.85, 0.70, 0.36))


static func draw_roof(canvas: CanvasItem, grid: LocationGrid, roof: Dictionary, active_cell: Vector2i) -> void:
	var hide_bounds: Dictionary = roof.get("hide_bounds", roof.get("bounds", {})) as Dictionary
	if _cell_in_bounds(active_cell, hide_bounds):
		return

	var rect: Rect2 = _bounds_to_rect(grid, roof.get("bounds", {}) as Dictionary)
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return

	var palette: Dictionary = _roof_palette(str(roof.get("palette", "blue")), Color.html(str(roof.get("color", "#3f678c"))))
	_draw_tile_roof(canvas, rect, palette)


static func _draw_grass_floor(canvas: CanvasItem, grid: LocationGrid, cell: Vector2i, rect: Rect2, color: Color) -> void:
	_draw_soft_noise(canvas, grid, cell, rect, color)
	var blade_color := Color(0.30, 0.49, 0.28, 0.38)
	for index in range(3):
		var point: Vector2 = rect.position + Vector2(
			6.0 + float(_pattern_value(cell, index, 19) % max(1, grid.tile_size - 12)),
			8.0 + float(_pattern_value(cell, index, 31) % max(1, grid.tile_size - 14))
		)
		canvas.draw_line(point, point + Vector2(2.0, -4.0), blade_color, 1.0)


static func _draw_path_floor(canvas: CanvasItem, grid: LocationGrid, cell: Vector2i, rect: Rect2, color: Color) -> void:
	canvas.draw_rect(rect.grow(-3.0), Color(0.65, 0.52, 0.33, 0.16), true)
	var pebble_color := Color(0.36, 0.28, 0.18, 0.22)
	for index in range(4):
		var point: Vector2 = rect.position + Vector2(
			5.0 + float(_pattern_value(cell, index, 13) % max(1, grid.tile_size - 10)),
			5.0 + float(_pattern_value(cell, index, 29) % max(1, grid.tile_size - 10))
		)
		canvas.draw_circle(point, 1.2, pebble_color)
	canvas.draw_rect(rect.grow(-8.0), Color(1.0, 0.92, 0.68, 0.07), false, 1.0)


static func _draw_plaza_floor(canvas: CanvasItem, cell: Vector2i, rect: Rect2) -> void:
	var seam_color := Color(0.18, 0.17, 0.15, 0.20)
	canvas.draw_line(Vector2(rect.position.x + rect.size.x * 0.5, rect.position.y + 3.0), Vector2(rect.position.x + rect.size.x * 0.5, rect.end.y - 3.0), seam_color, 1.0)
	canvas.draw_line(Vector2(rect.position.x + 3.0, rect.position.y + rect.size.y * 0.5), Vector2(rect.end.x - 3.0, rect.position.y + rect.size.y * 0.5), seam_color, 1.0)
	if _pattern_value(cell, 0, 5) % 3 == 0:
		canvas.draw_circle(rect.position + Vector2(9.0, 8.0), 1.2, Color(1.0, 1.0, 1.0, 0.08))


static func _draw_wood_floor(canvas: CanvasItem, grid: LocationGrid, cell: Vector2i, rect: Rect2) -> void:
	var seam_color := Color(0.25, 0.14, 0.07, 0.24)
	var seam_offset: float = float(_pattern_value(cell, 0, 11) % 4)
	for index in range(2):
		var y: float = rect.position.y + 9.0 + float(index * 10) + seam_offset * 0.25
		canvas.draw_line(Vector2(rect.position.x + 3.0, y), Vector2(rect.end.x - 3.0, y), seam_color, 1.0)
	canvas.draw_rect(rect.grow(-4.0), Color(0.95, 0.78, 0.42, 0.05), false, 1.0)


static func _draw_workshop_floor(canvas: CanvasItem, grid: LocationGrid, cell: Vector2i, rect: Rect2) -> void:
	_draw_soft_noise(canvas, grid, cell, rect, Color(0.43, 0.39, 0.33))
	canvas.draw_line(rect.position + Vector2(5.0, 5.0), rect.end - Vector2(5.0, 5.0), Color(0.08, 0.07, 0.06, 0.12), 1.0)
	canvas.draw_circle(rect.position + Vector2(22.0, 10.0), 1.5, Color(0.12, 0.11, 0.10, 0.22))


static func _draw_field_floor(canvas: CanvasItem, cell: Vector2i, rect: Rect2) -> void:
	canvas.draw_rect(rect.grow(-2.0), Color(0.34, 0.27, 0.13, 0.22), true)
	var soil_color := Color(0.30, 0.23, 0.12, 0.30)
	for index in range(4):
		var y: float = rect.position.y + 7.0 + float(index * 6)
		canvas.draw_line(Vector2(rect.position.x + 4.0, y), Vector2(rect.end.x - 4.0, y + 1.0), soil_color, 1.1)
	if _pattern_value(cell, 2, 31) % 2 == 0:
		var sprout_color := Color(0.30, 0.62, 0.28, 0.58)
		canvas.draw_line(rect.get_center(), rect.get_center() + Vector2(-3.0, -6.0), sprout_color, 1.5)
		canvas.draw_line(rect.get_center(), rect.get_center() + Vector2(4.0, -5.0), sprout_color, 1.5)


static func _draw_training_floor(canvas: CanvasItem, grid: LocationGrid, cell: Vector2i, rect: Rect2, color: Color) -> void:
	_draw_soft_noise(canvas, grid, cell, rect, color)
	var rake_color := Color(0.34, 0.23, 0.12, 0.20)
	for index in range(3):
		var y: float = rect.position.y + 7.0 + float(index * 7)
		canvas.draw_line(Vector2(rect.position.x + 5.0, y), Vector2(rect.end.x - 5.0, y + 1.0), rake_color, 1.0)


static func _draw_soft_noise(canvas: CanvasItem, grid: LocationGrid, cell: Vector2i, rect: Rect2, color: Color) -> void:
	var tint := Color(1.0, 1.0, 1.0, 0.04)
	var shade := Color(0.0, 0.0, 0.0, 0.04)
	if grid == null or _pattern_value(cell, 0, 7) % 2 == 0:
		canvas.draw_rect(rect.grow(-4.0), tint, true)
	else:
		canvas.draw_rect(rect.grow(-5.0), shade, true)
	canvas.draw_rect(Rect2(rect.position + Vector2(2.0, 2.0), rect.size - Vector2(4.0, 4.0)), Color(color.r, color.g, color.b, 0.08), false, 1.0)


static func _draw_wall(canvas: CanvasItem, rect: Rect2, structure: Dictionary) -> void:
	var base := _wall_color_for_structure(structure)
	canvas.draw_rect(rect, base, true)
	canvas.draw_rect(rect, Color(0.56, 0.56, 0.53, 0.18), true)
	canvas.draw_rect(rect, Color(0.20, 0.20, 0.19, 0.72), false, 1.0)
	canvas.draw_line(rect.position + Vector2(4.0, 5.0), rect.end - Vector2(4.0, 6.0), Color(1.0, 1.0, 1.0, 0.08), 1.0)


static func _wall_color_for_structure(structure: Dictionary) -> Color:
	var visual: Dictionary = structure.get("visual", {}) as Dictionary
	match str(visual.get("wall_palette", "")):
		"warm_plaster":
			return Color(0.55, 0.51, 0.43, 0.96)
		"shop_plaster":
			return Color(0.48, 0.55, 0.58, 0.96)
		"workshop_stone":
			return Color(0.47, 0.45, 0.40, 0.96)
		"tavern_plaster":
			return Color(0.57, 0.48, 0.42, 0.96)
		"storage_wood":
			return Color(0.44, 0.42, 0.37, 0.96)
		"guard_stone":
			return Color(0.46, 0.48, 0.48, 0.96)
		_:
			return Color(0.47, 0.47, 0.45, 0.96)


static func _draw_wall_ring(canvas: CanvasItem, grid: LocationGrid, structure: Dictionary) -> void:
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
			var rect := Rect2(Vector2(xx * grid.tile_size, yy * grid.tile_size), Vector2(grid.tile_size, grid.tile_size))
			_draw_wall(canvas, rect, structure)


static func _draw_door(canvas: CanvasItem, rect: Rect2, _structure: Dictionary) -> void:
	_draw_wall(canvas, rect, {})
	var unit: float = min(rect.size.x, rect.size.y) / 32.0
	var origin: Vector2 = rect.position
	var center_x: float = rect.get_center().x

	var outline := Color(0.12, 0.07, 0.04, 0.96)
	var frame_dark := Color(0.27, 0.14, 0.06, 0.98)
	var frame_mid := Color(0.52, 0.30, 0.12, 0.98)
	var frame_light := Color(0.74, 0.47, 0.20, 0.88)
	var plank_dark := Color(0.30, 0.15, 0.06, 0.98)
	var plank_mid := Color(0.46, 0.24, 0.09, 0.98)
	var plank_alt := Color(0.56, 0.31, 0.12, 0.98)
	var plank_light := Color(0.82, 0.52, 0.22, 0.70)
	var metal := Color(0.45, 0.57, 0.62, 0.95)
	var metal_light := Color(0.76, 0.86, 0.88, 0.80)

	canvas.draw_rect(Rect2(Vector2(center_x - 10.0 * unit, origin.y + 7.0 * unit), Vector2(20.0 * unit, 23.0 * unit)), Color(0.0, 0.0, 0.0, 0.18), true)

	canvas.draw_rect(Rect2(Vector2(center_x - 5.0 * unit, origin.y + 4.0 * unit), Vector2(10.0 * unit, 3.0 * unit)), outline, true)
	canvas.draw_rect(Rect2(Vector2(center_x - 8.0 * unit, origin.y + 7.0 * unit), Vector2(16.0 * unit, 3.0 * unit)), outline, true)
	canvas.draw_rect(Rect2(Vector2(center_x - 10.0 * unit, origin.y + 10.0 * unit), Vector2(20.0 * unit, 20.0 * unit)), outline, true)

	canvas.draw_rect(Rect2(Vector2(center_x - 4.0 * unit, origin.y + 5.0 * unit), Vector2(8.0 * unit, 2.0 * unit)), frame_mid, true)
	canvas.draw_rect(Rect2(Vector2(center_x - 7.0 * unit, origin.y + 7.0 * unit), Vector2(14.0 * unit, 3.0 * unit)), frame_mid, true)
	canvas.draw_rect(Rect2(Vector2(center_x - 9.0 * unit, origin.y + 10.0 * unit), Vector2(18.0 * unit, 19.0 * unit)), frame_dark, true)

	canvas.draw_rect(Rect2(Vector2(center_x - 6.0 * unit, origin.y + 8.0 * unit), Vector2(12.0 * unit, 3.0 * unit)), plank_mid, true)
	canvas.draw_rect(Rect2(Vector2(center_x - 7.0 * unit, origin.y + 11.0 * unit), Vector2(14.0 * unit, 17.0 * unit)), plank_mid, true)
	canvas.draw_rect(Rect2(Vector2(center_x - 1.0 * unit, origin.y + 11.0 * unit), Vector2(5.0 * unit, 17.0 * unit)), plank_alt, true)
	canvas.draw_rect(Rect2(Vector2(center_x - 6.0 * unit, origin.y + 12.0 * unit), Vector2(2.0 * unit, 15.0 * unit)), Color(0.64, 0.36, 0.14, 0.72), true)

	for offset in [-3.0, 2.0]:
		var line_x: float = center_x + offset * unit
		canvas.draw_line(Vector2(line_x, origin.y + 11.0 * unit), Vector2(line_x, origin.y + 28.0 * unit), plank_dark, 1.0 * unit)

	canvas.draw_rect(Rect2(Vector2(center_x - 6.0 * unit, origin.y + 8.0 * unit), Vector2(12.0 * unit, 1.0 * unit)), plank_light, true)
	canvas.draw_rect(Rect2(Vector2(center_x - 8.0 * unit, origin.y + 10.0 * unit), Vector2(2.0 * unit, 18.0 * unit)), frame_light, true)
	canvas.draw_rect(Rect2(Vector2(center_x + 7.0 * unit, origin.y + 11.0 * unit), Vector2(1.0 * unit, 17.0 * unit)), Color(0.15, 0.08, 0.04, 0.42), true)
	canvas.draw_rect(Rect2(Vector2(center_x - 7.0 * unit, origin.y + 28.0 * unit), Vector2(14.0 * unit, 1.0 * unit)), Color(0.09, 0.05, 0.03, 0.64), true)

	canvas.draw_rect(Rect2(Vector2(center_x - 6.0 * unit, origin.y + 15.0 * unit), Vector2(3.0 * unit, 1.0 * unit)), Color(0.86, 0.56, 0.24, 0.34), true)
	canvas.draw_rect(Rect2(Vector2(center_x + 1.0 * unit, origin.y + 21.0 * unit), Vector2(3.0 * unit, 1.0 * unit)), Color(0.92, 0.62, 0.28, 0.28), true)
	canvas.draw_rect(Rect2(Vector2(center_x - 2.0 * unit, origin.y + 25.0 * unit), Vector2(2.0 * unit, 1.0 * unit)), Color(0.12, 0.06, 0.03, 0.34), true)

	var knob_center := Vector2(center_x + 5.0 * unit, origin.y + 18.0 * unit)
	canvas.draw_rect(Rect2(knob_center + Vector2(-2.0, -2.0) * unit, Vector2(4.0, 4.0) * unit), Color(0.12, 0.08, 0.06, 0.55), true)
	canvas.draw_circle(knob_center, 1.8 * unit, metal)
	canvas.draw_circle(knob_center + Vector2(-0.6, -0.6) * unit, 0.7 * unit, metal_light)
	canvas.draw_rect(Rect2(Vector2(center_x + 3.0 * unit, origin.y + 17.0 * unit), Vector2(2.0 * unit, 1.0 * unit)), Color(0.24, 0.30, 0.32, 0.80), true)

	for hinge_y in [12.0, 22.0]:
		canvas.draw_rect(Rect2(Vector2(center_x - 9.0 * unit, origin.y + hinge_y * unit), Vector2(3.0 * unit, 2.0 * unit)), Color(0.16, 0.10, 0.05, 0.78), true)
		canvas.draw_rect(Rect2(Vector2(center_x - 8.0 * unit, origin.y + hinge_y * unit), Vector2(1.0 * unit, 1.0 * unit)), frame_light, true)


static func _draw_window(canvas: CanvasItem, rect: Rect2) -> void:
	var window_rect := rect.grow(-8.0)
	canvas.draw_rect(window_rect, Color(0.47, 0.70, 0.86, 0.78), true)
	canvas.draw_rect(window_rect, LINE_COLOR, false, 1.0)
	canvas.draw_line(Vector2(window_rect.position.x + window_rect.size.x * 0.5, window_rect.position.y), Vector2(window_rect.position.x + window_rect.size.x * 0.5, window_rect.end.y), LINE_COLOR, 0.8)
	canvas.draw_line(Vector2(window_rect.position.x, window_rect.position.y + window_rect.size.y * 0.5), Vector2(window_rect.end.x, window_rect.position.y + window_rect.size.y * 0.5), LINE_COLOR, 0.8)


static func _draw_sign_badge(canvas: CanvasItem, rect: Rect2, label: String) -> void:
	if label.is_empty():
		return
	var sign_rect := rect.grow(-5.0)
	canvas.draw_rect(sign_rect, Color(0.39, 0.23, 0.11, 0.96), true)
	canvas.draw_rect(sign_rect, LINE_COLOR, false, 1.2)
	_draw_centered_text(canvas, sign_rect, label, 16, Color(0.96, 0.84, 0.58))


static func _draw_foundation(canvas: CanvasItem, rect: Rect2) -> void:
	canvas.draw_rect(rect.grow(-2.0), Color(0.44, 0.41, 0.35, 0.92), true)
	canvas.draw_rect(rect.grow(-2.0), LINE_COLOR, false, 1.0)
	for x in range(int(rect.position.x) + 8, int(rect.end.x), 18):
		canvas.draw_line(Vector2(x, rect.position.y + 4.0), Vector2(x, rect.end.y - 4.0), Color(0.16, 0.14, 0.12, 0.18), 1.0)


static func _draw_steps(canvas: CanvasItem, rect: Rect2) -> void:
	canvas.draw_rect(rect.grow(-3.0), Color(0.54, 0.51, 0.45, 0.94), true)
	canvas.draw_rect(rect.grow(-3.0), LINE_COLOR, false, 1.0)
	canvas.draw_line(rect.position + Vector2(5.0, rect.size.y * 0.5), rect.end - Vector2(5.0, rect.size.y * 0.5), Color(0.20, 0.18, 0.15, 0.22), 1.0)


static func _draw_fence(canvas: CanvasItem, rect: Rect2, orientation: String) -> void:
	var wood := Color(0.43, 0.27, 0.13)
	if orientation == "vertical":
		canvas.draw_line(rect.get_center() + Vector2(0.0, -13.0), rect.get_center() + Vector2(0.0, 13.0), wood, 4.0)
		canvas.draw_line(rect.get_center() + Vector2(-8.0, -8.0), rect.get_center() + Vector2(8.0, -8.0), wood, 2.0)
		canvas.draw_line(rect.get_center() + Vector2(-8.0, 8.0), rect.get_center() + Vector2(8.0, 8.0), wood, 2.0)
	else:
		canvas.draw_line(rect.get_center() + Vector2(-13.0, 0.0), rect.get_center() + Vector2(13.0, 0.0), wood, 4.0)
		canvas.draw_line(rect.get_center() + Vector2(-8.0, -8.0), rect.get_center() + Vector2(-8.0, 8.0), wood, 2.0)
		canvas.draw_line(rect.get_center() + Vector2(8.0, -8.0), rect.get_center() + Vector2(8.0, 8.0), wood, 2.0)


static func _draw_tile_roof(canvas: CanvasItem, rect: Rect2, palette: Dictionary) -> void:
	var outline: Color = palette.get("outline", LINE_COLOR)
	var shadow: Color = palette.get("shadow", Color(0.08, 0.05, 0.04, 0.50))
	var dark: Color = palette.get("dark", Color(0.12, 0.24, 0.42))
	var mid: Color = palette.get("mid", Color(0.19, 0.37, 0.62))
	var alt_mid: Color = palette.get("alt_mid", Color(0.16, 0.31, 0.52))
	var light: Color = palette.get("light", Color(0.30, 0.50, 0.74))
	var highlight: Color = palette.get("highlight", Color(0.46, 0.64, 0.85))
	var roof_line: Color = palette.get("line", Color(0.10, 0.20, 0.36))

	canvas.draw_rect(Rect2(rect.position + Vector2(2.0, 3.0), rect.size), shadow, true)
	canvas.draw_rect(rect, outline, true)
	canvas.draw_rect(rect.grow(-2.0), dark, true)
	canvas.draw_rect(Rect2(rect.position + Vector2(3.0, 3.0), Vector2(rect.size.x - 6.0, 3.0)), highlight, true)
	canvas.draw_rect(Rect2(rect.position + Vector2(3.0, 6.0), Vector2(rect.size.x - 6.0, 2.0)), light, true)

	var inner_x: float = rect.position.x + 4.0
	var inner_y: float = rect.position.y + 7.0
	var inner_w: float = rect.size.x - 8.0
	var row_h: int = 7
	var tile_w: int = 12
	var row_count: int = max(1, int((rect.size.y - 12.0) / float(row_h)))
	for row in range(row_count):
		var row_y: float = inner_y + float(row * row_h)
		var offset: int = int(tile_w / 2) if row % 2 == 1 else 0
		canvas.draw_rect(Rect2(Vector2(inner_x, row_y), Vector2(inner_w, float(row_h))), mid if row % 2 == 0 else alt_mid, true)
		canvas.draw_line(Vector2(inner_x, row_y + row_h), Vector2(inner_x + inner_w, row_y + row_h), roof_line, 1.0)
		var tx: float = inner_x - float(offset)
		while tx < inner_x + inner_w:
			if tx >= inner_x:
				canvas.draw_line(Vector2(tx, row_y + 1.0), Vector2(tx, row_y + float(row_h - 1)), roof_line.lightened(0.08), 1.0)
				canvas.draw_rect(Rect2(Vector2(tx + 1.0, row_y + 1.0), Vector2(3.0, 1.0)), light, true)
			tx += float(tile_w)

	var eave_y: float = rect.end.y - 7.0
	canvas.draw_rect(Rect2(Vector2(rect.position.x + 2.0, eave_y), Vector2(rect.size.x - 4.0, 5.0)), dark.darkened(0.10), true)
	canvas.draw_line(Vector2(rect.position.x + 2.0, eave_y), Vector2(rect.end.x - 3.0, eave_y), highlight, 1.0)
	canvas.draw_line(Vector2(rect.position.x + 2.0, eave_y + 5.0), Vector2(rect.end.x - 3.0, eave_y + 5.0), outline, 1.0)
	for ex in range(int(rect.position.x) + 4, int(rect.end.x) - 4, 10):
		canvas.draw_line(Vector2(ex, eave_y + 1.0), Vector2(ex, eave_y + 4.0), roof_line.darkened(0.18), 1.0)

	canvas.draw_line(rect.position + Vector2(1.0, 1.0), Vector2(rect.end.x - 2.0, rect.position.y + 1.0), roof_line.darkened(0.20), 1.0)
	canvas.draw_line(Vector2(rect.position.x + 1.0, rect.end.y - 2.0), rect.end - Vector2(2.0, 2.0), outline, 1.0)
	canvas.draw_line(rect.position + Vector2(1.0, 1.0), Vector2(rect.position.x + 1.0, rect.end.y - 2.0), outline, 1.0)
	canvas.draw_line(Vector2(rect.end.x - 2.0, rect.position.y + 1.0), rect.end - Vector2(2.0, 2.0), outline, 1.0)


static func _draw_flower_pot(canvas: CanvasItem, rect: Rect2) -> void:
	var center: Vector2 = rect.get_center()
	canvas.draw_rect(Rect2(center + Vector2(-7.0, 1.0), Vector2(14.0, 8.0)), Color(0.54, 0.27, 0.15), true)
	canvas.draw_line(center + Vector2(0.0, 1.0), center + Vector2(0.0, -8.0), Color(0.28, 0.58, 0.25), 1.4)
	canvas.draw_circle(center + Vector2(-4.0, -7.0), 2.2, Color(0.92, 0.50, 0.66))
	canvas.draw_circle(center + Vector2(4.0, -8.0), 2.2, Color(0.96, 0.80, 0.28))


static func _draw_mailbox(canvas: CanvasItem, rect: Rect2) -> void:
	var box := Rect2(rect.get_center() + Vector2(-8.0, -5.0), Vector2(16.0, 10.0))
	canvas.draw_rect(box, Color(0.34, 0.42, 0.50), true)
	canvas.draw_rect(box, LINE_COLOR, false, 1.1)
	canvas.draw_line(box.get_center() + Vector2(0.0, 5.0), box.get_center() + Vector2(0.0, 13.0), Color(0.28, 0.16, 0.08), 2.0)


static func _draw_workbench(canvas: CanvasItem, rect: Rect2) -> void:
	var table := Rect2(rect.position + Vector2(5.0, 10.0), Vector2(rect.size.x - 10.0, 12.0))
	canvas.draw_rect(table, Color(0.52, 0.31, 0.15), true)
	canvas.draw_rect(table, LINE_COLOR, false, 1.2)
	canvas.draw_line(table.position + Vector2(6.0, 3.0), table.end - Vector2(6.0, 5.0), Color(0.88, 0.68, 0.38), 1.0)


static func _draw_anvil(canvas: CanvasItem, rect: Rect2) -> void:
	var center: Vector2 = rect.get_center()
	canvas.draw_rect(Rect2(center + Vector2(-9.0, -3.0), Vector2(18.0, 7.0)), Color(0.36, 0.39, 0.42), true)
	canvas.draw_rect(Rect2(center + Vector2(-4.0, 4.0), Vector2(8.0, 7.0)), Color(0.26, 0.28, 0.30), true)
	canvas.draw_line(center + Vector2(-13.0, -3.0), center + Vector2(-9.0, 1.0), Color(0.36, 0.39, 0.42), 4.0)


static func _draw_tool_rack(canvas: CanvasItem, rect: Rect2) -> void:
	var rack := Rect2(rect.position + Vector2(6.0, 5.0), Vector2(rect.size.x - 12.0, 8.0))
	canvas.draw_rect(rack, Color(0.36, 0.21, 0.10), true)
	for index in range(3):
		var x: float = rack.position.x + 6.0 + float(index * 8)
		canvas.draw_line(Vector2(x, rack.end.y), Vector2(x + 4.0, rack.end.y + 13.0), Color(0.62, 0.62, 0.58), 1.6)


static func _draw_material_crates(canvas: CanvasItem, rect: Rect2) -> void:
	_draw_goods_crate(canvas, Rect2(rect.position, rect.size * 0.72))
	_draw_goods_crate(canvas, Rect2(rect.position + Vector2(12.0, 10.0), rect.size * 0.62))


static func _draw_shop_sign(canvas: CanvasItem, rect: Rect2) -> void:
	var sign := Rect2(rect.position + Vector2(5.0, 6.0), Vector2(rect.size.x - 10.0, 15.0))
	canvas.draw_rect(sign, Color(0.45, 0.25, 0.10), true)
	canvas.draw_rect(sign, LINE_COLOR, false, 1.2)
	_draw_centered_text(canvas, sign, "店", 14, Color(0.98, 0.82, 0.42))


static func _draw_shelf(canvas: CanvasItem, rect: Rect2) -> void:
	var shelf := rect.grow(-5.0)
	canvas.draw_rect(shelf, Color(0.38, 0.23, 0.12), true)
	canvas.draw_rect(shelf, LINE_COLOR, false, 1.2)
	for index in range(2):
		var y: float = shelf.position.y + 7.0 + float(index * 8)
		canvas.draw_line(Vector2(shelf.position.x + 2.0, y), Vector2(shelf.end.x - 2.0, y), Color(0.72, 0.52, 0.28), 1.0)
	canvas.draw_circle(shelf.position + Vector2(8.0, 9.0), 2.0, Color(0.85, 0.18, 0.14))
	canvas.draw_circle(shelf.position + Vector2(20.0, 17.0), 2.0, Color(0.95, 0.80, 0.28))


static func _draw_counter(canvas: CanvasItem, rect: Rect2) -> void:
	var counter := Rect2(rect.position + Vector2(3.0, 11.0), Vector2(rect.size.x - 6.0, 12.0))
	canvas.draw_rect(counter, Color(0.45, 0.27, 0.13), true)
	canvas.draw_rect(counter, LINE_COLOR, false, 1.2)
	canvas.draw_circle(counter.position + Vector2(counter.size.x - 8.0, 5.0), 2.0, Color(0.94, 0.73, 0.28))


static func _draw_goods_crate(canvas: CanvasItem, rect: Rect2) -> void:
	var crate := rect.grow(-6.0)
	canvas.draw_rect(crate, Color(0.58, 0.36, 0.18), true)
	canvas.draw_rect(crate, LINE_COLOR, false, 1.1)
	canvas.draw_line(crate.position, crate.end, LINE_COLOR, 1.0)
	canvas.draw_line(Vector2(crate.end.x, crate.position.y), Vector2(crate.position.x, crate.end.y), LINE_COLOR, 1.0)


static func _draw_table_set(canvas: CanvasItem, rect: Rect2) -> void:
	var center: Vector2 = rect.get_center()
	canvas.draw_circle(center, 8.0, Color(0.48, 0.30, 0.15))
	canvas.draw_arc(center, 8.0, 0.0, TAU, 18, LINE_COLOR, 1.2)
	for offset in [Vector2(0.0, -12.0), Vector2(0.0, 12.0), Vector2(-12.0, 0.0), Vector2(12.0, 0.0)]:
		canvas.draw_circle(center + offset, 4.0, Color(0.42, 0.24, 0.12))


static func _draw_barrel(canvas: CanvasItem, rect: Rect2) -> void:
	var body := Rect2(rect.get_center() + Vector2(-8.0, -10.0), Vector2(16.0, 20.0))
	canvas.draw_rect(body, Color(0.53, 0.32, 0.15), true)
	canvas.draw_rect(body, LINE_COLOR, false, 1.1)
	canvas.draw_line(body.position + Vector2(2.0, 5.0), body.end - Vector2(2.0, 14.0), Color(0.24, 0.14, 0.07), 1.0)
	canvas.draw_line(body.position + Vector2(2.0, 14.0), body.end - Vector2(2.0, 5.0), Color(0.24, 0.14, 0.07), 1.0)


static func _draw_stove(canvas: CanvasItem, rect: Rect2) -> void:
	var stove := rect.grow(-7.0)
	canvas.draw_rect(stove, Color(0.24, 0.22, 0.20), true)
	canvas.draw_rect(stove, LINE_COLOR, false, 1.2)
	canvas.draw_circle(stove.get_center(), 5.0, Color(0.98, 0.36, 0.12))
	canvas.draw_circle(stove.get_center(), 2.5, Color(1.0, 0.78, 0.24))


static func _draw_scarecrow(canvas: CanvasItem, rect: Rect2) -> void:
	var center: Vector2 = rect.get_center()
	canvas.draw_line(center + Vector2(0.0, -12.0), center + Vector2(0.0, 12.0), Color(0.35, 0.21, 0.10), 2.0)
	canvas.draw_line(center + Vector2(-10.0, -4.0), center + Vector2(10.0, -4.0), Color(0.35, 0.21, 0.10), 2.0)
	canvas.draw_circle(center + Vector2(0.0, -13.0), 5.0, Color(0.85, 0.70, 0.34))
	canvas.draw_rect(Rect2(center + Vector2(-7.0, -1.0), Vector2(14.0, 10.0)), Color(0.50, 0.36, 0.18), true)


static func _draw_bucket(canvas: CanvasItem, rect: Rect2) -> void:
	var bucket := Rect2(rect.get_center() + Vector2(-7.0, -4.0), Vector2(14.0, 12.0))
	canvas.draw_rect(bucket, Color(0.35, 0.55, 0.62), true)
	canvas.draw_rect(bucket, LINE_COLOR, false, 1.0)
	canvas.draw_arc(bucket.position + Vector2(7.0, 1.0), 8.0, PI, TAU, 12, Color(0.80, 0.80, 0.74), 1.0)


static func _draw_farm_tool(canvas: CanvasItem, rect: Rect2) -> void:
	var center: Vector2 = rect.get_center()
	canvas.draw_line(center + Vector2(-8.0, 8.0), center + Vector2(7.0, -9.0), Color(0.37, 0.22, 0.10), 2.0)
	canvas.draw_line(center + Vector2(7.0, -9.0), center + Vector2(12.0, -5.0), Color(0.62, 0.62, 0.58), 1.8)


static func _draw_fountain(canvas: CanvasItem, rect: Rect2) -> void:
	var center: Vector2 = rect.get_center()
	var radius: float = min(rect.size.x, rect.size.y) * 0.28
	canvas.draw_circle(center + Vector2(0.0, 1.5), radius + 5.0, Color(0.40, 0.38, 0.34))
	canvas.draw_circle(center, radius + 2.0, Color(0.62, 0.58, 0.50))
	canvas.draw_circle(center, radius, Color(0.30, 0.55, 0.74))
	canvas.draw_arc(center, radius, 0.0, TAU, 28, LINE_COLOR, 1.5)
	canvas.draw_line(center + Vector2(0.0, -radius + 2.0), center + Vector2(0.0, -radius - 8.0), Color(0.78, 0.92, 1.0, 0.85), 2.0)


static func _draw_notice_board(canvas: CanvasItem, rect: Rect2) -> void:
	var board := rect.grow(-5.0)
	canvas.draw_rect(board, Color(0.55, 0.34, 0.16), true)
	canvas.draw_rect(board, LINE_COLOR, false, 1.2)
	canvas.draw_line(board.position + Vector2(4.0, 7.0), board.end - Vector2(4.0, 13.0), Color(0.90, 0.76, 0.48), 1.0)
	canvas.draw_line(board.position + Vector2(4.0, 13.0), board.end - Vector2(4.0, 7.0), Color(0.90, 0.76, 0.48), 1.0)


static func _draw_bench(canvas: CanvasItem, rect: Rect2) -> void:
	var center: Vector2 = rect.get_center()
	canvas.draw_rect(Rect2(center + Vector2(-12.0, -4.0), Vector2(24.0, 5.0)), Color(0.44, 0.27, 0.13), true)
	canvas.draw_rect(Rect2(center + Vector2(-10.0, 4.0), Vector2(20.0, 4.0)), Color(0.44, 0.27, 0.13), true)


static func _draw_signpost(canvas: CanvasItem, rect: Rect2) -> void:
	var center: Vector2 = rect.get_center()
	canvas.draw_line(center + Vector2(0.0, -8.0), center + Vector2(0.0, 12.0), Color(0.36, 0.21, 0.10), 2.4)
	var sign := Rect2(center + Vector2(-13.0, -13.0), Vector2(22.0, 10.0))
	canvas.draw_rect(sign, Color(0.60, 0.39, 0.18), true)
	canvas.draw_rect(sign, LINE_COLOR, false, 1.1)


static func _draw_target(canvas: CanvasItem, rect: Rect2) -> void:
	var center: Vector2 = rect.get_center()
	canvas.draw_line(center + Vector2(0.0, 8.0), center + Vector2(0.0, 14.0), Color(0.34, 0.20, 0.10), 2.0)
	for radius in [11.0, 7.0, 3.0]:
		canvas.draw_circle(center + Vector2(0.0, -3.0), radius, Color(0.78, 0.62, 0.38) if radius > 7.0 else Color(0.86, 0.18, 0.15))
		canvas.draw_arc(center + Vector2(0.0, -3.0), radius, 0.0, TAU, 20, LINE_COLOR, 1.0)


static func _draw_training_dummy(canvas: CanvasItem, rect: Rect2) -> void:
	var center: Vector2 = rect.get_center()
	canvas.draw_circle(center + Vector2(0.0, -10.0), 5.0, Color(0.76, 0.64, 0.35))
	canvas.draw_rect(Rect2(center + Vector2(-6.0, -4.0), Vector2(12.0, 15.0)), Color(0.55, 0.42, 0.20), true)
	canvas.draw_line(center + Vector2(-10.0, 1.0), center + Vector2(10.0, 1.0), Color(0.35, 0.22, 0.10), 2.0)


static func _draw_weapon_rack(canvas: CanvasItem, rect: Rect2) -> void:
	var base := rect.grow(-6.0)
	canvas.draw_rect(Rect2(base.position + Vector2(0.0, 20.0), Vector2(base.size.x, 4.0)), Color(0.34, 0.20, 0.10), true)
	for index in range(3):
		var x: float = base.position.x + 7.0 + float(index * 8)
		canvas.draw_line(Vector2(x, base.end.y - 3.0), Vector2(x + 4.0, base.position.y + 2.0), Color(0.70, 0.70, 0.65), 1.8)


static func _draw_wood_stump(canvas: CanvasItem, rect: Rect2) -> void:
	var center: Vector2 = rect.get_center()
	canvas.draw_circle(center, 8.0, Color(0.52, 0.32, 0.14))
	canvas.draw_arc(center, 8.0, 0.0, TAU, 18, LINE_COLOR, 1.2)
	canvas.draw_arc(center, 4.0, 0.0, TAU, 14, Color(0.30, 0.18, 0.08, 0.35), 1.0)


static func _draw_flower_patch(canvas: CanvasItem, rect: Rect2, palette: String) -> void:
	var flower_color := Color(0.96, 0.82, 0.30)
	if palette == "purple":
		flower_color = Color(0.76, 0.54, 0.92)
	elif palette == "red":
		flower_color = Color(0.92, 0.30, 0.30)
	for index in range(4):
		var center: Vector2 = rect.position + Vector2(8.0 + float(index * 5), 12.0 + float(index % 2) * 5.0)
		canvas.draw_line(center + Vector2(0.0, 5.0), center, Color(0.28, 0.55, 0.24, 0.65), 1.2)
		canvas.draw_circle(center, 2.0, flower_color)


static func _draw_grass_clump(canvas: CanvasItem, rect: Rect2) -> void:
	var center: Vector2 = rect.get_center()
	for index in range(5):
		var x: float = -8.0 + float(index * 4)
		canvas.draw_line(center + Vector2(x, 8.0), center + Vector2(x + 2.0, -5.0 - float(index % 2) * 3.0), Color(0.26, 0.50, 0.24, 0.55), 1.4)


static func _draw_small_stone(canvas: CanvasItem, rect: Rect2) -> void:
	var center: Vector2 = rect.get_center()
	canvas.draw_circle(center, 5.0, Color(0.50, 0.50, 0.46, 0.72))
	canvas.draw_line(center + Vector2(-3.0, -2.0), center + Vector2(3.0, -4.0), Color(1.0, 1.0, 1.0, 0.14), 1.0)


static func _draw_road_pebbles(canvas: CanvasItem, rect: Rect2) -> void:
	for offset in [Vector2(8.0, 10.0), Vector2(17.0, 16.0), Vector2(23.0, 9.0)]:
		canvas.draw_circle(rect.position + offset, 1.5, Color(0.35, 0.28, 0.18, 0.28))


static func _draw_marker(canvas: CanvasItem, rect: Rect2, color: Color) -> void:
	canvas.draw_circle(rect.get_center(), min(rect.size.x, rect.size.y) * 0.22, color)
	canvas.draw_arc(rect.get_center(), min(rect.size.x, rect.size.y) * 0.22, 0.0, TAU, 16, LINE_COLOR, 1.1)


static func _draw_centered_text(canvas: CanvasItem, rect: Rect2, text: String, font_size: int, color: Color) -> void:
	var font: Font = ThemeDB.fallback_font
	var text_size: Vector2 = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size)
	canvas.draw_string(font, rect.position + Vector2((rect.size.x - text_size.x) * 0.5, rect.size.y * 0.5 + text_size.y * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, color)


static func _entry_rect(grid: LocationGrid, entry: Dictionary) -> Rect2:
	if entry.has("bounds"):
		return _bounds_to_rect(grid, entry.get("bounds", {}) as Dictionary)

	var cell: Vector2i = _entry_cell(entry)
	var size_data: Dictionary = entry.get("grid_size", {}) as Dictionary
	var width: int = max(1, int(size_data.get("w", 1)))
	var height: int = max(1, int(size_data.get("h", 1)))
	return Rect2(Vector2(cell.x * grid.tile_size, cell.y * grid.tile_size), Vector2(width * grid.tile_size, height * grid.tile_size))


static func _entry_cell(entry: Dictionary) -> Vector2i:
	var position_data: Dictionary = entry.get("grid_position", {}) as Dictionary
	return Vector2i(int(position_data.get("x", 0)), int(position_data.get("y", 0)))


static func _bounds_to_rect(grid: LocationGrid, bounds: Dictionary) -> Rect2:
	return Rect2(
		Vector2(int(bounds.get("x", 0)) * grid.tile_size, int(bounds.get("y", 0)) * grid.tile_size),
		Vector2(int(bounds.get("w", 0)) * grid.tile_size, int(bounds.get("h", 0)) * grid.tile_size)
	)


static func _cell_in_bounds(cell: Vector2i, bounds: Dictionary) -> bool:
	if bounds.is_empty():
		return false

	var x: int = int(bounds.get("x", 0))
	var y: int = int(bounds.get("y", 0))
	var w: int = int(bounds.get("w", 0))
	var h: int = int(bounds.get("h", 0))
	return cell.x >= x and cell.y >= y and cell.x < x + w and cell.y < y + h


static func _is_ring_edge(xx: int, yy: int, x: int, y: int, w: int, h: int) -> bool:
	return xx == x or xx == x + w - 1 or yy == y or yy == y + h - 1


static func _structure_excludes_cell(structure: Dictionary, cell: Vector2i) -> bool:
	var excluded_rows: Array = structure.get("exclude_cells", []) as Array
	for excluded_value in excluded_rows:
		var excluded: Dictionary = excluded_value as Dictionary
		if _entry_cell({ "grid_position": excluded }) == cell:
			return true
	return false


static func _soften(color: Color) -> Color:
	return color.lerp(Color(0.78, 0.76, 0.68), 0.16)


static func _roof_palette(name: String, fallback: Color) -> Dictionary:
	var base: Color = fallback
	match name:
		"purple":
			base = Color.html("#4f3a67")
		"brown":
			base = Color.html("#7a4a2a")
		"blue":
			base = Color.html("#2f5f9e")
		"red":
			base = Color.html("#8a4a3f")
		"green":
			base = Color.html("#3e6b3c")
		"gray":
			base = Color.html("#555a5f")

	return {
		"outline": Color(0.16, 0.10, 0.08, 0.95),
		"shadow": Color(0.08, 0.05, 0.04, 0.50),
		"dark": base.darkened(0.34),
		"mid": base,
		"alt_mid": base.darkened(0.12),
		"light": base.lightened(0.22),
		"highlight": base.lightened(0.40),
		"line": base.darkened(0.45),
	}


static func _zone_color(zone_type: String) -> Color:
	match zone_type:
		"residential":
			return Color(0.55, 0.35, 0.65)
		"workshop":
			return Color(0.76, 0.39, 0.18)
		"shop":
			return Color(0.22, 0.46, 0.72)
		"tavern":
			return Color(0.76, 0.28, 0.24)
		"farm":
			return Color(0.34, 0.62, 0.26)
		"plaza":
			return Color(0.78, 0.66, 0.22)
		"wild_entrance":
			return Color(0.20, 0.60, 0.58)
		"training":
			return Color(0.76, 0.30, 0.22)
		_:
			return Color(0.70, 0.62, 0.45)


static func _pattern_value(cell: Vector2i, index: int, salt: int) -> int:
	return abs(cell.x * 73 + cell.y * 151 + index * 41 + salt * 97)


static func _solid_colors(count: int, color: Color) -> PackedColorArray:
	var colors := PackedColorArray()
	for _index in range(count):
		colors.append(color)
	return colors

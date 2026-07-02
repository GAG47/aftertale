class_name RegionMapView
extends Control

signal close_requested()

const BIOME_LABELS := {
	"sea": "海",
	"coast": "海岸",
	"plain": "平原",
	"forest": "森林",
	"riverbank": "河岸 / 水域",
	"foothill": "山脚",
	"rocky": "岩地",
}

const BIOME_COLORS := {
	"sea": Color(0.08, 0.24, 0.42, 1.0),
	"coast": Color(0.68, 0.60, 0.36, 1.0),
	"plain": Color(0.38, 0.61, 0.30, 1.0),
	"forest": Color(0.13, 0.35, 0.20, 1.0),
	"riverbank": Color(0.20, 0.52, 0.66, 1.0),
	"foothill": Color(0.43, 0.44, 0.27, 1.0),
	"rocky": Color(0.40, 0.41, 0.38, 1.0),
}

const UNKNOWN_BIOME_COLOR := Color(0.34, 0.34, 0.34, 1.0)
const PANEL_BG := Color(0.055, 0.068, 0.055, 0.96)
const PANEL_BORDER := Color(0.77, 0.86, 0.66, 0.34)
const TEXT_MAIN := Color(0.96, 0.98, 0.91, 1.0)
const TEXT_DIM := Color(0.74, 0.78, 0.68, 1.0)
const MAP_BG := Color(0.15, 0.17, 0.10, 1.0)
const MAP_WASH := Color(0.95, 0.82, 0.52, 0.06)
const BIOME_BOUNDARY_COLOR := Color(0.03, 0.04, 0.025, 0.18)
const WATER_DETAIL := Color(0.72, 0.90, 0.92, 0.30)
const FOREST_DETAIL := Color(0.05, 0.17, 0.08, 0.38)
const PLAIN_DETAIL := Color(0.84, 0.90, 0.52, 0.24)
const HILL_DETAIL := Color(0.20, 0.19, 0.14, 0.30)
const ROAD_SHADOW_COLOR := Color(0.035, 0.035, 0.022, 0.58)
const ROAD_EDGE_COLOR := Color(0.68, 0.63, 0.38, 0.38)
const ROAD_CENTER_COLOR := Color(0.98, 0.91, 0.58, 0.86)
const NODE_COLOR := Color(0.94, 0.92, 0.72, 1.0)
const NODE_BORDER := Color(0.10, 0.13, 0.08, 1.0)
const NODE_LABEL_BG := Color(0.035, 0.045, 0.035, 0.78)
const NODE_LABEL_BORDER := Color(0.91, 0.86, 0.56, 0.26)
const CURRENT_COLOR := Color(1.0, 0.86, 0.20, 1.0)
const CURRENT_PIN := Color(0.16, 0.45, 0.95, 1.0)
const HOVER_COLOR := Color(0.42, 0.86, 1.0, 1.0)
const SELECTED_COLOR := Color(1.0, 1.0, 1.0, 1.0)

var _world_service: Variant
var _view_data: Dictionary = {}
var _region_map: Dictionary = {}
var _locations: Array[Dictionary] = []
var _edges: Array[Dictionary] = []
var _location_by_id: Dictionary = {}
var _current_location_id: String = ""
var _display_current_location_id: String = ""
var _selected_location_id: String = ""
var _hovered_location_id: String = ""
var _node_screen_positions: Dictionary = {}
var _map_draw_rect: Rect2 = Rect2()
var _last_error: String = ""


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	set_process(false)


func bind_world_service(world_service: Variant) -> void:
	_world_service = world_service


func open_panel() -> void:
	visible = true
	refresh()
	grab_focus()
	queue_redraw()


func close_panel() -> void:
	visible = false


func is_open() -> bool:
	return visible


func refresh() -> void:
	_last_error = ""
	_view_data.clear()
	_region_map.clear()
	_locations.clear()
	_edges.clear()
	_location_by_id.clear()
	_node_screen_positions.clear()
	_current_location_id = ""
	_display_current_location_id = ""
	_hovered_location_id = ""

	if _world_service == null or not (_world_service is Object) or not is_instance_valid(_world_service):
		_last_error = "当前没有可读取的世界服务。"
		queue_redraw()
		return
	if not _world_service.has_method("get_region_map_view_data"):
		_last_error = "世界服务没有提供区域地图只读数据。"
		queue_redraw()
		return

	_view_data = (_world_service.call("get_region_map_view_data") as Dictionary).duplicate(true)
	if _view_data.is_empty():
		_last_error = "当前没有已加载的世界。"
		queue_redraw()
		return

	_region_map = (_view_data.get("region_map", {}) as Dictionary).duplicate(true)
	_locations = _dictionary_array(_view_data.get("locations", []) as Array)
	_edges = _dictionary_array(_view_data.get("edges", []) as Array)
	_current_location_id = str(_view_data.get("current_location_id", ""))
	_display_current_location_id = str(_view_data.get("display_current_location_id", ""))
	_build_location_index()

	if _region_map.is_empty():
		_last_error = "当前世界缺少区域母图。"
	elif _locations.is_empty():
		_last_error = "当前世界没有地点节点。"

	if not _display_current_location_id.is_empty() and _location_by_id.has(_display_current_location_id):
		_selected_location_id = _display_current_location_id
	elif _selected_location_id.is_empty() or not _location_by_id.has(_selected_location_id):
		_selected_location_id = _first_region_location_id()

	queue_redraw()


func get_view_summary() -> Dictionary:
	return {
		"visible": visible,
		"world_id": str(_view_data.get("world_id", "")),
		"region_width": int(_region_map.get("width", 0)),
		"region_height": int(_region_map.get("height", 0)),
		"location_count": _locations.size(),
		"edge_count": _edges.size(),
		"current_location_id": _current_location_id,
		"display_current_location_id": _display_current_location_id,
		"selected_location_id": _selected_location_id,
		"node_labels_enabled": true,
		"road_lines_enabled": true,
		"adventure_style_enabled": true,
		"grid_visible": false,
		"current_marker_style": "pin",
		"error": _last_error,
	}


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and visible:
		queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventMouseMotion:
		var mouse_event: InputEventMouseMotion = event as InputEventMouseMotion
		var next_hover := _location_at_position(mouse_event.position)
		if next_hover != _hovered_location_id:
			_hovered_location_id = next_hover
			queue_redraw()
		return
	if event is InputEventMouseButton:
		var button_event: InputEventMouseButton = event as InputEventMouseButton
		if button_event.button_index == MOUSE_BUTTON_LEFT and button_event.pressed:
			var clicked_location := _location_at_position(button_event.position)
			if not clicked_location.is_empty():
				_selected_location_id = clicked_location
				queue_redraw()
				get_viewport().set_input_as_handled()


func _draw() -> void:
	if not visible:
		return

	_node_screen_positions.clear()
	var font := get_theme_default_font()
	var base_size := get_theme_default_font_size()
	var full_rect := Rect2(Vector2.ZERO, size)
	draw_rect(full_rect, Color(0.0, 0.0, 0.0, 0.50), true)

	var window_rect := _window_rect()
	draw_rect(window_rect, PANEL_BG, true)
	draw_rect(window_rect, PANEL_BORDER, false, 2.0)

	_draw_text(font, window_rect.position + Vector2(18, 30), "区域大地图", base_size + 8, TEXT_MAIN)
	_draw_text(font, window_rect.position + Vector2(window_rect.size.x - 170, 30), "M / Esc 关闭", base_size, TEXT_DIM)

	if not _last_error.is_empty():
		_draw_text(font, window_rect.position + Vector2(18, 76), _last_error, base_size + 2, Color(1.0, 0.62, 0.48, 1.0))
		return

	var legend_rect := Rect2(window_rect.position + Vector2(18, 58), Vector2(170, window_rect.size.y - 76))
	var info_rect := Rect2(window_rect.position + Vector2(window_rect.size.x - 292, 58), Vector2(274, window_rect.size.y - 76))
	var map_rect := Rect2(
		window_rect.position + Vector2(204, 64),
		Vector2(window_rect.size.x - 514, window_rect.size.y - 92)
	)
	_draw_legend(font, legend_rect, base_size)
	_draw_map(font, map_rect, base_size)
	_draw_info(font, info_rect, base_size)


func _window_rect() -> Rect2:
	var margin := Vector2(24, 44)
	var window_size := size - margin * 2.0
	if window_size.x < 760:
		window_size.x = maxf(320.0, size.x - 24.0)
	if window_size.y < 480:
		window_size.y = maxf(300.0, size.y - 24.0)
	var position := (size - window_size) * 0.5
	return Rect2(position, window_size)


func _draw_legend(font: Font, rect: Rect2, font_size: int) -> void:
	draw_rect(rect, Color(0.07, 0.085, 0.065, 0.88), true)
	draw_rect(rect, PANEL_BORDER, false, 1.0)
	_draw_text(font, rect.position + Vector2(12, 24), "图例", font_size + 3, TEXT_MAIN)
	var y := rect.position.y + 54.0
	for biome in ["plain", "forest", "riverbank", "coast", "foothill", "rocky", "sea"]:
		var color := _biome_color(biome)
		draw_rect(Rect2(Vector2(rect.position.x + 14, y - 13), Vector2(18, 18)), color, true)
		draw_rect(Rect2(Vector2(rect.position.x + 14, y - 13), Vector2(18, 18)), Color(0.0, 0.0, 0.0, 0.28), false, 1.0)
		_draw_text(font, Vector2(rect.position.x + 40, y + 2), _biome_label(biome), font_size, TEXT_MAIN)
		y += 30.0

	y += 12.0
	_draw_route_line(Vector2(rect.position.x + 14, y), Vector2(rect.position.x + 42, y), "legend", 0.55)
	_draw_text(font, Vector2(rect.position.x + 52, y + 5), "旅行路线", font_size, TEXT_MAIN)
	y += 34.0
	_draw_node_icon(Vector2(rect.position.x + 24, y - 4), "forest", false)
	_draw_text(font, Vector2(rect.position.x + 52, y + 2), "地点", font_size, TEXT_MAIN)
	y += 34.0
	_draw_current_marker(Vector2(rect.position.x + 24, y + 4), 0.7)
	_draw_text(font, Vector2(rect.position.x + 52, y + 2), "当前位置", font_size, TEXT_MAIN)


func _draw_map(font: Font, rect: Rect2, font_size: int) -> void:
	draw_rect(rect, MAP_BG, true)
	draw_rect(rect, PANEL_BORDER, false, 1.0)

	var width := int(_region_map.get("width", 0))
	var height := int(_region_map.get("height", 0))
	var biome_map: Array = _region_map.get("biome_map", []) as Array
	if width <= 0 or height <= 0 or biome_map.is_empty():
		_draw_text(font, rect.position + Vector2(14, 28), "区域母图不可用。", font_size, TEXT_DIM)
		return

	var cell_size := minf(rect.size.x / float(width), rect.size.y / float(height))
	var draw_size := Vector2(cell_size * float(width), cell_size * float(height))
	_map_draw_rect = Rect2(rect.position + (rect.size - draw_size) * 0.5, draw_size)

	for y in range(height):
		for x in range(width):
			var biome := _map_string(biome_map, Vector2i(x, y))
			var cell_rect := Rect2(
				_map_draw_rect.position + Vector2(float(x) * cell_size, float(y) * cell_size),
				Vector2(cell_size + 1.2, cell_size + 1.2)
			)
			draw_rect(cell_rect, _terrain_color(biome, Vector2i(x, y)), true)

	draw_rect(_map_draw_rect, MAP_WASH, true)
	_draw_biome_textures(biome_map, width, height, cell_size)
	_draw_biome_boundaries(biome_map, width, height, cell_size)

	_draw_edges(cell_size)
	_draw_nodes(font, font_size, cell_size)
	if _node_screen_positions.is_empty():
		_draw_text(font, rect.position + Vector2(14, 28), "没有可显示的区域地点。", font_size, TEXT_DIM)


func _draw_biome_textures(biome_map: Array, width: int, height: int, cell_size: float) -> void:
	if cell_size < 9.0:
		return
	for y in range(height):
		for x in range(width):
			var cell := Vector2i(x, y)
			var biome := _map_string(biome_map, cell)
			var rect := _cell_rect(cell, cell_size)
			match biome:
				"sea", "riverbank":
					_draw_water_marks(rect, cell, cell_size, biome == "sea")
				"forest":
					_draw_forest_marks(rect, cell, cell_size)
				"foothill":
					_draw_hill_marks(rect, cell, cell_size)
				"rocky":
					_draw_rock_marks(rect, cell, cell_size)
				"coast":
					_draw_coast_marks(rect, cell, cell_size)
				"plain":
					_draw_plain_marks(rect, cell, cell_size)


func _draw_biome_boundaries(biome_map: Array, width: int, height: int, cell_size: float) -> void:
	for y in range(height):
		for x in range(width):
			var cell := Vector2i(x, y)
			var biome := _map_string(biome_map, cell)
			if x < width - 1 and _map_string(biome_map, Vector2i(x + 1, y)) != biome:
				var px := _map_draw_rect.position.x + float(x + 1) * cell_size
				var y0 := _map_draw_rect.position.y + float(y) * cell_size
				draw_line(Vector2(px, y0), Vector2(px, y0 + cell_size), BIOME_BOUNDARY_COLOR, 1.2)
			if y < height - 1 and _map_string(biome_map, Vector2i(x, y + 1)) != biome:
				var py := _map_draw_rect.position.y + float(y + 1) * cell_size
				var x0 := _map_draw_rect.position.x + float(x) * cell_size
				draw_line(Vector2(x0, py), Vector2(x0 + cell_size, py), BIOME_BOUNDARY_COLOR, 1.2)


func _draw_water_marks(rect: Rect2, cell: Vector2i, cell_size: float, is_sea: bool) -> void:
	var line_count: int = 2 if is_sea else 1
	for index in range(line_count):
		var t := _map_noise(cell, 41 + index)
		var y := rect.position.y + cell_size * (0.32 + 0.28 * float(index)) + (t - 0.5) * cell_size * 0.14
		var x0 := rect.position.x + cell_size * (0.18 + _map_noise(cell, 51 + index) * 0.18)
		var x1 := rect.position.x + cell_size * (0.68 + _map_noise(cell, 61 + index) * 0.12)
		draw_line(Vector2(x0, y), Vector2(x1, y + cell_size * 0.035), WATER_DETAIL, maxf(1.0, cell_size * 0.035))


func _draw_forest_marks(rect: Rect2, cell: Vector2i, cell_size: float) -> void:
	var count: int = 2 if cell_size >= 20.0 else 1
	for index in range(count):
		var center := rect.position + Vector2(
			cell_size * (0.30 + _map_noise(cell, 101 + index) * 0.42),
			cell_size * (0.30 + _map_noise(cell, 111 + index) * 0.40)
		)
		var radius := maxf(2.0, cell_size * (0.055 + _map_noise(cell, 121 + index) * 0.035))
		draw_circle(center, radius, FOREST_DETAIL)
		draw_line(center + Vector2(0.0, radius * 0.6), center + Vector2(0.0, radius * 1.55), Color(0.10, 0.07, 0.035, 0.26), maxf(1.0, radius * 0.25))


func _draw_hill_marks(rect: Rect2, cell: Vector2i, cell_size: float) -> void:
	var center := rect.position + Vector2(cell_size * (0.35 + _map_noise(cell, 201) * 0.25), cell_size * 0.66)
	var width := cell_size * (0.26 + _map_noise(cell, 211) * 0.14)
	var height := cell_size * (0.18 + _map_noise(cell, 221) * 0.10)
	var points := PackedVector2Array([
		center + Vector2(-width * 0.5, 0.0),
		center + Vector2(0.0, -height),
		center + Vector2(width * 0.5, 0.0),
	])
	draw_polygon(points, PackedColorArray([HILL_DETAIL, HILL_DETAIL, HILL_DETAIL]))


func _draw_rock_marks(rect: Rect2, cell: Vector2i, cell_size: float) -> void:
	var center := rect.position + Vector2(
		cell_size * (0.28 + _map_noise(cell, 301) * 0.44),
		cell_size * (0.32 + _map_noise(cell, 311) * 0.34)
	)
	var radius := maxf(2.0, cell_size * 0.055)
	draw_circle(center, radius, HILL_DETAIL)
	draw_circle(center + Vector2(radius * 1.5, radius * 0.4), radius * 0.65, HILL_DETAIL)


func _draw_coast_marks(rect: Rect2, cell: Vector2i, cell_size: float) -> void:
	var dot_count: int = 2 if cell_size >= 18.0 else 1
	for index in range(dot_count):
		var center := rect.position + Vector2(
			cell_size * (0.25 + _map_noise(cell, 401 + index) * 0.50),
			cell_size * (0.30 + _map_noise(cell, 411 + index) * 0.42)
		)
		draw_circle(center, maxf(1.0, cell_size * 0.032), Color(0.96, 0.86, 0.55, 0.30))


func _draw_plain_marks(rect: Rect2, cell: Vector2i, cell_size: float) -> void:
	if _map_noise(cell, 501) < 0.45:
		return
	var base := rect.position + Vector2(cell_size * (0.28 + _map_noise(cell, 511) * 0.45), cell_size * (0.62 + _map_noise(cell, 521) * 0.16))
	var height := maxf(2.0, cell_size * 0.10)
	draw_line(base, base + Vector2(cell_size * 0.06, -height), PLAIN_DETAIL, maxf(1.0, cell_size * 0.025))
	draw_line(base + Vector2(cell_size * 0.06, 0.0), base + Vector2(cell_size * 0.13, -height * 0.75), PLAIN_DETAIL, maxf(1.0, cell_size * 0.025))


func _draw_edges(cell_size: float) -> void:
	var drawn_pairs := {}
	for edge_value in _edges:
		var edge: Dictionary = edge_value as Dictionary
		var from_id := str(edge.get("from_location_id", ""))
		var to_id := str(edge.get("target_location_id", ""))
		if from_id.is_empty() or to_id.is_empty():
			continue
		var pair_key := _pair_key(from_id, to_id)
		if drawn_pairs.has(pair_key):
			continue
		var from_pos := _screen_position_for_location(from_id, cell_size)
		var to_pos := _screen_position_for_location(to_id, cell_size)
		if not _is_valid_screen_position(from_pos) or not _is_valid_screen_position(to_pos):
			continue
		drawn_pairs[pair_key] = true
		_draw_route_line(from_pos, to_pos, pair_key)


func _draw_nodes(font: Font, font_size: int, cell_size: float) -> void:
	for location_value in _locations:
		var location: Dictionary = location_value as Dictionary
		var location_id := str(location.get("location_id", ""))
		var pos := _screen_position_for_location(location_id, cell_size)
		if not _is_valid_screen_position(pos):
			continue
		_node_screen_positions[location_id] = pos
		var is_current := location_id == _display_current_location_id
		var is_selected := location_id == _selected_location_id
		var is_hovered := location_id == _hovered_location_id
		if is_selected:
			draw_arc(pos, 16.0, 0.0, TAU, 48, SELECTED_COLOR, 2.0)
		if is_hovered:
			draw_arc(pos, 19.0, 0.0, TAU, 48, HOVER_COLOR, 2.0)
		if is_current:
			_draw_current_marker(pos)
		else:
			_draw_node_icon(pos, _location_biome(location), false)
		_draw_node_label(font, location, pos, is_current, is_selected or is_hovered, font_size, cell_size)


func _draw_node_icon(position: Vector2, biome: String, is_current: bool) -> void:
	var radius := 8.0 if not is_current else 9.0
	draw_circle(position, radius + 2.2, NODE_BORDER)
	draw_circle(position, radius, CURRENT_COLOR if is_current else NODE_COLOR)
	_draw_node_symbol(position, biome, is_current)


func _draw_node_symbol(position: Vector2, biome: String, is_current: bool) -> void:
	var color := Color(0.16, 0.20, 0.12, 0.92)
	if is_current:
		color = CURRENT_PIN
	match biome:
		"forest":
			var top := position + Vector2(0.0, -4.8)
			var tree := PackedVector2Array([
				top,
				position + Vector2(-4.8, 2.5),
				position + Vector2(4.8, 2.5),
			])
			draw_polygon(tree, PackedColorArray([color, color, color]))
			draw_line(position + Vector2(0.0, 2.0), position + Vector2(0.0, 5.4), color, 1.4)
		"riverbank", "sea":
			for index in range(2):
				var y := position.y - 2.4 + float(index) * 4.0
				draw_line(Vector2(position.x - 4.8, y), Vector2(position.x + 4.8, y + 1.2), color, 1.4)
		"foothill", "rocky":
			var mountain := PackedVector2Array([
				position + Vector2(-5.2, 4.0),
				position + Vector2(-1.0, -4.6),
				position + Vector2(2.0, 1.0),
				position + Vector2(4.8, 4.0),
			])
			draw_polyline(mountain, color, 1.6, true)
		_:
			draw_line(position + Vector2(-3.6, 3.8), position + Vector2(-1.6, -3.0), color, 1.3)
			draw_line(position + Vector2(0.0, 4.0), position + Vector2(1.0, -3.6), color, 1.3)
			draw_line(position + Vector2(3.0, 3.5), position + Vector2(4.4, -1.5), color, 1.3)


func _draw_current_marker(position: Vector2, scale: float = 1.0) -> void:
	var head := position + Vector2(0.0, -11.0 * scale)
	var left := head + Vector2(-5.8 * scale, 6.8 * scale)
	var right := head + Vector2(5.8 * scale, 6.8 * scale)
	draw_circle(head + Vector2(1.6 * scale, 2.0 * scale), 9.8 * scale, Color(0.0, 0.0, 0.0, 0.34))
	draw_polygon(PackedVector2Array([position, left + Vector2(1.6 * scale, 2.0 * scale), right + Vector2(1.6 * scale, 2.0 * scale)]), PackedColorArray([Color(0.0, 0.0, 0.0, 0.34), Color(0.0, 0.0, 0.0, 0.34), Color(0.0, 0.0, 0.0, 0.34)]))
	draw_polygon(PackedVector2Array([position, left, right]), PackedColorArray([CURRENT_PIN, CURRENT_PIN, CURRENT_PIN]))
	draw_circle(head, 9.4 * scale, CURRENT_PIN)
	draw_circle(head, 5.0 * scale, Color(0.96, 0.98, 1.0, 1.0))
	draw_circle(head, 2.6 * scale, Color(0.12, 0.34, 0.78, 1.0))


func _draw_info(font: Font, rect: Rect2, font_size: int) -> void:
	draw_rect(rect, Color(0.07, 0.085, 0.065, 0.88), true)
	draw_rect(rect, PANEL_BORDER, false, 1.0)
	_draw_text(font, rect.position + Vector2(12, 24), "地点信息", font_size + 3, TEXT_MAIN)

	var location_id := _selected_location_id
	if not _hovered_location_id.is_empty():
		location_id = _hovered_location_id
	var location: Dictionary = _location_by_id.get(location_id, {}) as Dictionary
	if location.is_empty():
		_draw_lines(font, Rect2(rect.position + Vector2(12, 56), rect.size - Vector2(24, 64)), ["暂无选中地点。"], font_size, TEXT_DIM)
		return

	var lines: Array[String] = []
	var display_name := _location_display_name(location)
	var biome := str(location.get("region_biome", ""))
	lines.append("名称：%s" % display_name)
	lines.append("地貌：%s" % _biome_label(biome))
	lines.append("地点 ID：%s" % location_id)
	if location_id == _display_current_location_id:
		lines.append("当前位置：是")
	elif _current_location_id == location_id:
		lines.append("当前位置：是")
	else:
		lines.append("当前位置：否")
	if _current_location_id != _display_current_location_id and location_id == _display_current_location_id:
		lines.append("当前子地点：%s" % _current_location_id)
	var connections := _connection_names(location_id)
	lines.append("")
	lines.append("连接地点：")
	if connections.is_empty():
		lines.append("无")
	else:
		for name in connections:
			lines.append("- %s" % name)
	_draw_lines(font, Rect2(rect.position + Vector2(12, 56), rect.size - Vector2(24, 64)), lines, font_size, TEXT_MAIN)


func _draw_route_line(from_pos: Vector2, to_pos: Vector2, route_key: String, scale: float = 1.0) -> void:
	var points := PackedVector2Array()
	var control := _route_control_point(from_pos, to_pos, route_key)
	var segments: int = 28
	for index in range(segments + 1):
		var t := float(index) / float(segments)
		points.append(_quadratic_point(from_pos, control, to_pos, t))

	draw_polyline(points, ROAD_SHADOW_COLOR, maxf(1.0, 7.0 * scale), true)
	draw_polyline(points, ROAD_EDGE_COLOR, maxf(1.0, 3.2 * scale), true)

	var length := from_pos.distance_to(to_pos)
	var dot_count: int = maxi(2, int(length / maxf(8.0, 13.0 * scale)))
	for index in range(dot_count + 1):
		var t := float(index) / float(dot_count)
		var dot := _quadratic_point(from_pos, control, to_pos, t)
		draw_circle(dot, maxf(1.0, 1.9 * scale), ROAD_CENTER_COLOR)


func _route_control_point(from_pos: Vector2, to_pos: Vector2, route_key: String) -> Vector2:
	var delta := to_pos - from_pos
	var length := delta.length()
	if length <= 0.1:
		return (from_pos + to_pos) * 0.5
	var normal := Vector2(-delta.y, delta.x).normalized()
	var route_hash: int = int(abs(hash(route_key)))
	var sign := 1.0 if route_hash % 2 == 0 else -1.0
	var offset := minf(42.0, maxf(8.0, length * 0.12)) * sign
	return (from_pos + to_pos) * 0.5 + normal * offset


func _quadratic_point(from_pos: Vector2, control: Vector2, to_pos: Vector2, t: float) -> Vector2:
	var a := from_pos.lerp(control, t)
	var b := control.lerp(to_pos, t)
	return a.lerp(b, t)


func _draw_node_label(
	font: Font,
	location: Dictionary,
	node_position: Vector2,
	is_current: bool,
	is_emphasized: bool,
	font_size: int,
	cell_size: float
) -> void:
	if cell_size < 16.0 and not is_current and not is_emphasized:
		return

	var label_font_size: int = maxi(10, font_size - 2)
	var max_chars: int = 10
	if is_current or is_emphasized:
		max_chars = 14
	var label := _truncate_line(_location_display_name(location), max_chars)
	var text_size: Vector2 = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, label_font_size)
	var box_size := text_size + Vector2(8.0, 7.0)
	var box_position := node_position + Vector2(10.0, -float(label_font_size) - 10.0)

	var map_right := _map_draw_rect.position.x + _map_draw_rect.size.x
	var map_bottom := _map_draw_rect.position.y + _map_draw_rect.size.y
	if box_position.x + box_size.x > map_right:
		box_position.x = node_position.x - box_size.x - 10.0
	if box_position.y < _map_draw_rect.position.y:
		box_position.y = node_position.y + 10.0
	if box_position.y + box_size.y > map_bottom:
		box_position.y = map_bottom - box_size.y
	box_position.x = maxf(_map_draw_rect.position.x, box_position.x)
	box_position.y = maxf(_map_draw_rect.position.y, box_position.y)

	var box_rect := Rect2(box_position, box_size)
	draw_rect(box_rect, NODE_LABEL_BG, true)
	draw_rect(box_rect, CURRENT_COLOR if is_current else NODE_LABEL_BORDER, false, 1.0)
	_draw_text(font, box_rect.position + Vector2(4.0, float(label_font_size) + 1.0), label, label_font_size, CURRENT_COLOR if is_current else TEXT_MAIN)


func _location_display_name(location: Dictionary) -> String:
	var location_id := str(location.get("location_id", ""))
	var display_name := str(location.get("display_name", ""))
	return display_name if not display_name.is_empty() else location_id


func _location_biome(location: Dictionary) -> String:
	return str(location.get("region_biome", "plain"))


func _location_at_position(position: Vector2) -> String:
	var best_id := ""
	var best_distance := INF
	for location_id_value in _node_screen_positions.keys():
		var location_id := str(location_id_value)
		var node_position: Vector2 = _node_screen_positions.get(location_id, Vector2(-100000.0, -100000.0)) as Vector2
		var distance := position.distance_to(node_position)
		if distance <= 18.0 and distance < best_distance:
			best_distance = distance
			best_id = location_id
	return best_id


func _screen_position_for_location(location_id: String, cell_size: float) -> Vector2:
	var region_position := _region_position_for_location(location_id)
	if region_position.x < 0 or region_position.y < 0:
		return Vector2(-100000.0, -100000.0)
	return _map_draw_rect.position + Vector2((float(region_position.x) + 0.5) * cell_size, (float(region_position.y) + 0.5) * cell_size)


func _region_position_for_location(location_id: String) -> Vector2i:
	var cursor := location_id
	var visited := {}
	while not cursor.is_empty() and not visited.has(cursor):
		visited[cursor] = true
		var location: Dictionary = _location_by_id.get(cursor, {}) as Dictionary
		var position: Dictionary = location.get("region_position", {}) as Dictionary
		if position.has("x") and position.has("y"):
			return Vector2i(int(position.get("x", -1)), int(position.get("y", -1)))
		cursor = str(location.get("parent_location_id", ""))
	return Vector2i(-1, -1)


func _connection_names(location_id: String) -> Array[String]:
	var result: Array[String] = []
	var seen := {}
	for edge_value in _edges:
		var edge: Dictionary = edge_value as Dictionary
		var other_id := ""
		if str(edge.get("from_location_id", "")) == location_id:
			other_id = str(edge.get("target_location_id", ""))
		elif str(edge.get("target_location_id", "")) == location_id:
			other_id = str(edge.get("from_location_id", ""))
		if other_id.is_empty() or seen.has(other_id):
			continue
		seen[other_id] = true
		var other: Dictionary = _location_by_id.get(other_id, {}) as Dictionary
		result.append(_location_display_name(other))
	result.sort()
	return result


func _build_location_index() -> void:
	_location_by_id.clear()
	for location_value in _locations:
		var location: Dictionary = location_value as Dictionary
		var location_id := str(location.get("location_id", ""))
		if not location_id.is_empty():
			_location_by_id[location_id] = location


func _first_region_location_id() -> String:
	for location_value in _locations:
		var location: Dictionary = location_value as Dictionary
		var location_id := str(location.get("location_id", ""))
		var position: Dictionary = location.get("region_position", {}) as Dictionary
		if not location_id.is_empty() and position.has("x") and position.has("y"):
			return location_id
	return ""


func _dictionary_array(values: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for value in values:
		result.append((value as Dictionary).duplicate(true))
	return result


func _cell_rect(cell: Vector2i, cell_size: float) -> Rect2:
	return Rect2(
		_map_draw_rect.position + Vector2(float(cell.x) * cell_size, float(cell.y) * cell_size),
		Vector2(cell_size, cell_size)
	)


func _map_string(map_data: Array, cell: Vector2i) -> String:
	if cell.y < 0 or cell.y >= map_data.size():
		return ""
	var row: Array = map_data[cell.y] as Array
	if cell.x < 0 or cell.x >= row.size():
		return ""
	return str(row[cell.x])


func _biome_label(biome: String) -> String:
	return str(BIOME_LABELS.get(biome, "未知地貌"))


func _terrain_color(biome: String, cell: Vector2i) -> Color:
	var base := _biome_color(biome)
	var amount := (_map_noise(cell, 17) - 0.5) * 0.16
	return _scale_color(base, 1.0 + amount)


func _biome_color(biome: String) -> Color:
	return BIOME_COLORS.get(biome, UNKNOWN_BIOME_COLOR) as Color


func _scale_color(color: Color, factor: float) -> Color:
	return Color(
		clampf(color.r * factor, 0.0, 1.0),
		clampf(color.g * factor, 0.0, 1.0),
		clampf(color.b * factor, 0.0, 1.0),
		color.a
	)


func _map_noise(cell: Vector2i, salt: int) -> float:
	var world_id := str(_view_data.get("world_id", "region_map"))
	var seed_value: int = int(abs(hash("%s:%d:%d:%d" % [world_id, cell.x, cell.y, salt])) % 100000)
	var value := sin(float(seed_value) * 12.9898 + float(cell.x * 37 + cell.y * 91 + salt) * 0.173) * 43758.5453123
	return value - floor(value)


func _pair_key(a: String, b: String) -> String:
	return "%s::%s" % [a, b] if a < b else "%s::%s" % [b, a]


func _is_valid_screen_position(position: Vector2) -> bool:
	return position.x > -99999.0 and position.y > -99999.0


func _draw_text(font: Font, position: Vector2, text: String, font_size: int, color: Color) -> void:
	draw_string(font, position, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, color)


func _draw_lines(font: Font, rect: Rect2, lines: Array[String], font_size: int, color: Color) -> void:
	var y := rect.position.y + float(font_size)
	var line_height := float(font_size) + 8.0
	var max_chars := maxi(8, int(rect.size.x / maxf(8.0, float(font_size) * 0.58)))
	for line in lines:
		if y > rect.position.y + rect.size.y:
			return
		_draw_text(font, Vector2(rect.position.x, y), _truncate_line(line, max_chars), font_size, color if not line.begins_with("- ") else TEXT_DIM)
		y += line_height


func _truncate_line(text: String, max_chars: int) -> String:
	if text.length() <= max_chars:
		return text
	return text.substr(0, maxi(0, max_chars - 3)) + "..."

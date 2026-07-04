class_name RegionMapView
extends Control

signal close_requested()

const AREA_TYPE_LABELS := {
	"plain": "平原",
	"forest": "森林",
	"hills": "丘陵",
	"highland": "高地",
	"mountain": "山地",
	"river_valley": "河谷",
	"wetland": "湿地",
	"lake_region": "湖区",
	"coastland": "海岸带",
	"rocky_wilds": "岩地荒野",
	"settlement_area": "聚居区",
}

const AREA_TYPE_COLORS := {
	"plain": Color(0.38, 0.61, 0.30, 1.0),
	"forest": Color(0.13, 0.35, 0.20, 1.0),
	"hills": Color(0.43, 0.48, 0.28, 1.0),
	"highland": Color(0.47, 0.46, 0.30, 1.0),
	"mountain": Color(0.40, 0.39, 0.34, 1.0),
	"river_valley": Color(0.24, 0.54, 0.55, 1.0),
	"wetland": Color(0.25, 0.49, 0.38, 1.0),
	"lake_region": Color(0.15, 0.42, 0.60, 1.0),
	"coastland": Color(0.68, 0.60, 0.36, 1.0),
	"rocky_wilds": Color(0.40, 0.41, 0.38, 1.0),
	"settlement_area": Color(0.50, 0.40, 0.25, 1.0),
}

const UNKNOWN_AREA_COLOR := Color(0.34, 0.34, 0.34, 1.0)
const PANEL_BG := Color(0.055, 0.068, 0.055, 0.96)
const PANEL_BORDER := Color(0.77, 0.86, 0.66, 0.34)
const TEXT_MAIN := Color(0.96, 0.98, 0.91, 1.0)
const TEXT_DIM := Color(0.74, 0.78, 0.68, 1.0)
const MAP_BG := Color(0.15, 0.17, 0.10, 1.0)
const MAP_WASH := Color(0.95, 0.82, 0.52, 0.06)
const REGION_BOUNDARY_COLOR := Color(0.03, 0.04, 0.025, 0.18)
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
const REGION_ADJACENCY_COLOR := Color(0.95, 0.91, 0.58, 0.30)
const FOCUSED_REGION_FILL := Color(1.0, 0.90, 0.24, 0.16)
const FOCUSED_REGION_BORDER := Color(1.0, 0.92, 0.28, 0.58)
const ZOOM_MIN := 0.78
const ZOOM_MAX := 2.10
const ZOOM_DEFAULT := 0.86
const ZOOM_STEP := 0.18
const ZOOM_LAYER_BLEND_START := 1.08
const ZOOM_LAYER_BLEND_END := 1.56
const LAYER_VISIBLE_EPSILON := 0.04
const SELECTION_NONE := "none"
const SELECTION_REGION := "region_area"
const SELECTION_LOCATION := "location_node"

var _world_service: Variant
var _view_data: Dictionary = {}
var _region_map: Dictionary = {}
var _region_areas: Array[Dictionary] = []
var _locations: Array[Dictionary] = []
var _edges: Array[Dictionary] = []
var _region_area_by_id: Dictionary = {}
var _region_cell_owner_by_key: Dictionary = {}
var _location_by_id: Dictionary = {}
var _current_location_id: String = ""
var _display_current_location_id: String = ""
var _current_region_id: String = ""
var _focused_region_id: String = ""
var _selected_region_id: String = ""
var _selected_location_id: String = ""
var _selection_type: String = SELECTION_NONE
var _hovered_region_id: String = ""
var _hovered_location_id: String = ""
var _node_screen_positions: Dictionary = {}
var _region_screen_positions: Dictionary = {}
var _map_draw_rect: Rect2 = Rect2()
var _zoom_level: float = ZOOM_DEFAULT
var _region_layer_alpha: float = 1.0
var _location_layer_alpha: float = 0.0
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
	_zoom_level = ZOOM_DEFAULT
	_update_layer_alpha()
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
	_region_areas.clear()
	_locations.clear()
	_edges.clear()
	_region_area_by_id.clear()
	_region_cell_owner_by_key.clear()
	_location_by_id.clear()
	_node_screen_positions.clear()
	_region_screen_positions.clear()
	_current_location_id = ""
	_display_current_location_id = ""
	_current_region_id = ""
	_focused_region_id = ""
	_hovered_region_id = ""
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
	_region_areas = _dictionary_array(_view_data.get("region_areas", []) as Array)
	_locations = _dictionary_array(_view_data.get("locations", []) as Array)
	_edges = _dictionary_array(_view_data.get("edges", []) as Array)
	_current_location_id = str(_view_data.get("current_location_id", ""))
	_display_current_location_id = str(_view_data.get("display_current_location_id", ""))
	_current_region_id = str(_view_data.get("current_region_id", ""))
	_build_region_area_index()
	_build_location_index()
	_update_focus_region()

	if _region_map.is_empty():
		_last_error = "当前世界缺少区域母图。"
	elif _locations.is_empty():
		_last_error = "当前世界没有地点节点。"

	if _selected_region_id.is_empty() or not _region_area_by_id.has(_selected_region_id):
		_selected_region_id = _focused_region_id
	if _selected_location_id.is_empty() or not _location_by_id.has(_selected_location_id):
		_selected_location_id = ""
	if _selection_type == SELECTION_NONE and not _selected_region_id.is_empty():
		_selection_type = SELECTION_REGION

	queue_redraw()


func get_view_summary() -> Dictionary:
	_update_layer_alpha()
	_update_focus_region()
	return {
		"visible": visible,
		"world_id": str(_view_data.get("world_id", "")),
		"region_width": int(_region_map.get("width", 0)),
		"region_height": int(_region_map.get("height", 0)),
		"region_area_count": _region_areas.size(),
		"location_count": _locations.size(),
		"edge_count": _edges.size(),
		"current_location_id": _current_location_id,
		"display_current_location_id": _display_current_location_id,
		"current_region_id": _current_region_id,
		"focused_region_id": _focused_region_id,
		"selected_region_id": _selected_region_id,
		"selected_location_id": _selected_location_id,
		"selection_type": _selection_type,
		"hovered_region_id": _hovered_region_id,
		"hovered_location_id": _hovered_location_id,
		"zoom_level": _zoom_level,
		"region_layer_alpha": _round3(_region_layer_alpha),
		"location_layer_alpha": _round3(_location_layer_alpha),
		"visible_region_area_ids": _visible_region_area_ids(),
		"visible_location_ids": _visible_location_ids(),
		"visible_location_edge_ids": _visible_location_edge_ids(),
		"visible_region_adjacency_ids": _visible_region_adjacency_ids(),
		"region_area_labels_enabled": true,
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
	if event is InputEventKey:
		var key_event: InputEventKey = event as InputEventKey
		if key_event.pressed and not key_event.echo:
			if key_event.keycode == KEY_ESCAPE or key_event.keycode == KEY_M:
				close_requested.emit()
				get_viewport().set_input_as_handled()
				return
			if key_event.keycode == KEY_PLUS or key_event.keycode == KEY_EQUAL or key_event.keycode == KEY_KP_ADD:
				zoom_by_steps(1)
				get_viewport().set_input_as_handled()
				return
			if key_event.keycode == KEY_MINUS or key_event.keycode == KEY_KP_SUBTRACT:
				zoom_by_steps(-1)
				get_viewport().set_input_as_handled()
				return
	if event is InputEventMouseMotion:
		var mouse_event: InputEventMouseMotion = event as InputEventMouseMotion
		var next_region := _region_at_position(mouse_event.position)
		var next_location := _location_at_position(mouse_event.position)
		if next_region != _hovered_region_id or next_location != _hovered_location_id:
			_hovered_region_id = next_region
			_hovered_location_id = next_location
			_update_focus_region()
			queue_redraw()
		return
	if event is InputEventMouseButton:
		var button_event: InputEventMouseButton = event as InputEventMouseButton
		if button_event.button_index == MOUSE_BUTTON_WHEEL_UP and button_event.pressed:
			zoom_by_steps(1)
			get_viewport().set_input_as_handled()
			return
		if button_event.button_index == MOUSE_BUTTON_WHEEL_DOWN and button_event.pressed:
			zoom_by_steps(-1)
			get_viewport().set_input_as_handled()
			return
		if button_event.button_index == MOUSE_BUTTON_LEFT and button_event.pressed:
			_select_at_position(button_event.position)
			get_viewport().set_input_as_handled()


func set_zoom_level(value: float) -> void:
	_zoom_level = clampf(value, ZOOM_MIN, ZOOM_MAX)
	_update_layer_alpha()
	_update_focus_region()
	queue_redraw()


func zoom_by_steps(steps: int) -> void:
	if steps == 0:
		return
	set_zoom_level(_zoom_level + float(steps) * ZOOM_STEP)


func set_pointer_region_id(region_id: String) -> bool:
	if not region_id.is_empty() and not _region_area_by_id.has(region_id):
		return false
	_hovered_region_id = region_id
	_update_focus_region()
	queue_redraw()
	return true


func clear_pointer_region() -> void:
	_hovered_region_id = ""
	_update_focus_region()
	queue_redraw()


func select_region(region_id: String) -> bool:
	if region_id.is_empty() or not _region_area_by_id.has(region_id):
		return false
	_selected_region_id = region_id
	_selected_location_id = ""
	_selection_type = SELECTION_REGION
	_update_focus_region()
	queue_redraw()
	return true


func select_location(location_id: String) -> bool:
	var location: Dictionary = _location_by_id.get(location_id, {}) as Dictionary
	if location.is_empty():
		return false
	var parent_region_id := str(location.get("parent_region_id", ""))
	if parent_region_id.is_empty() or not _region_area_by_id.has(parent_region_id):
		return false
	_selected_region_id = parent_region_id
	_selected_location_id = location_id
	_selection_type = SELECTION_LOCATION
	_update_focus_region()
	queue_redraw()
	return true


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
	_draw_map(font, map_rect, base_size)
	_draw_legend(font, legend_rect, base_size)
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
	for area_type in ["plain", "forest", "hills", "river_valley", "wetland", "lake_region", "coastland", "rocky_wilds"]:
		var color := _area_type_color(area_type)
		draw_rect(Rect2(Vector2(rect.position.x + 14, y - 13), Vector2(18, 18)), color, true)
		draw_rect(Rect2(Vector2(rect.position.x + 14, y - 13), Vector2(18, 18)), Color(0.0, 0.0, 0.0, 0.28), false, 1.0)
		_draw_text(font, Vector2(rect.position.x + 40, y + 2), _area_type_label(area_type), font_size, TEXT_MAIN)
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
	if width <= 0 or height <= 0 or not _has_required_layer_maps():
		_draw_text(font, rect.position + Vector2(14, 28), "区域母图不可用。", font_size, TEXT_DIM)
		return

	_update_layer_alpha()
	_update_focus_region()
	var base_cell_size := minf(rect.size.x / float(width), rect.size.y / float(height))
	var cell_size := base_cell_size * _zoom_level
	var draw_size := Vector2(cell_size * float(width), cell_size * float(height))
	_map_draw_rect = _zoomed_map_rect(rect, draw_size, cell_size)
	_region_screen_positions.clear()

	for y in range(height):
		for x in range(width):
			var cell := Vector2i(x, y)
			var cell_data := _region_cell_layer_data(cell)
			var cell_rect := Rect2(
				_map_draw_rect.position + Vector2(float(x) * cell_size, float(y) * cell_size),
				Vector2(cell_size + 1.2, cell_size + 1.2)
			)
			draw_rect(cell_rect, _terrain_color_for_cell(cell_data, cell), true)

	draw_rect(_map_draw_rect, MAP_WASH, true)
	_draw_layer_textures(width, height, cell_size)
	_draw_region_boundaries(width, height, cell_size, maxf(0.18, _region_layer_alpha))

	_draw_focused_region_overlay(cell_size)
	_draw_region_adjacency_lines(cell_size, _region_layer_alpha)
	_draw_region_area_labels(font, font_size, cell_size, _region_layer_alpha)
	_draw_location_edges(cell_size, _location_layer_alpha)
	_draw_nodes(font, font_size, cell_size, _location_layer_alpha)
	if _region_layer_alpha <= LAYER_VISIBLE_EPSILON and _visible_location_ids().is_empty():
		_draw_text(font, rect.position + Vector2(14, 28), "没有可显示的区域地点。", font_size, TEXT_DIM)


func _has_required_layer_maps() -> bool:
	for map_key in [
		"elevation_map",
		"moisture_map",
		"water_map",
		"forest_map",
		"rock_map",
		"slope_map",
		"water_distance_map",
		"hydro_context_map",
		"landform_class_map",
		"vegetation_class_map",
		"surface_class_map",
	]:
		if (_region_map.get(map_key, []) as Array).is_empty():
			return false
	return true


func _draw_layer_textures(width: int, height: int, cell_size: float) -> void:
	if cell_size < 9.0:
		return
	for y in range(height):
		for x in range(width):
			var cell := Vector2i(x, y)
			var cell_data := _region_cell_layer_data(cell)
			var rect := _cell_rect(cell, cell_size)
			var hydro_context := str(cell_data.get("hydro_context", ""))
			var landform_class := str(cell_data.get("landform_class", ""))
			var vegetation_class := str(cell_data.get("vegetation_class", ""))
			var surface_class := str(cell_data.get("surface_class", ""))
			if hydro_context == "sea" or hydro_context == "lake_or_water":
				_draw_water_marks(rect, cell, cell_size, hydro_context == "sea")
			elif hydro_context == "near_sea":
				_draw_coast_marks(rect, cell, cell_size)
			elif vegetation_class == "forest":
				_draw_forest_marks(rect, cell, cell_size)
			elif landform_class == "hills" or landform_class == "highland" or landform_class == "mountain":
				_draw_hill_marks(rect, cell, cell_size)
			elif surface_class == "rock":
				_draw_rock_marks(rect, cell, cell_size)
			else:
				_draw_plain_marks(rect, cell, cell_size)


func _draw_region_boundaries(width: int, height: int, cell_size: float, alpha: float = 1.0) -> void:
	if alpha <= LAYER_VISIBLE_EPSILON:
		return
	var boundary_color := _with_alpha(REGION_BOUNDARY_COLOR, alpha)
	for y in range(height):
		for x in range(width):
			var cell := Vector2i(x, y)
			var region_id := _region_area_id_for_cell(cell)
			if x < width - 1 and _region_area_id_for_cell(Vector2i(x + 1, y)) != region_id:
				var px := _map_draw_rect.position.x + float(x + 1) * cell_size
				var y0 := _map_draw_rect.position.y + float(y) * cell_size
				draw_line(Vector2(px, y0), Vector2(px, y0 + cell_size), boundary_color, 1.2)
			if y < height - 1 and _region_area_id_for_cell(Vector2i(x, y + 1)) != region_id:
				var py := _map_draw_rect.position.y + float(y + 1) * cell_size
				var x0 := _map_draw_rect.position.x + float(x) * cell_size
				draw_line(Vector2(x0, py), Vector2(x0 + cell_size, py), boundary_color, 1.2)


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


func _draw_region_area_labels(font: Font, font_size: int, cell_size: float, alpha: float) -> void:
	if cell_size < 14.0 or alpha <= LAYER_VISIBLE_EPSILON:
		return
	var label_font_size: int = maxi(10, font_size - 3)
	for area_value in _region_areas:
		var area: Dictionary = area_value as Dictionary
		var center: Dictionary = area.get("center_position", {}) as Dictionary
		if not center.has("x") or not center.has("y"):
			continue
		var cell := Vector2i(int(center.get("x", -1)), int(center.get("y", -1)))
		var position := _map_draw_rect.position + Vector2((float(cell.x) + 0.5) * cell_size, (float(cell.y) + 0.5) * cell_size)
		var display_name := _region_area_display_name(area)
		if display_name.is_empty():
			continue
		var max_chars := 8
		var text := _truncate_line(display_name, max_chars)
		var text_size: Vector2 = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, label_font_size)
		var box_rect := Rect2(position - Vector2(text_size.x * 0.5 + 5.0, float(label_font_size) * 0.5 + 4.0), text_size + Vector2(10.0, 7.0))
		var region_id := str(area.get("region_id", ""))
		_region_screen_positions[region_id] = position
		draw_rect(box_rect, _with_alpha(Color(0.03, 0.04, 0.03, 0.30), alpha), true)
		var border_color := CURRENT_COLOR if str(area.get("region_id", "")) == _current_region_id else Color(0.95, 0.90, 0.58, 0.16)
		if region_id == _selected_region_id:
			border_color = SELECTED_COLOR
		elif region_id == _hovered_region_id:
			border_color = HOVER_COLOR
		draw_rect(box_rect, _with_alpha(border_color, alpha), false, 1.0)
		_draw_text(font, box_rect.position + Vector2(5.0, float(label_font_size) + 1.0), text, label_font_size, _with_alpha(Color(0.92, 0.91, 0.76, 0.82), alpha))


func _draw_location_edges(cell_size: float, alpha: float) -> void:
	if alpha <= LAYER_VISIBLE_EPSILON:
		return
	var drawn_pairs := {}
	for edge_value in _visible_location_edge_rows():
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
		_draw_route_line(from_pos, to_pos, pair_key, 1.0, alpha)


func _draw_nodes(font: Font, font_size: int, cell_size: float, alpha: float) -> void:
	if alpha <= LAYER_VISIBLE_EPSILON:
		return
	for location_value in _visible_location_rows():
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
			draw_arc(pos, 16.0, 0.0, TAU, 48, _with_alpha(SELECTED_COLOR, alpha), 2.0)
		if is_hovered:
			draw_arc(pos, 19.0, 0.0, TAU, 48, _with_alpha(HOVER_COLOR, alpha), 2.0)
		if is_current:
			_draw_current_marker(pos, 1.0, alpha)
		else:
			_draw_node_icon(pos, _location_area_type(location), false, alpha)
		_draw_node_label(font, location, pos, is_current, is_selected or is_hovered, font_size, cell_size, alpha)


func _draw_node_icon(position: Vector2, area_type: String, is_current: bool, alpha: float = 1.0) -> void:
	var radius := 8.0 if not is_current else 9.0
	draw_circle(position, radius + 2.2, _with_alpha(NODE_BORDER, alpha))
	draw_circle(position, radius, _with_alpha(CURRENT_COLOR if is_current else NODE_COLOR, alpha))
	_draw_node_symbol(position, area_type, is_current, alpha)


func _draw_node_symbol(position: Vector2, area_type: String, is_current: bool, alpha: float = 1.0) -> void:
	var color := Color(0.16, 0.20, 0.12, 0.92)
	if is_current:
		color = CURRENT_PIN
	color = _with_alpha(color, alpha)
	match area_type:
		"forest":
			var top := position + Vector2(0.0, -4.8)
			var tree := PackedVector2Array([
				top,
				position + Vector2(-4.8, 2.5),
				position + Vector2(4.8, 2.5),
			])
			draw_polygon(tree, PackedColorArray([color, color, color]))
			draw_line(position + Vector2(0.0, 2.0), position + Vector2(0.0, 5.4), color, 1.4)
		"river_valley", "wetland", "lake_region", "coastland":
			for index in range(2):
				var y := position.y - 2.4 + float(index) * 4.0
				draw_line(Vector2(position.x - 4.8, y), Vector2(position.x + 4.8, y + 1.2), color, 1.4)
		"hills", "highland", "mountain", "rocky_wilds":
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


func _draw_current_marker(position: Vector2, scale: float = 1.0, alpha: float = 1.0) -> void:
	var head := position + Vector2(0.0, -11.0 * scale)
	var left := head + Vector2(-5.8 * scale, 6.8 * scale)
	var right := head + Vector2(5.8 * scale, 6.8 * scale)
	var shadow := _with_alpha(Color(0.0, 0.0, 0.0, 0.34), alpha)
	var pin := _with_alpha(CURRENT_PIN, alpha)
	draw_circle(head + Vector2(1.6 * scale, 2.0 * scale), 9.8 * scale, shadow)
	draw_polygon(PackedVector2Array([position, left + Vector2(1.6 * scale, 2.0 * scale), right + Vector2(1.6 * scale, 2.0 * scale)]), PackedColorArray([shadow, shadow, shadow]))
	draw_polygon(PackedVector2Array([position, left, right]), PackedColorArray([pin, pin, pin]))
	draw_circle(head, 9.4 * scale, pin)
	draw_circle(head, 5.0 * scale, _with_alpha(Color(0.96, 0.98, 1.0, 1.0), alpha))
	draw_circle(head, 2.6 * scale, _with_alpha(Color(0.12, 0.34, 0.78, 1.0), alpha))


func _draw_info(font: Font, rect: Rect2, font_size: int) -> void:
	draw_rect(rect, Color(0.07, 0.085, 0.065, 0.88), true)
	draw_rect(rect, PANEL_BORDER, false, 1.0)
	var info_type := _active_info_type()
	_draw_text(font, rect.position + Vector2(12, 24), "地点信息" if info_type == SELECTION_LOCATION else "区域信息", font_size + 3, TEXT_MAIN)

	if info_type == SELECTION_LOCATION:
		_draw_location_info(font, rect, font_size)
	else:
		_draw_region_info(font, rect, font_size)


func _draw_region_info(font: Font, rect: Rect2, font_size: int) -> void:
	var region_id := _selected_region_id
	if not _hovered_region_id.is_empty() and _region_area_by_id.has(_hovered_region_id):
		region_id = _hovered_region_id
	elif region_id.is_empty() or not _region_area_by_id.has(region_id):
		region_id = _focused_region_id
	var area: Dictionary = _region_area_by_id.get(region_id, {}) as Dictionary
	if area.is_empty():
		_draw_lines(font, Rect2(rect.position + Vector2(12, 56), rect.size - Vector2(24, 64)), ["暂无选中区域。"], font_size, TEXT_DIM)
		return

	var lines: Array[String] = []
	lines.append("区域名称：%s" % _region_area_display_name(area))
	lines.append("区域类型：%s" % _area_type_label(str(area.get("area_type", ""))))
	lines.append("包含地点：%d" % _locations_for_region(region_id).size())
	lines.append("当前区域：%s" % ("是" if region_id == _current_region_id else "否"))
	var features := _region_feature_labels(area)
	lines.append("区域特征：%s" % ("无" if features.is_empty() else _join_strings(features, "、")))
	lines.append("")
	lines.append("相邻区域：")
	var adjacent_names := _adjacent_region_names(area)
	if adjacent_names.is_empty():
		lines.append("无")
	else:
		for name in adjacent_names:
			lines.append("- %s" % name)
	_draw_lines(font, Rect2(rect.position + Vector2(12, 56), rect.size - Vector2(24, 64)), lines, font_size, TEXT_MAIN)


func _draw_location_info(font: Font, rect: Rect2, font_size: int) -> void:
	var location_id := _selected_location_id
	if not _hovered_location_id.is_empty():
		location_id = _hovered_location_id
	var location: Dictionary = _location_by_id.get(location_id, {}) as Dictionary
	if location.is_empty():
		_draw_lines(font, Rect2(rect.position + Vector2(12, 56), rect.size - Vector2(24, 64)), ["暂无选中地点。"], font_size, TEXT_DIM)
		return

	var lines: Array[String] = []
	var display_name := _location_display_name(location)
	lines.append("名称：%s" % display_name)
	var parent_region_id := str(location.get("parent_region_id", ""))
	if not parent_region_id.is_empty():
		var parent_area: Dictionary = _region_area_by_id.get(parent_region_id, {}) as Dictionary
		lines.append("所属区域：%s" % _region_area_display_name(parent_area))
	lines.append("区域类型：%s" % _area_type_label(_location_area_type(location)))
	var local_role := str(location.get("local_role", ""))
	if not local_role.is_empty():
		lines.append("节点角色：%s" % _local_role_label(local_role))
	var profile_id := str(location.get("generator_profile_id", ""))
	if not profile_id.is_empty():
		lines.append("生成模板：%s" % profile_id)
	lines.append("地点 ID：%s" % location_id)
	if location_id == _display_current_location_id:
		lines.append("当前位置：是")
	elif _current_location_id == location_id:
		lines.append("当前位置：是")
	else:
		lines.append("当前位置：否")
	if _current_location_id != _display_current_location_id and location_id == _display_current_location_id:
		lines.append("当前子地点：%s" % _current_location_id)
	var connections := _connection_names(location_id, true)
	lines.append("")
	lines.append("连接地点：")
	if connections.is_empty():
		lines.append("无")
	else:
		for name in connections:
			lines.append("- %s" % name)
	_draw_lines(font, Rect2(rect.position + Vector2(12, 56), rect.size - Vector2(24, 64)), lines, font_size, TEXT_MAIN)


func _draw_route_line(from_pos: Vector2, to_pos: Vector2, route_key: String, scale: float = 1.0, alpha: float = 1.0) -> void:
	var points := PackedVector2Array()
	var control := _route_control_point(from_pos, to_pos, route_key)
	var segments: int = 28
	for index in range(segments + 1):
		var t := float(index) / float(segments)
		points.append(_quadratic_point(from_pos, control, to_pos, t))

	draw_polyline(points, _with_alpha(ROAD_SHADOW_COLOR, alpha), maxf(1.0, 7.0 * scale), true)
	draw_polyline(points, _with_alpha(ROAD_EDGE_COLOR, alpha), maxf(1.0, 3.2 * scale), true)

	var length := from_pos.distance_to(to_pos)
	var dot_count: int = maxi(2, int(length / maxf(8.0, 13.0 * scale)))
	for index in range(dot_count + 1):
		var t := float(index) / float(dot_count)
		var dot := _quadratic_point(from_pos, control, to_pos, t)
		draw_circle(dot, maxf(1.0, 1.9 * scale), _with_alpha(ROAD_CENTER_COLOR, alpha))


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


func _zoomed_map_rect(container_rect: Rect2, draw_size: Vector2, cell_size: float) -> Rect2:
	var focus_cell := _focus_cell()
	var focus_screen := container_rect.position + container_rect.size * 0.5
	var origin := focus_screen - Vector2((float(focus_cell.x) + 0.5) * cell_size, (float(focus_cell.y) + 0.5) * cell_size)
	if draw_size.x <= container_rect.size.x:
		origin.x = container_rect.position.x + (container_rect.size.x - draw_size.x) * 0.5
	else:
		origin.x = clampf(origin.x, container_rect.position.x + container_rect.size.x - draw_size.x, container_rect.position.x)
	if draw_size.y <= container_rect.size.y:
		origin.y = container_rect.position.y + (container_rect.size.y - draw_size.y) * 0.5
	else:
		origin.y = clampf(origin.y, container_rect.position.y + container_rect.size.y - draw_size.y, container_rect.position.y)
	return Rect2(origin, draw_size)


func _focus_cell() -> Vector2i:
	var area: Dictionary = _region_area_by_id.get(_focused_region_id, {}) as Dictionary
	var center: Dictionary = area.get("center_position", {}) as Dictionary
	if center.has("x") and center.has("y"):
		return Vector2i(int(center.get("x", 0)), int(center.get("y", 0)))
	var location: Dictionary = _location_by_id.get(_display_current_location_id, {}) as Dictionary
	var position: Dictionary = location.get("region_position", {}) as Dictionary
	if position.has("x") and position.has("y"):
		return Vector2i(int(position.get("x", 0)), int(position.get("y", 0)))
	return Vector2i(int(_region_map.get("width", 1)) / 2, int(_region_map.get("height", 1)) / 2)


func _draw_focused_region_overlay(cell_size: float) -> void:
	if _focused_region_id.is_empty():
		return
	var area: Dictionary = _region_area_by_id.get(_focused_region_id, {}) as Dictionary
	if area.is_empty():
		return
	var fill_alpha := maxf(_location_layer_alpha * 0.45, _region_layer_alpha * 0.25)
	var border_alpha := maxf(_location_layer_alpha * 0.80, _region_layer_alpha * 0.45)
	for cell_value in (area.get("cells", []) as Array):
		var cell := _cell_from_dict(cell_value as Dictionary)
		var cell_rect := _cell_rect(cell, cell_size)
		draw_rect(cell_rect, _with_alpha(FOCUSED_REGION_FILL, fill_alpha), true)
	for cell_value in (area.get("cells", []) as Array):
		var cell := _cell_from_dict(cell_value as Dictionary)
		var cell_rect := _cell_rect(cell, cell_size)
		for offset in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var neighbor: Vector2i = cell + offset
			if _region_area_id_for_cell(neighbor) == _focused_region_id:
				continue
			if offset == Vector2i.LEFT:
				draw_line(cell_rect.position, cell_rect.position + Vector2(0.0, cell_rect.size.y), _with_alpha(FOCUSED_REGION_BORDER, border_alpha), 1.6)
			elif offset == Vector2i.RIGHT:
				var x := cell_rect.position.x + cell_rect.size.x
				draw_line(Vector2(x, cell_rect.position.y), Vector2(x, cell_rect.position.y + cell_rect.size.y), _with_alpha(FOCUSED_REGION_BORDER, border_alpha), 1.6)
			elif offset == Vector2i.UP:
				draw_line(cell_rect.position, cell_rect.position + Vector2(cell_rect.size.x, 0.0), _with_alpha(FOCUSED_REGION_BORDER, border_alpha), 1.6)
			elif offset == Vector2i.DOWN:
				var y := cell_rect.position.y + cell_rect.size.y
				draw_line(Vector2(cell_rect.position.x, y), Vector2(cell_rect.position.x + cell_rect.size.x, y), _with_alpha(FOCUSED_REGION_BORDER, border_alpha), 1.6)


func _draw_region_adjacency_lines(cell_size: float, alpha: float) -> void:
	if alpha <= LAYER_VISIBLE_EPSILON:
		return
	var drawn_pairs := {}
	for area_value in _region_areas:
		var area: Dictionary = area_value as Dictionary
		var from_id := str(area.get("region_id", ""))
		var from_pos := _screen_position_for_region_area(from_id, cell_size)
		if not _is_valid_screen_position(from_pos):
			continue
		for adjacent_value in (area.get("adjacent_region_ids", []) as Array):
			var to_id := str(adjacent_value)
			var pair_key := _pair_key(from_id, to_id)
			if drawn_pairs.has(pair_key):
				continue
			var to_pos := _screen_position_for_region_area(to_id, cell_size)
			if not _is_valid_screen_position(to_pos):
				continue
			drawn_pairs[pair_key] = true
			draw_line(from_pos, to_pos, _with_alpha(REGION_ADJACENCY_COLOR, alpha), 1.2)


func _screen_position_for_region_area(region_id: String, cell_size: float) -> Vector2:
	var area: Dictionary = _region_area_by_id.get(region_id, {}) as Dictionary
	var center: Dictionary = area.get("center_position", {}) as Dictionary
	if not center.has("x") or not center.has("y"):
		return Vector2(-100000.0, -100000.0)
	return _map_draw_rect.position + Vector2((float(center.get("x", 0)) + 0.5) * cell_size, (float(center.get("y", 0)) + 0.5) * cell_size)


func _select_at_position(position: Vector2) -> void:
	var clicked_location := ""
	if _location_layer_alpha >= _region_layer_alpha:
		clicked_location = _location_at_position(position)
	if not clicked_location.is_empty():
		select_location(clicked_location)
		return
	var clicked_region := _region_at_position(position)
	if not clicked_region.is_empty():
		select_region(clicked_region)
		return
	if _location_layer_alpha < _region_layer_alpha:
		clicked_location = _location_at_position(position)
		if not clicked_location.is_empty():
			select_location(clicked_location)


func _active_info_type() -> String:
	if _location_layer_alpha >= 0.50 and _selection_type == SELECTION_LOCATION:
		var location: Dictionary = _location_by_id.get(_selected_location_id, {}) as Dictionary
		if str(location.get("parent_region_id", "")) == _focused_region_id:
			return SELECTION_LOCATION
	return SELECTION_REGION


func _update_layer_alpha() -> void:
	var t := smoothstep(ZOOM_LAYER_BLEND_START, ZOOM_LAYER_BLEND_END, _zoom_level)
	_location_layer_alpha = clampf(t, 0.0, 1.0)
	_region_layer_alpha = clampf(1.0 - t, 0.0, 1.0)


func _update_focus_region() -> void:
	_update_layer_alpha()
	_focused_region_id = _choose_focused_region_id()


func _choose_focused_region_id() -> String:
	if not _hovered_region_id.is_empty() and _region_area_by_id.has(_hovered_region_id):
		return _hovered_region_id
	if not _current_region_id.is_empty() and _region_area_by_id.has(_current_region_id):
		return _current_region_id
	if not _selected_region_id.is_empty() and _region_area_by_id.has(_selected_region_id):
		return _selected_region_id
	return _first_region_area_id()


func _first_region_area_id() -> String:
	if _region_areas.is_empty():
		return ""
	var area: Dictionary = _region_areas[0] as Dictionary
	return str(area.get("region_id", ""))


func _visible_region_area_ids() -> Array[String]:
	var result: Array[String] = []
	if _region_layer_alpha <= LAYER_VISIBLE_EPSILON:
		return result
	for area_value in _region_areas:
		var area: Dictionary = area_value as Dictionary
		var region_id := str(area.get("region_id", ""))
		if not region_id.is_empty():
			result.append(region_id)
	return result


func _visible_location_rows() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if _location_layer_alpha <= LAYER_VISIBLE_EPSILON or _focused_region_id.is_empty():
		return result
	for location_value in _locations:
		var location: Dictionary = location_value as Dictionary
		if str(location.get("parent_region_id", "")) == _focused_region_id:
			result.append(location)
	return result


func _visible_location_ids() -> Array[String]:
	var result: Array[String] = []
	for location in _visible_location_rows():
		var location_id := str(location.get("location_id", ""))
		if not location_id.is_empty():
			result.append(location_id)
	return result


func _visible_location_edge_rows() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if _location_layer_alpha <= LAYER_VISIBLE_EPSILON or _focused_region_id.is_empty():
		return result
	for edge_value in _edges:
		var edge: Dictionary = edge_value as Dictionary
		if str(edge.get("edge_scope", "")) != "internal_region":
			continue
		if str(edge.get("from_region_id", "")) != _focused_region_id or str(edge.get("target_region_id", "")) != _focused_region_id:
			continue
		result.append(edge)
	return result


func _visible_location_edge_ids() -> Array[String]:
	var result: Array[String] = []
	for edge in _visible_location_edge_rows():
		var edge_id := str(edge.get("exit_id", ""))
		if not edge_id.is_empty():
			result.append(edge_id)
	return result


func _visible_region_adjacency_ids() -> Array[String]:
	var result: Array[String] = []
	if _region_layer_alpha <= LAYER_VISIBLE_EPSILON:
		return result
	var seen := {}
	for area_value in _region_areas:
		var area: Dictionary = area_value as Dictionary
		var from_id := str(area.get("region_id", ""))
		for adjacent_value in (area.get("adjacent_region_ids", []) as Array):
			var pair_key := _pair_key(from_id, str(adjacent_value))
			if seen.has(pair_key):
				continue
			seen[pair_key] = true
			result.append(pair_key)
	return result


func _draw_node_label(
	font: Font,
	location: Dictionary,
	node_position: Vector2,
	is_current: bool,
	is_emphasized: bool,
	font_size: int,
	cell_size: float,
	alpha: float = 1.0
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
	draw_rect(box_rect, _with_alpha(NODE_LABEL_BG, alpha), true)
	draw_rect(box_rect, _with_alpha(CURRENT_COLOR if is_current else NODE_LABEL_BORDER, alpha), false, 1.0)
	_draw_text(font, box_rect.position + Vector2(4.0, float(label_font_size) + 1.0), label, label_font_size, _with_alpha(CURRENT_COLOR if is_current else TEXT_MAIN, alpha))


func _location_display_name(location: Dictionary) -> String:
	var location_id := str(location.get("location_id", ""))
	var display_name := str(location.get("display_name", ""))
	return display_name if not display_name.is_empty() else location_id


func _location_area_type(location: Dictionary) -> String:
	var area_type := str(location.get("area_type", ""))
	if not area_type.is_empty():
		return area_type
	var parent_region_id := str(location.get("parent_region_id", ""))
	var parent_area: Dictionary = _region_area_by_id.get(parent_region_id, {}) as Dictionary
	return str(parent_area.get("area_type", "plain"))


func _location_at_position(position: Vector2) -> String:
	if _location_layer_alpha <= LAYER_VISIBLE_EPSILON:
		return ""
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


func _region_at_position(position: Vector2) -> String:
	if _map_draw_rect.size.x <= 0.0 or _map_draw_rect.size.y <= 0.0:
		return ""
	if not _map_draw_rect.has_point(position):
		return ""
	var width := int(_region_map.get("width", 0))
	var height := int(_region_map.get("height", 0))
	if width <= 0 or height <= 0:
		return ""
	var cell_size := _map_draw_rect.size.x / float(width)
	if cell_size <= 0.0:
		return ""
	var cell := Vector2i(
		int(floor((position.x - _map_draw_rect.position.x) / cell_size)),
		int(floor((position.y - _map_draw_rect.position.y) / cell_size))
	)
	return _region_area_id_for_cell(cell)


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


func _connection_names(location_id: String, same_region_only: bool = false) -> Array[String]:
	var result: Array[String] = []
	var seen := {}
	var location: Dictionary = _location_by_id.get(location_id, {}) as Dictionary
	var parent_region_id := str(location.get("parent_region_id", ""))
	for edge_value in _edges:
		var edge: Dictionary = edge_value as Dictionary
		var other_id := ""
		if str(edge.get("from_location_id", "")) == location_id:
			other_id = str(edge.get("target_location_id", ""))
		elif str(edge.get("target_location_id", "")) == location_id:
			other_id = str(edge.get("from_location_id", ""))
		if other_id.is_empty() or seen.has(other_id):
			continue
		if same_region_only:
			var other_location: Dictionary = _location_by_id.get(other_id, {}) as Dictionary
			if str(other_location.get("parent_region_id", "")) != parent_region_id:
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


func _build_region_area_index() -> void:
	_region_area_by_id.clear()
	_region_cell_owner_by_key.clear()
	for area_value in _region_areas:
		var area: Dictionary = area_value as Dictionary
		var region_id := str(area.get("region_id", ""))
		if not region_id.is_empty():
			_region_area_by_id[region_id] = area
		for cell_value in (area.get("cells", []) as Array):
			var cell := _cell_from_dict(cell_value as Dictionary)
			_region_cell_owner_by_key[_position_key(cell)] = region_id


func _region_area_id_for_cell(cell: Vector2i) -> String:
	return str(_region_cell_owner_by_key.get(_position_key(cell), ""))


func _locations_for_region(region_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if region_id.is_empty():
		return result
	for location_value in _locations:
		var location: Dictionary = location_value as Dictionary
		if str(location.get("parent_region_id", "")) == region_id:
			result.append(location)
	return result


func _adjacent_region_names(area: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for adjacent_value in (area.get("adjacent_region_ids", []) as Array):
		var adjacent_id := str(adjacent_value)
		var adjacent_area: Dictionary = _region_area_by_id.get(adjacent_id, {}) as Dictionary
		if not adjacent_area.is_empty():
			result.append(_region_area_display_name(adjacent_area))
	result.sort()
	return result


func _region_feature_labels(area: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for feature_value in (area.get("features", []) as Array):
		var feature := str(feature_value)
		match feature:
			"near_sea":
				result.append("近海")
			"near_river":
				result.append("近河")
			"high_moisture":
				result.append("高湿度")
			"dense_forest":
				result.append("密林")
			"rocky_slope":
				result.append("岩坡")
			_:
				if not feature.is_empty():
					result.append(feature)
	return result


func _region_area_display_name(area: Dictionary) -> String:
	if area.is_empty():
		return "未知区域"
	var display_name := str(area.get("display_name", ""))
	if not display_name.is_empty():
		return display_name
	return str(area.get("region_id", "未知区域"))


func _local_role_label(local_role: String) -> String:
	match local_role:
		"field_entry":
			return "野地入口"
		"forest_entrance":
			return "森林入口"
		"foothill_entrance":
			return "山脚入口"
		"riverbank_entry":
			return "河岸入口"
		"shoreline_entry":
			return "海岸入口"
		"path":
			return "路径"
		"forest_path":
			return "林间小路"
		"wetland_path":
			return "湿地小路"
		"rocky_slope_path":
			return "岩坡小径"
		"clearing":
			return "空地"
		"creek_side":
			return "溪流边"
		"deep_area":
			return "深处"
		"special_site":
			return "遗迹"
		_:
			return local_role


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


func _cell_from_dict(value: Dictionary) -> Vector2i:
	return Vector2i(int(value.get("x", -1)), int(value.get("y", -1)))


func _cell_rect(cell: Vector2i, cell_size: float) -> Rect2:
	return Rect2(
		_map_draw_rect.position + Vector2(float(cell.x) * cell_size, float(cell.y) * cell_size),
		Vector2(cell_size, cell_size)
	)


func _position_key(cell: Vector2i) -> String:
	return "%d,%d" % [cell.x, cell.y]


func _map_string(map_data: Array, cell: Vector2i) -> String:
	if cell.y < 0 or cell.y >= map_data.size():
		return ""
	var row: Array = map_data[cell.y] as Array
	if cell.x < 0 or cell.x >= row.size():
		return ""
	return str(row[cell.x])


func _map_float(map_data: Array, cell: Vector2i) -> float:
	if cell.y < 0 or cell.y >= map_data.size():
		return 0.0
	var row: Array = map_data[cell.y] as Array
	if cell.x < 0 or cell.x >= row.size():
		return 0.0
	return float(row[cell.x])


func _region_cell_layer_data(cell: Vector2i) -> Dictionary:
	return {
		"elevation": _map_float(_region_map.get("elevation_map", []) as Array, cell),
		"moisture": _map_float(_region_map.get("moisture_map", []) as Array, cell),
		"water": _map_float(_region_map.get("water_map", []) as Array, cell),
		"forest": _map_float(_region_map.get("forest_map", []) as Array, cell),
		"rock": _map_float(_region_map.get("rock_map", []) as Array, cell),
		"slope": _map_float(_region_map.get("slope_map", []) as Array, cell),
		"water_distance": _map_float(_region_map.get("water_distance_map", []) as Array, cell),
		"hydro_context": _map_string(_region_map.get("hydro_context_map", []) as Array, cell),
		"landform_class": _map_string(_region_map.get("landform_class_map", []) as Array, cell),
		"vegetation_class": _map_string(_region_map.get("vegetation_class_map", []) as Array, cell),
		"surface_class": _map_string(_region_map.get("surface_class_map", []) as Array, cell),
	}


func _area_type_label(area_type: String) -> String:
	return str(AREA_TYPE_LABELS.get(area_type, "未知区域类型"))


func _terrain_color_for_cell(cell_data: Dictionary, cell: Vector2i) -> Color:
	var area_type := _area_type_for_cell(cell)
	var base := _area_type_color(area_type)
	var hydro_context := str(cell_data.get("hydro_context", ""))
	var landform_class := str(cell_data.get("landform_class", ""))
	var vegetation_class := str(cell_data.get("vegetation_class", ""))
	var surface_class := str(cell_data.get("surface_class", ""))
	var water := clampf(float(cell_data.get("water", 0.0)), 0.0, 1.0)
	var moisture := clampf(float(cell_data.get("moisture", 0.0)), 0.0, 1.0)
	var forest := clampf(float(cell_data.get("forest", 0.0)), 0.0, 1.0)
	var rock := clampf(float(cell_data.get("rock", 0.0)), 0.0, 1.0)
	if hydro_context == "sea" or hydro_context == "lake_or_water":
		base = base.lerp(Color(0.08, 0.30, 0.50, 1.0), 0.65 + water * 0.25)
	elif hydro_context == "near_sea":
		base = base.lerp(Color(0.70, 0.62, 0.38, 1.0), 0.35)
	elif hydro_context == "near_water":
		base = base.lerp(Color(0.20, 0.50, 0.48, 1.0), 0.22 + moisture * 0.14)
	if vegetation_class == "forest":
		base = base.lerp(Color(0.12, 0.34, 0.18, 1.0), 0.25 + forest * 0.22)
	elif vegetation_class == "wetland":
		base = base.lerp(Color(0.20, 0.42, 0.34, 1.0), 0.22)
	elif vegetation_class == "sparse":
		base = base.lerp(Color(0.50, 0.52, 0.33, 1.0), 0.14)
	if landform_class == "hills" or landform_class == "highland" or landform_class == "mountain":
		base = base.lerp(Color(0.42, 0.39, 0.29, 1.0), 0.18)
	if surface_class == "rock":
		base = base.lerp(Color(0.45, 0.45, 0.40, 1.0), 0.22 + rock * 0.14)
	elif surface_class == "sand":
		base = base.lerp(Color(0.70, 0.63, 0.42, 1.0), 0.18)
	var amount := (_map_noise(cell, 17) - 0.5) * 0.16
	return _scale_color(base, 1.0 + amount)


func _area_type_for_cell(cell: Vector2i) -> String:
	var region_id := _region_area_id_for_cell(cell)
	var area: Dictionary = _region_area_by_id.get(region_id, {}) as Dictionary
	return str(area.get("area_type", "plain"))


func _area_type_color(area_type: String) -> Color:
	return AREA_TYPE_COLORS.get(area_type, UNKNOWN_AREA_COLOR) as Color


func _scale_color(color: Color, factor: float) -> Color:
	return Color(
		clampf(color.r * factor, 0.0, 1.0),
		clampf(color.g * factor, 0.0, 1.0),
		clampf(color.b * factor, 0.0, 1.0),
		color.a
	)


func _with_alpha(color: Color, alpha: float) -> Color:
	return Color(color.r, color.g, color.b, clampf(color.a * alpha, 0.0, 1.0))


func _join_strings(values: Array[String], separator: String) -> String:
	var result := ""
	for index in range(values.size()):
		if index > 0:
			result += separator
		result += values[index]
	return result


func _round3(value: float) -> float:
	return snappedf(value, 0.001)


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

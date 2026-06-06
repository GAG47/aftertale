class_name CharacterAppearanceRenderer
extends RefCounted

const CANVAS_SIZE := Vector2(64.0, 64.0)
const GRID_ANCHOR := Vector2(32.0, 46.0)

static var _texture_cache: Dictionary = {}


static func draw_character(canvas: CanvasItem, context: Dictionary) -> void:
	var appearance: Dictionary = _dictionary(context.get("appearance", {}))
	if not _draw_texture_layer(canvas, appearance, "shadow"):
		_draw_shadow(canvas)

	if bool(context.get("is_training_dummy", false)):
		_draw_training_dummy(canvas)
		return

	if str(appearance.get("display_mode", "modular")) == "badge":
		_draw_badge_mode(canvas, appearance)
		return

	_draw_texture_layer(canvas, appearance, "body")
	_draw_texture_layer(canvas, appearance, "outfit")
	_draw_texture_layer(canvas, appearance, "head")
	_draw_texture_layer(canvas, appearance, "face")
	_draw_texture_layer(canvas, appearance, "hair")
	_draw_texture_layer(canvas, appearance, "accessory")
	_draw_texture_layer(canvas, appearance, "held_item")


static func _draw_shadow(canvas: CanvasItem) -> void:
	_draw_ellipse(canvas, Vector2(0.0, 8.8), Vector2(24.0, 6.5), Color(0.0, 0.0, 0.0, 0.20))


static func _draw_badge_mode(canvas: CanvasItem, appearance: Dictionary) -> bool:
	var source: String = str(appearance.get("badge_source", ""))
	if source.is_empty():
		var portrait: Dictionary = _dictionary(appearance.get("portrait", {}))
		source = str(portrait.get("badge", ""))
	if source.is_empty():
		return false

	var texture: Texture2D = _load_layer_texture(source)
	if texture == null:
		return false

	var offset_data: Dictionary = _dictionary(appearance.get("badge_offset", {}))
	var center := Vector2(float(offset_data.get("x", 0.0)), float(offset_data.get("y", 0.0)))
	var size_value: float = float(appearance.get("badge_size", 28.0))
	var size := Vector2(size_value, size_value)
	var rect := Rect2(center - size * 0.5, size)
	canvas.draw_texture_rect(texture, rect, false)

	var ring_color: Color = _color_from_value(appearance.get("badge_ring", "#3b2e22"), Color(0.23, 0.18, 0.13))
	var highlight_color: Color = _color_from_value(appearance.get("badge_highlight", "#f2d999"), Color(0.95, 0.82, 0.52))
	canvas.draw_arc(center, size_value * 0.5 + 0.2, 0.0, TAU, 64, ring_color, 1.8)
	canvas.draw_arc(center, size_value * 0.5 - 1.8, -PI * 0.85, -PI * 0.15, 24, highlight_color, 1.2)
	return true


static func _draw_training_dummy(canvas: CanvasItem) -> void:
	var wood: Color = Color(0.70, 0.46, 0.22)
	var dark: Color = Color(0.24, 0.13, 0.06)
	canvas.draw_line(Vector2(0.0, 8.0), Vector2(0.0, -13.0), dark, 4.8)
	canvas.draw_line(Vector2(0.0, 8.0), Vector2(0.0, -13.0), wood, 3.0)
	canvas.draw_line(Vector2(-9.0, -2.0), Vector2(9.0, -2.0), dark, 4.2)
	canvas.draw_line(Vector2(-9.0, -2.0), Vector2(9.0, -2.0), Color(0.82, 0.60, 0.32), 2.5)
	canvas.draw_circle(Vector2(0.0, -13.0), 6.8, Color(0.78, 0.56, 0.29))
	canvas.draw_arc(Vector2(0.0, -13.0), 7.0, 0.0, TAU, 20, dark, 1.4)
	canvas.draw_line(Vector2(-3.0, -14.5), Vector2(-0.8, -12.2), dark, 1.2)
	canvas.draw_line(Vector2(3.0, -14.5), Vector2(0.8, -12.2), dark, 1.2)


static func _draw_texture_layer(canvas: CanvasItem, appearance: Dictionary, layer_id: String) -> bool:
	var layer_data: Dictionary = _texture_layer_data(appearance, layer_id)
	var source: String = str(layer_data.get("source", layer_data.get("path", "")))
	if source.is_empty():
		return false

	var texture: Texture2D = _load_layer_texture(source)
	if texture == null:
		return false

	var offset_data: Dictionary = _dictionary(layer_data.get("offset", {}))
	var offset := Vector2(float(offset_data.get("x", 0.0)), float(offset_data.get("y", 0.0)))
	var size: Vector2 = CANVAS_SIZE
	var size_data: Dictionary = _dictionary(layer_data.get("size", {}))
	if not size_data.is_empty():
		size = Vector2(float(size_data.get("x", CANVAS_SIZE.x)), float(size_data.get("y", CANVAS_SIZE.y)))
	elif layer_data.has("scale"):
		var scale_value: float = float(layer_data.get("scale", 1.0))
		size = CANVAS_SIZE * scale_value
	var modulate: Color = _color_from_value(layer_data.get("modulate", "#ffffffff"), Color.WHITE)
	canvas.draw_texture_rect(texture, Rect2(-GRID_ANCHOR + offset, size), false, modulate)
	return true


static func _load_layer_texture(source: String) -> Texture2D:
	if _texture_cache.has(source):
		return _texture_cache.get(source, null) as Texture2D
	if ResourceLoader.exists(source):
		var loaded_texture: Texture2D = load(source) as Texture2D
		_texture_cache[source] = loaded_texture
		return loaded_texture
	if source.begins_with("res://") and not FileAccess.file_exists(source):
		_texture_cache[source] = null
		return null

	var image := Image.new()
	var error: Error = image.load(source)
	if error == OK:
		var image_texture: ImageTexture = ImageTexture.create_from_image(image)
		_texture_cache[source] = image_texture
		return image_texture

	var imported_texture: Texture2D = load(source) as Texture2D
	_texture_cache[source] = imported_texture
	return imported_texture


static func _texture_layer_data(appearance: Dictionary, layer_id: String) -> Dictionary:
	var layers: Dictionary = _dictionary(appearance.get("layers", {}))
	return _dictionary(layers.get(layer_id, {}))


static func _color_from_value(value: Variant, fallback: Color) -> Color:
	var text: String = str(value)
	if text.is_empty():
		return fallback
	return Color.from_string(text, fallback)


static func _draw_ellipse(canvas: CanvasItem, center: Vector2, size: Vector2, color: Color) -> void:
	var points := PackedVector2Array()
	var steps: int = 24
	for index in range(steps):
		var angle: float = TAU * float(index) / float(steps)
		points.append(center + Vector2(cos(angle) * size.x * 0.5, sin(angle) * size.y * 0.5))
	_draw_polygon(canvas, points, color)


static func _draw_ellipse_outline(canvas: CanvasItem, center: Vector2, size: Vector2, color: Color, width: float) -> void:
	var points := PackedVector2Array()
	var steps: int = 24
	for index in range(steps):
		var angle: float = TAU * float(index) / float(steps)
		points.append(center + Vector2(cos(angle) * size.x * 0.5, sin(angle) * size.y * 0.5))
	points.append(points[0])
	canvas.draw_polyline(points, color, width)


static func _draw_polygon(canvas: CanvasItem, points: PackedVector2Array, color: Color) -> void:
	var colors := PackedColorArray()
	for _index in range(points.size()):
		colors.append(color)
	canvas.draw_polygon(points, colors)


static func _dictionary(value: Variant) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return {}
	return value as Dictionary

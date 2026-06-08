class_name CharacterAppearanceRenderer
extends RefCounted

const CANVAS_SIZE := Vector2(64.0, 64.0)
const GRID_ANCHOR := Vector2(32.0, 46.0)

static var _texture_cache: Dictionary = {}
static var _map_sprite_texture_cache: Dictionary = {}


static func draw_character(canvas: CanvasItem, context: Dictionary) -> void:
	var appearance: Dictionary = _dictionary(context.get("appearance", {}))
	if not _draw_texture_layer(canvas, appearance, "shadow"):
		_draw_shadow(canvas)

	if bool(context.get("is_training_dummy", false)):
		_draw_training_dummy(canvas)
		return

	var display_mode: String = str(appearance.get("display_mode", "modular"))
	if display_mode == "map_sprite":
		if _draw_map_sprite(canvas, appearance):
			return
		_draw_map_sprite_placeholder(canvas)
		return

	_draw_texture_layer(canvas, appearance, "body")
	_draw_texture_layer(canvas, appearance, "outfit")
	_draw_texture_layer(canvas, appearance, "head")
	_draw_texture_layer(canvas, appearance, "face")
	_draw_texture_layer(canvas, appearance, "hair")
	_draw_texture_layer(canvas, appearance, "accessory")
	_draw_texture_layer(canvas, appearance, "held_item")


static func _draw_map_sprite(canvas: CanvasItem, appearance: Dictionary) -> bool:
	var map_sprite: Dictionary = _dictionary(appearance.get("map_sprite", {}))
	var source: String = str(map_sprite.get("source", ""))
	if source.is_empty():
		return false

	var texture: Texture2D = _load_map_sprite_texture(source)
	if texture == null:
		return false

	var scale_value: float = maxf(0.001, float(map_sprite.get("scale", 0.034)))
	var size: Vector2 = texture.get_size() * scale_value
	var offset_data: Dictionary = _dictionary(map_sprite.get("offset", {}))
	var offset := Vector2(
		float(offset_data.get("x", 0.0)),
		float(offset_data.get("y", 0.0))
	)
	var anchor_data: Dictionary = _dictionary(map_sprite.get("anchor", {}))
	var anchor_ratio := Vector2(
		float(anchor_data.get("x", 0.5)),
		float(anchor_data.get("y", 0.94))
	)
	var anchor: Vector2 = size * anchor_ratio
	var modulate: Color = _color_from_value(map_sprite.get("modulate", "#ffffffff"), Color.WHITE)
	canvas.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	canvas.draw_texture_rect(texture, Rect2(offset - anchor, size), false, modulate)
	return true


static func _draw_map_sprite_placeholder(canvas: CanvasItem) -> void:
	canvas.draw_circle(Vector2(0.0, -10.0), 7.5, Color(0.55, 0.58, 0.62, 0.95))
	canvas.draw_rect(Rect2(Vector2(-6.5, -3.5), Vector2(13.0, 18.0)), Color(0.40, 0.43, 0.48, 0.92), true)
	canvas.draw_line(Vector2(-10.0, 2.0), Vector2(10.0, 2.0), Color(0.27, 0.29, 0.33, 0.95), 3.0)
	canvas.draw_line(Vector2(-4.5, 14.0), Vector2(-7.0, 22.0), Color(0.27, 0.29, 0.33, 0.95), 3.0)
	canvas.draw_line(Vector2(4.5, 14.0), Vector2(7.0, 22.0), Color(0.27, 0.29, 0.33, 0.95), 3.0)


static func _draw_shadow(canvas: CanvasItem) -> void:
	_draw_ellipse(canvas, Vector2(0.0, 8.8), Vector2(24.0, 6.5), Color(0.0, 0.0, 0.0, 0.20))


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


static func _load_map_sprite_texture(source: String) -> Texture2D:
	if _map_sprite_texture_cache.has(source):
		return _map_sprite_texture_cache.get(source, null) as Texture2D
	var source_texture: Texture2D = _load_layer_texture(source)
	if source_texture == null:
		_map_sprite_texture_cache[source] = null
		return null
	var image: Image = source_texture.get_image()
	if image == null or image.is_empty():
		_map_sprite_texture_cache[source] = source_texture
		return source_texture
	if not image.has_mipmaps():
		image.generate_mipmaps()
	var texture := ImageTexture.create_from_image(image)
	_map_sprite_texture_cache[source] = texture
	return texture


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

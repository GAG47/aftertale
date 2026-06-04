class_name CharacterAppearanceRenderer
extends RefCounted

const CANVAS_SIZE := Vector2(64.0, 64.0)
const GRID_ANCHOR := Vector2(32.0, 46.0)


static func draw_character(canvas: CanvasItem, context: Dictionary) -> void:
	var appearance: Dictionary = _dictionary(context.get("appearance", {}))
	if not _draw_texture_layer(canvas, appearance, "shadow"):
		_draw_shadow(canvas)

	if bool(context.get("is_training_dummy", false)):
		_draw_training_dummy(canvas)
		return

	if not _draw_texture_layer(canvas, appearance, "hair_back"):
		_draw_hair_back(canvas, context)
	if not _draw_texture_layer(canvas, appearance, "body"):
		_draw_body(canvas, context)
	if not _draw_texture_layer(canvas, appearance, "outfit"):
		_draw_outfit(canvas, context)
	if not _draw_texture_layer(canvas, appearance, "head"):
		_draw_head(canvas, context)
	if not _draw_texture_layer(canvas, appearance, "face"):
		_draw_face(canvas, context)
	if not _draw_texture_layer(canvas, appearance, "hair_front"):
		_draw_hair_front(canvas, context)
	if not _draw_texture_layer(canvas, appearance, "accessory"):
		_draw_accessory(canvas, context)
	if not _draw_texture_layer(canvas, appearance, "held_item"):
		_draw_held_item(canvas, context)


static func _draw_shadow(canvas: CanvasItem) -> void:
	_draw_ellipse(canvas, Vector2(0.0, 8.8), Vector2(24.0, 6.5), Color(0.0, 0.0, 0.0, 0.20))


static func _draw_body(canvas: CanvasItem, context: Dictionary) -> void:
	var body_color: Color = _body_color(context)
	var body := PackedVector2Array([
		Vector2(-7.2, -13.0),
		Vector2(7.2, -13.0),
		Vector2(8.2, 1.0),
		Vector2(5.2, 12.2),
		Vector2(-5.2, 12.2),
		Vector2(-8.2, 1.0),
	])
	_draw_polygon(canvas, body, body_color)
	canvas.draw_polyline(PackedVector2Array([body[0], body[1], body[2], body[3], body[4], body[5], body[0]]), Color(0.08, 0.07, 0.06, 0.46), 1.2)


static func _draw_outfit(canvas: CanvasItem, context: Dictionary) -> void:
	var role: String = _role(context)
	var outfit_color: Color = _outfit_color(context)
	var trim_color: Color = _trim_color(context)
	if role == "guard":
		var armor := PackedVector2Array([
			Vector2(-7.4, -11.8),
			Vector2(7.4, -11.8),
			Vector2(7.2, 12.5),
			Vector2(-7.2, 12.5),
		])
		_draw_polygon(canvas, armor, outfit_color)
		canvas.draw_polyline(PackedVector2Array([armor[0], armor[1], armor[2], armor[3], armor[0]]), Color(0.08, 0.07, 0.06, 0.55), 1.2)
		canvas.draw_line(Vector2(-5.2, -6.0), Vector2(5.2, -6.0), trim_color, 1.2)
		canvas.draw_line(Vector2(0.0, -11.2), Vector2(0.0, 11.5), Color(0.18, 0.17, 0.15, 0.55), 1.0)
		canvas.draw_line(Vector2(-4.8, 1.0), Vector2(4.8, 1.0), Color(0.78, 0.75, 0.66, 0.55), 0.9)
		return

	if role == "clergy" or role == "scholar":
		var robe := PackedVector2Array([
			Vector2(-6.8, -12.0),
			Vector2(6.8, -12.0),
			Vector2(9.4, 13.2),
			Vector2(-9.4, 13.2),
		])
		_draw_polygon(canvas, robe, outfit_color)
		canvas.draw_polyline(PackedVector2Array([robe[0], robe[1], robe[2], robe[3], robe[0]]), Color(0.08, 0.07, 0.06, 0.45), 1.1)
		canvas.draw_line(Vector2(-4.8, -5.8), Vector2(4.8, -5.8), trim_color, 1.2)
		canvas.draw_line(Vector2(0.0, -11.0), Vector2(0.0, 12.2), Color(0.88, 0.82, 0.68, 0.55), 0.9)
		return

	var tunic := PackedVector2Array([
		Vector2(-7.0, -12.0),
		Vector2(7.0, -12.0),
		Vector2(6.8, 12.0),
		Vector2(-6.8, 12.0),
	])
	_draw_polygon(canvas, tunic, outfit_color)
	canvas.draw_polyline(PackedVector2Array([tunic[0], tunic[1], tunic[2], tunic[3], tunic[0]]), Color(0.08, 0.07, 0.06, 0.42), 1.0)
	canvas.draw_line(Vector2(-4.8, -6.0), Vector2(4.8, -6.0), trim_color, 1.4)
	canvas.draw_line(Vector2(-4.6, 4.8), Vector2(4.6, 4.8), Color(0.15, 0.11, 0.08, 0.28), 0.9)
	if role == "farmer" or role == "villager":
		canvas.draw_line(Vector2(-3.8, -10.8), Vector2(-2.4, 10.4), Color(0.78, 0.67, 0.38, 0.78), 1.0)
		canvas.draw_line(Vector2(3.8, -10.8), Vector2(2.4, 10.4), Color(0.78, 0.67, 0.38, 0.78), 1.0)


static func _draw_head(canvas: CanvasItem, context: Dictionary) -> void:
	var skin_color: Color = _skin_color(context)
	canvas.draw_circle(Vector2(0.0, -18.0), 7.4, skin_color)
	canvas.draw_arc(Vector2(0.0, -18.0), 7.5, 0.0, TAU, 24, Color(0.08, 0.07, 0.06, 0.52), 1.2)


static func _draw_face(canvas: CanvasItem, context: Dictionary) -> void:
	var facing: String = str(context.get("facing", "down"))
	if facing == "up":
		return

	var eye_y: float = -18.1
	var eye_offset: float = 2.5
	var eye_color: Color = Color(0.12, 0.10, 0.09)
	if facing == "left":
		canvas.draw_circle(Vector2(-eye_offset, eye_y), 0.9, eye_color)
	elif facing == "right":
		canvas.draw_circle(Vector2(eye_offset, eye_y), 0.9, eye_color)
	else:
		canvas.draw_circle(Vector2(-eye_offset, eye_y), 0.9, eye_color)
		canvas.draw_circle(Vector2(eye_offset, eye_y), 0.9, eye_color)


static func _draw_hair_back(canvas: CanvasItem, context: Dictionary) -> void:
	var hair_id: String = _hair_id(context)
	if not (hair_id.contains("long") or hair_id.contains("bob") or hair_id.contains("twin")):
		return

	var hair_color: Color = _hair_color(context)
	if hair_id.contains("twin"):
		_draw_ellipse(canvas, Vector2(-8.0, -16.2), Vector2(5.0, 16.0), hair_color)
		_draw_ellipse(canvas, Vector2(8.0, -16.2), Vector2(5.0, 16.0), hair_color)
		return

	var back_hair := PackedVector2Array([
		Vector2(-7.8, -20.4),
		Vector2(-8.8, -10.0),
		Vector2(-6.0, 3.0),
		Vector2(6.0, 3.0),
		Vector2(8.8, -10.0),
		Vector2(7.8, -20.4),
	])
	_draw_polygon(canvas, back_hair, hair_color)


static func _draw_hair_front(canvas: CanvasItem, context: Dictionary) -> void:
	var hair_color: Color = _hair_color(context)
	var hair_id: String = _hair_id(context)
	var hair := PackedVector2Array([
		Vector2(-7.0, -19.0),
		Vector2(-4.2, -25.0),
		Vector2(2.0, -26.0),
		Vector2(7.0, -21.5),
		Vector2(5.2, -16.0),
		Vector2(-5.6, -15.8),
	])
	if hair_id.contains("neat") or hair_id.contains("short"):
		hair = PackedVector2Array([
			Vector2(-6.8, -19.2),
			Vector2(-4.6, -24.2),
			Vector2(3.0, -24.7),
			Vector2(6.8, -21.0),
			Vector2(4.7, -16.3),
			Vector2(-5.4, -16.0),
		])
	elif hair_id.contains("bangs"):
		hair.append(Vector2(1.2, -13.8))
		hair.append(Vector2(-1.8, -15.6))
	_draw_polygon(canvas, hair, hair_color)


static func _draw_accessory(canvas: CanvasItem, context: Dictionary) -> void:
	var appearance: Dictionary = _dictionary(context.get("appearance", {}))
	var accessory_ids: Array = appearance.get("accessory_ids", []) as Array
	var role: String = _role(context)
	if role == "guard" and not accessory_ids.has("none"):
		var brim := Rect2(Vector2(-6.8, -24.2), Vector2(13.6, 2.2))
		canvas.draw_rect(brim, Color(0.20, 0.20, 0.20, 0.92), true)
		canvas.draw_rect(brim, Color(0.06, 0.05, 0.04, 0.45), false, 1.0)
		return

	for accessory_id_value in accessory_ids:
		var accessory_id: String = str(accessory_id_value)
		if accessory_id.contains("glasses"):
			canvas.draw_arc(Vector2(-2.5, -18.1), 2.0, 0.0, TAU, 12, Color(0.10, 0.09, 0.08, 0.72), 0.8)
			canvas.draw_arc(Vector2(2.5, -18.1), 2.0, 0.0, TAU, 12, Color(0.10, 0.09, 0.08, 0.72), 0.8)
			canvas.draw_line(Vector2(-0.7, -18.1), Vector2(0.7, -18.1), Color(0.10, 0.09, 0.08, 0.72), 0.8)


static func _draw_held_item(canvas: CanvasItem, context: Dictionary) -> void:
	var held_item_id: String = _held_item_id(context)
	if held_item_id.is_empty() or held_item_id == "none":
		return

	var dark: Color = Color(0.13, 0.10, 0.07, 0.88)
	var wood: Color = Color(0.58, 0.38, 0.18, 0.92)
	var metal: Color = Color(0.68, 0.70, 0.70, 0.95)
	if held_item_id.contains("spear"):
		canvas.draw_line(Vector2(9.0, 10.0), Vector2(17.0, -20.0), dark, 3.0)
		canvas.draw_line(Vector2(9.0, 10.0), Vector2(17.0, -20.0), wood, 1.6)
		var tip := PackedVector2Array([Vector2(17.0, -23.2), Vector2(13.8, -17.4), Vector2(19.2, -17.8)])
		_draw_polygon(canvas, tip, metal)
	elif held_item_id.contains("hoe"):
		canvas.draw_line(Vector2(9.0, 10.0), Vector2(15.8, -15.0), dark, 3.0)
		canvas.draw_line(Vector2(9.0, 10.0), Vector2(15.8, -15.0), wood, 1.6)
		canvas.draw_line(Vector2(13.2, -15.2), Vector2(20.0, -12.9), metal, 2.0)
	elif held_item_id.contains("book") or held_item_id.contains("ledger"):
		var book_rect := Rect2(Vector2(8.0, -5.0), Vector2(8.5, 6.6))
		canvas.draw_rect(book_rect, Color(0.45, 0.20, 0.16, 0.95), true)
		canvas.draw_rect(book_rect, dark, false, 1.0)
		canvas.draw_line(Vector2(12.2, -4.6), Vector2(12.2, 1.2), Color(0.90, 0.78, 0.52, 0.70), 0.8)
	elif held_item_id.contains("broom"):
		canvas.draw_line(Vector2(9.0, 10.0), Vector2(16.5, -15.0), dark, 3.0)
		canvas.draw_line(Vector2(9.0, 10.0), Vector2(16.5, -15.0), wood, 1.6)
		canvas.draw_rect(Rect2(Vector2(14.4, -18.4), Vector2(5.8, 5.4)), Color(0.78, 0.62, 0.32, 0.95), true)
	elif held_item_id.contains("tray"):
		_draw_ellipse(canvas, Vector2(12.8, -1.8), Vector2(12.0, 4.0), Color(0.62, 0.46, 0.26, 0.95))
		canvas.draw_arc(Vector2(12.8, -1.8), 6.2, 0.0, TAU, 16, dark, 0.9)
	elif held_item_id.contains("bag"):
		var bag := Rect2(Vector2(8.4, -2.0), Vector2(8.0, 8.0))
		canvas.draw_rect(bag, Color(0.55, 0.36, 0.18, 0.95), true)
		canvas.draw_rect(bag, dark, false, 1.0)


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
	var layers: Dictionary = _dictionary(appearance.get("layers", {}))
	var layer_data: Dictionary = _dictionary(layers.get(layer_id, {}))
	var source: String = str(layer_data.get("source", layer_data.get("path", "")))
	if source.is_empty() or not ResourceLoader.exists(source):
		return false

	var texture: Texture2D = load(source) as Texture2D
	if texture == null:
		return false

	var offset_data: Dictionary = _dictionary(layer_data.get("offset", {}))
	var offset := Vector2(float(offset_data.get("x", 0.0)), float(offset_data.get("y", 0.0)))
	var modulate: Color = _color_from_value(layer_data.get("modulate", "#ffffffff"), Color.WHITE)
	canvas.draw_texture_rect(texture, Rect2(-GRID_ANCHOR + offset, CANVAS_SIZE), false, modulate)
	return true


static func _skin_color(context: Dictionary) -> Color:
	var palette: Dictionary = _palette(context)
	return _color_from_value(palette.get("skin", ""), Color(0.91, 0.77, 0.62))


static func _hair_color(context: Dictionary) -> Color:
	var palette: Dictionary = _palette(context)
	var fallback: Color = Color(0.45, 0.31, 0.17)
	if str(context.get("kind", "")) == "player":
		fallback = Color(0.28, 0.25, 0.22)
	if _role(context) == "guard":
		fallback = Color(0.20, 0.19, 0.18)
	return _color_from_value(palette.get("hair", ""), fallback)


static func _body_color(context: Dictionary) -> Color:
	var palette: Dictionary = _palette(context)
	return _color_from_value(palette.get("body", ""), _base_color(context))


static func _outfit_color(context: Dictionary) -> Color:
	var palette: Dictionary = _palette(context)
	var role: String = _role(context)
	var fallback: Color = Color(0.43, 0.68, 0.50)
	if role == "guard":
		fallback = Color(0.44, 0.52, 0.62)
	elif role == "farmer":
		fallback = Color(0.48, 0.58, 0.34)
	elif role == "merchant":
		fallback = Color(0.58, 0.40, 0.28)
	elif role == "clergy":
		fallback = Color(0.72, 0.70, 0.64)
	elif str(context.get("kind", "")) == "player":
		fallback = Color(0.48, 0.67, 0.92)
	return _color_from_value(palette.get("outfit", ""), fallback)


static func _trim_color(context: Dictionary) -> Color:
	var palette: Dictionary = _palette(context)
	var fallback: Color = Color(0.96, 0.84, 0.48)
	if _role(context) == "guard":
		fallback = Color(0.82, 0.76, 0.58)
	if str(context.get("kind", "")) == "enemy":
		fallback = Color(0.36, 0.12, 0.10)
	return _color_from_value(palette.get("trim", ""), fallback)


static func _base_color(context: Dictionary) -> Color:
	match str(context.get("kind", "")):
		"player":
			return Color(0.48, 0.62, 0.86)
		"enemy":
			return Color(0.78, 0.38, 0.32)
		"companion":
			return Color(0.43, 0.70, 0.54)
		_:
			if _role(context) == "guard":
				return Color(0.46, 0.50, 0.56)
			return Color(0.54, 0.68, 0.47)


static func _held_item_id(context: Dictionary) -> String:
	var appearance: Dictionary = _dictionary(context.get("appearance", {}))
	var explicit_id: String = str(appearance.get("held_item_id", ""))
	if not explicit_id.is_empty():
		return explicit_id

	var activity_type: String = str(context.get("activity_type", "idle"))
	var role: String = _role(context)
	if role == "guard" and (activity_type == "patrol" or activity_type == "train"):
		return "held_spear_01"
	if activity_type == "work":
		return "held_hoe_01"
	if activity_type == "shopkeep":
		return "held_ledger_01"
	if activity_type == "social" or activity_type == "eat":
		return "held_tray_01"
	return ""


static func _hair_id(context: Dictionary) -> String:
	var appearance: Dictionary = _dictionary(context.get("appearance", {}))
	var hair_front_id: String = str(appearance.get("hair_front_id", ""))
	var hair_id: String = str(appearance.get("hair_id", hair_front_id))
	if not hair_id.is_empty():
		return hair_id
	if _role(context) == "guard":
		return "hair_front_short_neat_01"
	return "hair_front_short_01"


static func _role(context: Dictionary) -> String:
	var profile: Dictionary = _dictionary(context.get("appearance_profile", {}))
	var identity: Dictionary = _dictionary(context.get("identity", {}))
	var role: String = str(profile.get("role", ""))
	if role.is_empty():
		role = str(identity.get("occupation", ""))
	return role


static func _palette(context: Dictionary) -> Dictionary:
	var appearance: Dictionary = _dictionary(context.get("appearance", {}))
	return _dictionary(appearance.get("palette", {}))


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

class_name LocationObject
extends Node2D

@export var object_id: String = ""
@export var display_name: String = ""
@export var grid_position: Vector2i = Vector2i.ZERO
@export var blocks_movement: bool = true
@export var kind: String = "object"
@export var is_inspectable: bool = false
@export var is_pickable: bool = false
@export var is_usable: bool = false
@export_multiline var inspect_text: String = ""
@export_multiline var use_feedback: String = ""

var location_root: Node
var item_definition: Dictionary = {}
var item_quantity: int = 0


func configure(data: Dictionary, parent_location: Node) -> void:
	object_id = str(data.get("id", object_id))
	display_name = str(data.get("display_name", object_id))
	blocks_movement = bool(data.get("blocks_movement", blocks_movement))
	kind = str(data.get("kind", kind))
	is_inspectable = bool(data.get("is_inspectable", kind == "inspectable"))
	is_pickable = bool(data.get("is_pickable", kind == "drop"))
	is_usable = bool(data.get("is_usable", kind == "usable"))
	inspect_text = str(data.get("inspect_text", "There is nothing unusual here."))
	use_feedback = str(data.get("use_feedback", "Nothing happens."))

	var item_data: Dictionary = data.get("item", {}) as Dictionary
	item_quantity = int(item_data.get("quantity", 0))
	var item_source: String = str(item_data.get("source", ""))
	if not item_source.is_empty():
		item_definition = _read_item_definition(item_source)

	var position_data: Dictionary = data.get("grid_position", {}) as Dictionary
	grid_position = Vector2i(int(position_data.get("x", 0)), int(position_data.get("y", 0)))
	location_root = parent_location
	name = object_id

	if location_root.has_method("grid_to_world"):
		position = location_root.grid_to_world(grid_position)

	queue_redraw()


func _draw() -> void:
	_draw_shadow()

	var item_id: String = str(item_definition.get("id", ""))
	if item_id == "debug_apple":
		_draw_apple_icon()
	elif item_id == "debug_seed":
		_draw_seed_pouch_icon()
	elif item_id == "debug_stick":
		_draw_stick_icon()
	elif object_id.find("crate") >= 0:
		_draw_crate_icon()
	elif object_id.find("switch") >= 0:
		_draw_switch_icon()
	elif object_id.find("sign") >= 0 or object_id.find("marker") >= 0:
		_draw_sign_icon()
	else:
		_draw_generic_icon()

	_draw_interaction_badge()


func get_summary() -> Dictionary:
	return {
		"id": object_id,
		"display_name": display_name,
		"grid_position": grid_position,
		"kind": kind,
		"blocks_movement": blocks_movement,
		"is_inspectable": is_inspectable,
		"is_pickable": is_pickable,
		"is_usable": is_usable,
		"item_id": str(item_definition.get("id", "")),
		"item_quantity": item_quantity,
	}


func _read_item_definition(resource_path: String) -> Dictionary:
	return DefinitionLoader.load_item(resource_path)


func _draw_shadow() -> void:
	_draw_ellipse(Vector2(0.0, 9.5), Vector2(18.0, 5.0), Color(0.0, 0.0, 0.0, 0.16))


func _draw_apple_icon() -> void:
	draw_circle(Vector2(-1.5, 0.0), 7.0, Color(0.88, 0.20, 0.18))
	draw_circle(Vector2(2.5, 0.5), 6.6, Color(0.78, 0.12, 0.16))
	draw_circle(Vector2(-4.0, -3.0), 2.0, Color(1.0, 0.58, 0.50, 0.58))
	draw_line(Vector2(0.0, -7.0), Vector2(1.5, -12.0), Color(0.34, 0.20, 0.11), 1.5)
	_draw_ellipse(Vector2(5.0, -10.75), Vector2(6.0, 3.5), Color(0.28, 0.58, 0.25))
	_draw_soft_outline(8.5)


func _draw_seed_pouch_icon() -> void:
	var body := PackedVector2Array([
		Vector2(-8.0, -4.0),
		Vector2(-5.0, 8.0),
		Vector2(6.0, 8.0),
		Vector2(9.0, -4.0),
		Vector2(4.0, -8.0),
		Vector2(-4.0, -8.0),
	])
	draw_polygon(body, _solid_colors(body.size(), Color(0.74, 0.55, 0.29)))
	var outline := PackedVector2Array()
	for point in body:
		outline.append(point)
	outline.append(body[0])
	draw_polyline(outline, Color(0.34, 0.22, 0.12), 1.5)
	draw_line(Vector2(-5.5, -3.5), Vector2(6.5, -3.5), Color(0.42, 0.27, 0.14), 1.2)
	draw_circle(Vector2(-2.5, 1.0), 1.5, Color(0.93, 0.82, 0.42))
	draw_circle(Vector2(2.5, 2.5), 1.5, Color(0.93, 0.82, 0.42))
	draw_circle(Vector2(0.5, 5.0), 1.3, Color(0.93, 0.82, 0.42))


func _draw_stick_icon() -> void:
	var bark: Color = Color(0.48, 0.28, 0.12)
	var highlight: Color = Color(0.75, 0.52, 0.30)
	draw_line(Vector2(-9.0, 6.0), Vector2(8.0, -7.0), bark, 4.0)
	draw_line(Vector2(-9.0, 6.0), Vector2(8.0, -7.0), highlight, 1.4)
	draw_line(Vector2(1.0, -2.0), Vector2(7.0, 2.0), bark, 2.2)
	draw_line(Vector2(-3.0, 1.0), Vector2(-8.0, -2.0), bark, 2.0)


func _draw_sign_icon() -> void:
	draw_rect(Rect2(Vector2(-7.5, -10.0), Vector2(15.0, 10.0)), Color(0.78, 0.55, 0.28), true)
	draw_rect(Rect2(Vector2(-7.5, -10.0), Vector2(15.0, 10.0)), Color(0.28, 0.17, 0.08), false, 1.4)
	draw_line(Vector2(-4.5, -6.8), Vector2(4.5, -6.8), Color(0.37, 0.23, 0.10), 1.0)
	draw_line(Vector2(-5.0, -3.2), Vector2(5.0, -3.2), Color(0.37, 0.23, 0.10), 1.0)
	draw_rect(Rect2(Vector2(-1.5, 0.0), Vector2(3.0, 10.0)), Color(0.44, 0.28, 0.13), true)


func _draw_crate_icon() -> void:
	var rect := Rect2(Vector2(-9.0, -9.0), Vector2(18.0, 18.0))
	draw_rect(rect, Color(0.61, 0.38, 0.19), true)
	draw_rect(rect, Color(0.24, 0.14, 0.07), false, 1.5)
	draw_line(rect.position, rect.end, Color(0.34, 0.20, 0.09), 1.6)
	draw_line(Vector2(rect.end.x, rect.position.y), Vector2(rect.position.x, rect.end.y), Color(0.34, 0.20, 0.09), 1.6)
	draw_rect(rect.grow(-5.5), Color(0.83, 0.58, 0.30, 0.25), false, 1.0)


func _draw_switch_icon() -> void:
	draw_rect(Rect2(Vector2(-6.5, -9.0), Vector2(13.0, 18.0)), Color(0.58, 0.53, 0.55), true)
	draw_rect(Rect2(Vector2(-6.5, -9.0), Vector2(13.0, 18.0)), Color(0.20, 0.18, 0.19), false, 1.4)
	draw_circle(Vector2(0.0, -3.0), 3.8, Color(0.32, 0.29, 0.30))
	draw_line(Vector2(0.0, -3.0), Vector2(5.0, 3.5), Color(0.17, 0.16, 0.16), 2.0)
	draw_circle(Vector2(5.0, 3.5), 2.2, Color(0.80, 0.32, 0.28))


func _draw_generic_icon() -> void:
	var color: Color = Color(0.8, 0.35, 0.25)
	if kind == "inspectable":
		color = Color(0.85, 0.78, 0.35)
	elif kind == "drop":
		color = Color(0.35, 0.85, 0.35)
	elif kind == "usable":
		color = Color(0.75, 0.45, 0.95)
	draw_circle(Vector2.ZERO, 8.0, color)
	_draw_soft_outline(9.0)


func _draw_interaction_badge() -> void:
	if is_pickable:
		draw_circle(Vector2(8.0, -8.0), 3.2, Color(1.0, 0.93, 0.30))
		draw_arc(Vector2(8.0, -8.0), 3.5, 0.0, TAU, 12, Color(0.34, 0.26, 0.04, 0.5), 1.0)

	if is_usable:
		draw_circle(Vector2(-8.0, -8.0), 3.2, Color(0.45, 0.88, 1.0))
		draw_arc(Vector2(-8.0, -8.0), 3.5, 0.0, TAU, 12, Color(0.05, 0.25, 0.34, 0.5), 1.0)


func _draw_soft_outline(radius: float) -> void:
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 20, Color(0.08, 0.07, 0.06, 0.55), 1.4)


func _solid_colors(count: int, color: Color) -> PackedColorArray:
	var colors := PackedColorArray()
	for _index in range(count):
		colors.append(color)
	return colors


func _draw_ellipse(center: Vector2, size: Vector2, color: Color) -> void:
	var points := PackedVector2Array()
	var steps: int = 18
	for index in range(steps):
		var angle: float = TAU * float(index) / float(steps)
		points.append(center + Vector2(cos(angle) * size.x * 0.5, sin(angle) * size.y * 0.5))
	draw_polygon(points, _solid_colors(points.size(), color))

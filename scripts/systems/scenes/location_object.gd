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
@export var facility_type: String = ""
@export var shop_id: String = ""
@export var vendor_character_id: String = ""
@export var rest_type: String = ""
@export var rest_minutes: int = 60
@export var rest_target_hour: int = 6
@export var rest_target_minute: int = 0
@export var heal_ratio: float = 0.0
@export var heal_amount: int = 0
@export var full_restore: bool = false
@export var cost: int = 0
@export var target_scene_path: String = ""
@export var target_entrance_id: String = ""
@export var return_entrance_id: String = ""

var location_root: Node
var item_definition: Dictionary = {}
var item_quantity: int = 0
var recipe_ids: Array[String] = []
var transition_context: Dictionary = {}


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
	facility_type = str(data.get("facility_type", ""))
	if facility_type.is_empty() and kind == "workbench":
		facility_type = "crafting"
	if facility_type.is_empty() and kind == "shop":
		facility_type = "shop"
	if facility_type.is_empty() and (kind == "bed" or kind == "campfire" or kind == "inn"):
		facility_type = "rest"
	if facility_type.is_empty() and kind == "save_point":
		facility_type = "save"
	shop_id = str(data.get("shop_id", ""))
	vendor_character_id = str(data.get("vendor_character_id", data.get("vendor_id", "")))
	rest_type = str(data.get("rest_type", ""))
	if rest_type.is_empty() and facility_type == "rest":
		rest_type = kind
	rest_minutes = max(0, int(data.get("minutes", data.get("rest_minutes", rest_minutes))))
	rest_target_hour = clampi(int(data.get("target_hour", data.get("rest_target_hour", rest_target_hour))), 0, 23)
	rest_target_minute = clampi(int(data.get("target_minute", data.get("rest_target_minute", rest_target_minute))), 0, 59)
	heal_ratio = max(0.0, float(data.get("heal_ratio", heal_ratio)))
	heal_amount = max(0, int(data.get("heal_amount", heal_amount)))
	full_restore = bool(data.get("full_restore", rest_type == "bed" or rest_type == "inn"))
	cost = max(0, int(data.get("cost", cost)))
	target_scene_path = str(data.get("target_scene_path", ""))
	target_entrance_id = str(data.get("target_entrance_id", ""))
	return_entrance_id = str(data.get("return_entrance_id", ""))
	transition_context = (data.get("transition_context", {}) as Dictionary).duplicate(true)
	recipe_ids.clear()
	var recipe_rows: Array = data.get("recipe_ids", []) as Array
	for recipe_id_value in recipe_rows:
		recipe_ids.append(str(recipe_id_value))
	if is_facility():
		is_usable = true

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
	if kind == "door" or facility_type == "scene_transition":
		_draw_interaction_badge()
		return

	_draw_shadow()

	var item_id: String = str(item_definition.get("id", ""))
	if item_id == "debug_apple":
		_draw_apple_icon()
	elif item_id == "debug_herb":
		_draw_herb_icon()
	elif item_id == "debug_seed":
		_draw_seed_pouch_icon()
	elif item_id == "debug_stick":
		_draw_stick_icon()
	elif facility_type == "crafting" or object_id.find("crate") >= 0:
		_draw_crate_icon()
	elif facility_type == "shop" or rest_type == "inn":
		_draw_shop_icon()
	elif rest_type == "campfire":
		_draw_campfire_icon()
	elif rest_type == "bed" or facility_type == "save":
		_draw_marker_icon()
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
		"facility_type": facility_type,
		"shop_id": shop_id,
		"vendor_character_id": vendor_character_id,
		"recipe_ids": recipe_ids.duplicate(),
		"rest_type": rest_type,
		"minutes": rest_minutes,
		"target_hour": rest_target_hour,
		"target_minute": rest_target_minute,
		"heal_ratio": heal_ratio,
		"heal_amount": heal_amount,
		"full_restore": full_restore,
		"cost": cost,
		"target_scene_path": target_scene_path,
		"target_entrance_id": target_entrance_id,
		"return_entrance_id": return_entrance_id,
	}


func is_facility() -> bool:
	return facility_type == "crafting" or facility_type == "shop" or facility_type == "rest" or facility_type == "save"


func is_scene_transition() -> bool:
	return facility_type == "scene_transition" or not target_scene_path.is_empty()


func get_transition_data() -> Dictionary:
	return {
		"id": object_id,
		"display_name": display_name,
		"target_scene_path": target_scene_path,
		"target_entrance_id": target_entrance_id,
		"return_entrance_id": return_entrance_id,
		"context": transition_context.duplicate(true),
	}


func get_facility_data() -> Dictionary:
	return {
		"id": object_id,
		"display_name": display_name,
		"facility_type": facility_type,
		"shop_id": shop_id,
		"vendor_character_id": vendor_character_id,
		"recipe_ids": recipe_ids.duplicate(),
		"rest_type": rest_type,
		"minutes": rest_minutes,
		"target_hour": rest_target_hour,
		"target_minute": rest_target_minute,
		"heal_ratio": heal_ratio,
		"heal_amount": heal_amount,
		"full_restore": full_restore,
		"cost": cost,
	}


func _read_item_definition(resource_path: String) -> Dictionary:
	var loader: Variant = get_node_or_null("/root/DefinitionLoader")
	if loader == null:
		return {}
	return loader.load_item(resource_path)


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


func _draw_herb_icon() -> void:
	for index in range(5):
		var x := -7.0 + float(index) * 3.5
		var top := -8.0 - float(index % 2) * 2.0
		draw_line(Vector2(x, 8.0), Vector2(x + 1.5, top), Color(0.16, 0.48, 0.22), 2.0)
		draw_line(Vector2(x + 1.5, top + 4.0), Vector2(x + 5.0, top + 1.0), Color(0.30, 0.72, 0.34), 1.5)
	draw_circle(Vector2(5.0, -7.5), 2.1, Color(0.78, 0.90, 0.38))
	_draw_soft_outline(9.0)


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


func _draw_shop_icon() -> void:
	var rect := Rect2(Vector2(-10.0, -8.0), Vector2(20.0, 16.0))
	draw_rect(rect, Color(0.56, 0.24, 0.20), true)
	draw_rect(rect, Color(0.18, 0.09, 0.07), false, 1.5)
	draw_line(Vector2(-8.0, -2.0), Vector2(8.0, -2.0), Color(0.94, 0.78, 0.45), 1.5)
	draw_circle(Vector2(-4.0, 3.0), 2.0, Color(0.94, 0.78, 0.45))
	draw_circle(Vector2(4.0, 3.0), 2.0, Color(0.94, 0.78, 0.45))


func _draw_campfire_icon() -> void:
	draw_line(Vector2(-8.0, 8.0), Vector2(8.0, 1.0), Color(0.32, 0.18, 0.09), 3.0)
	draw_line(Vector2(8.0, 8.0), Vector2(-8.0, 1.0), Color(0.32, 0.18, 0.09), 3.0)
	var flame := PackedVector2Array([
		Vector2(0.0, -11.0),
		Vector2(-7.0, 1.0),
		Vector2(-3.0, 8.0),
		Vector2(0.0, 4.0),
		Vector2(4.0, 8.0),
		Vector2(8.0, 1.0),
	])
	draw_polygon(flame, _solid_colors(flame.size(), Color(0.94, 0.28, 0.12)))
	var inner := PackedVector2Array([Vector2(0.0, -5.0), Vector2(-3.0, 4.0), Vector2(2.0, 5.0), Vector2(4.0, 0.0)])
	draw_polygon(inner, _solid_colors(inner.size(), Color(1.0, 0.78, 0.24)))


func _draw_marker_icon() -> void:
	var rect := Rect2(Vector2(-9.0, -7.0), Vector2(18.0, 14.0))
	draw_rect(rect, Color(0.38, 0.48, 0.62), true)
	draw_rect(rect, Color(0.12, 0.17, 0.24), false, 1.4)
	draw_line(Vector2(-5.0, -1.0), Vector2(5.0, -1.0), Color(0.90, 0.92, 0.82), 1.3)
	draw_line(Vector2(-5.0, 3.0), Vector2(5.0, 3.0), Color(0.90, 0.92, 0.82), 1.3)


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
	elif is_facility():
		color = Color(0.95, 0.67, 0.25)
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

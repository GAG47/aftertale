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
@export var target_location_id: String = ""
@export var target_entrance_id: String = ""
@export var return_entrance_id: String = ""
@export var draw_visual: bool = true
@export var source_building_id: String = ""
@export var anchor_id: String = ""
@export var facility_role: String = ""
@export var interaction_kind: String = ""

var location_root: Node
var item_definition: Dictionary = {}
var item_quantity: int = 0
var recipe_ids: Array[String] = []
var transition_context: Dictionary = {}


static func interaction_action_priority(action_type: String) -> int:
	match action_type:
		"scene_transition":
			return 10
		"pickup":
			return 20
		"rest":
			return 30
		"shop", "service":
			return 40
		"craft":
			return 50
		"train":
			return 60
		"harvest":
			return 70
		"inspect":
			return 80
		"open_container":
			return 90
		_:
			return 100


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
	target_location_id = str(data.get("target_location_id", ""))
	target_entrance_id = str(data.get("target_entrance_id", ""))
	return_entrance_id = str(data.get("return_entrance_id", ""))
	draw_visual = bool(data.get("draw_visual", draw_visual))
	source_building_id = str(data.get("source_building_id", data.get("source_blueprint_id", "")))
	anchor_id = str(data.get("anchor_id", data.get("source_anchor_id", "")))
	facility_role = str(data.get("facility_role", ""))
	interaction_kind = str(data.get("interaction_kind", ""))
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
	if not draw_visual:
		return
	if kind == "door" or facility_type == "scene_transition":
		_draw_interaction_badge()
		return

	_draw_shadow()

	var item_id: String = str(item_definition.get("id", ""))
	if item_id == "debug_apple":
		_draw_apple_icon()
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
		"target_location_id": target_location_id,
		"target_entrance_id": target_entrance_id,
		"return_entrance_id": return_entrance_id,
		"source_building_id": source_building_id,
		"anchor_id": anchor_id,
		"facility_role": facility_role,
		"interaction_kind": interaction_kind,
	}


func is_facility() -> bool:
	return facility_type == "crafting" or facility_type == "shop" or facility_type == "rest" or facility_type == "save"


func is_scene_transition() -> bool:
	return facility_type == "scene_transition" or not target_scene_path.is_empty() or not target_location_id.is_empty()


func is_interactable() -> bool:
	return is_scene_transition() or is_pickable or is_facility() or is_usable or is_inspectable or _is_training_object() or _is_container_object()


func get_interaction_actions(_context: Dictionary = {}) -> Array[Dictionary]:
	var actions: Array[Dictionary] = []
	if is_scene_transition():
		_append_interaction_action(actions, "scene_transition", _scene_transition_prompt())
	if is_pickable:
		_append_interaction_action(actions, "pickup", "E/Enter pickup: %s" % display_name)
	match facility_type:
		"rest":
			_append_interaction_action(actions, "rest", _rest_prompt())
		"shop":
			_append_interaction_action(actions, "shop", "E/Enter trade: %s" % display_name)
		"crafting":
			_append_interaction_action(actions, "craft", "E/Enter craft: %s" % display_name)
		"save":
			_append_interaction_action(actions, "service", "E/Enter save: %s" % display_name)
		_:
			if is_facility():
				_append_interaction_action(actions, "service", "E/Enter use: %s" % display_name)
	if _is_training_object():
		_append_interaction_action(actions, "train", "E/Enter train: %s" % display_name)
	if _is_container_object():
		_append_interaction_action(actions, "open_container", "E/Enter open: %s" % display_name)
	elif is_usable and actions.is_empty():
		_append_interaction_action(actions, "inspect", "E/Enter use: %s" % display_name)
	if is_inspectable:
		_append_interaction_action(actions, "inspect", "E/Enter inspect: %s" % display_name)
	actions.sort_custom(Callable(self, "_compare_interaction_actions"))
	return actions


func build_interaction_candidates(context: Dictionary) -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []
	if not is_interactable():
		return candidates
	var source_cell: Vector2i = context.get("source_cell", Vector2i.ZERO) as Vector2i
	var target_cell: Vector2i = context.get("target_cell", grid_position) as Vector2i
	var source_location_id := str(context.get("source_location_id", ""))
	for action_value in get_interaction_actions(context):
		var action: Dictionary = action_value as Dictionary
		var action_type := str(action.get("action_type", "inspect"))
		candidates.append({
			"actor": context.get("actor", null),
			"actor_id": str(context.get("actor_id", "")),
			"source_location_id": source_location_id,
			"source_cell": source_cell,
			"target_cell": target_cell,
			"relation": str(context.get("relation", "facing")),
			"target_kind": "object",
			"target_id": object_id,
			"target_ref": self,
			"action_id": str(action.get("action_id", "%s.%s" % [object_id, action_type])),
			"action_type": action_type,
			"action_priority": int(action.get("action_priority", interaction_action_priority(action_type))),
			"priority": int(context.get("priority", 50)),
			"prompt_text": str(action.get("prompt_text", "")),
			"source_building_id": source_building_id,
			"interior_location_id": target_location_id if action_type == "scene_transition" else source_location_id,
			"anchor_id": anchor_id,
			"facility_role": facility_role,
			"transition_context": transition_context.duplicate(true),
			"metadata": {
				"facility_data": get_facility_data(),
				"transition_data": get_transition_data() if action_type == "scene_transition" else {},
				"blocks_movement": blocks_movement,
				"object_kind": kind,
			},
		})
	return candidates


func get_transition_data() -> Dictionary:
	return {
		"id": object_id,
		"display_name": display_name,
		"target_scene_path": target_scene_path,
		"target_location_id": target_location_id,
		"target_entrance_id": target_entrance_id,
		"return_entrance_id": return_entrance_id,
		"source_building_id": source_building_id,
		"anchor_id": anchor_id,
		"facility_role": facility_role,
		"interaction_kind": interaction_kind,
		"context": transition_context.duplicate(true),
	}


func get_facility_data() -> Dictionary:
	return {
		"id": object_id,
		"display_name": display_name,
		"facility_type": facility_type,
		"shop_id": shop_id,
		"vendor_character_id": vendor_character_id,
		"source_building_id": source_building_id,
		"anchor_id": anchor_id,
		"facility_role": facility_role,
		"interaction_kind": interaction_kind,
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


func _append_interaction_action(actions: Array[Dictionary], action_type: String, prompt_text: String) -> void:
	for existing_value in actions:
		var existing: Dictionary = existing_value
		if str(existing.get("action_type", "")) == action_type:
			return
	actions.append({
		"action_id": "%s.%s" % [object_id, action_type],
		"action_type": action_type,
		"action_priority": interaction_action_priority(action_type),
		"prompt_text": prompt_text,
	})


func _compare_interaction_actions(left: Dictionary, right: Dictionary) -> bool:
	var left_priority := int(left.get("action_priority", 100))
	var right_priority := int(right.get("action_priority", 100))
	if left_priority != right_priority:
		return left_priority < right_priority
	return str(left.get("action_id", "")) < str(right.get("action_id", ""))


func _scene_transition_prompt() -> String:
	if target_scene_path == "__return__" or interaction_kind == "return_to_exterior" or facility_role == "return_door":
		return "E/Enter Leave: %s" % display_name
	return "E/Enter Enter: %s" % display_name


func _rest_prompt() -> String:
	match rest_type:
		"bed":
			return "E/Enter rest until morning: %s" % display_name
		"campfire":
			return "E/Enter rest: %s" % display_name
		"inn":
			return "E/Enter stay: %s (%d gold)" % [display_name, cost]
		_:
			return "E/Enter rest: %s" % display_name


func _is_training_object() -> bool:
	return interaction_kind == "train" or facility_role == "training" or kind == "training_dummy"


func _is_container_object() -> bool:
	return kind == "container" or kind == "chest" or object_id.find("container") >= 0 or object_id.find("chest") >= 0


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

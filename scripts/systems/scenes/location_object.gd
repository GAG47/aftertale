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
	var radius: float = 8.0
	var color: Color = Color(0.8, 0.35, 0.25)
	if kind == "inspectable":
		color = Color(0.85, 0.78, 0.35)
	elif kind == "drop":
		color = Color(0.35, 0.85, 0.35)
	elif kind == "usable":
		color = Color(0.75, 0.45, 0.95)

	draw_circle(Vector2.ZERO, radius, color)
	draw_arc(Vector2.ZERO, radius + 2.0, 0.0, TAU, 16, Color.BLACK, 1.0)

	if is_pickable:
		draw_circle(Vector2(6.0, -6.0), 2.5, Color(0.95, 1.0, 0.45))

	if is_usable:
		draw_circle(Vector2(-6.0, -6.0), 2.5, Color(0.45, 0.9, 1.0))


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

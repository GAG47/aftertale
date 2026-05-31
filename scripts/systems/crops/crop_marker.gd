class_name CropMarker
extends Node2D

var crop_state: Dictionary = {}
var crop_definition: Dictionary = {}
var tile_size: int = 32


func configure(state: Dictionary, definition: Dictionary, size: int) -> void:
	crop_state = state.duplicate(true)
	crop_definition = definition.duplicate(true)
	tile_size = size
	queue_redraw()


func _draw() -> void:
	var stage_color: Color = _get_stage_color()
	var radius: float = max(4.0, float(tile_size) * 0.18)
	draw_circle(Vector2.ZERO, radius, stage_color)
	draw_arc(Vector2.ZERO, radius + 2.0, 0.0, TAU, 20, Color(0.05, 0.08, 0.04), 2.0)

	if bool(crop_state.get("watered", false)):
		draw_circle(Vector2(radius * 0.8, -radius * 0.8), 3.0, Color(0.35, 0.75, 1.0))

	if bool(crop_state.get("mature", false)):
		draw_circle(Vector2(-radius * 0.85, -radius * 0.85), 3.0, Color(1.0, 0.9, 0.25))


func _get_stage_color() -> Color:
	var stage_id: String = str(crop_state.get("stage_id", "seeded"))
	var stages: Array = crop_definition.get("stages", []) as Array
	for stage_value in stages:
		var stage: Dictionary = stage_value as Dictionary
		if str(stage.get("id", "")) == stage_id:
			return Color.html(str(stage.get("color", "#76a85b")))

	return Color(0.45, 0.75, 0.35)

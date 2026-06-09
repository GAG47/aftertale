extends Control

@export var fill_color := Color(0.018, 0.032, 0.047, 0.98)
@export var border_color := Color(0.95, 0.55, 0.2, 0.95)
@export var border_width := 2.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)
	queue_redraw()


func _draw() -> void:
	var center := size * 0.5
	var half_extent := maxf(0.0, minf(size.x, size.y) * 0.5 - border_width)
	var points := PackedVector2Array([
		center + Vector2(0.0, -half_extent),
		center + Vector2(half_extent, 0.0),
		center + Vector2(0.0, half_extent),
		center + Vector2(-half_extent, 0.0),
	])
	draw_colored_polygon(points, fill_color)
	var outline := points.duplicate()
	outline.append(points[0])
	draw_polyline(outline, border_color, border_width, true)

class_name BattleFeedbackPopup
extends Node2D


func configure(text: String, color: Color) -> void:
	var label: Label = Label.new()
	label.custom_minimum_size = Vector2(80.0, 22.0)
	label.position = Vector2(-40.0, -34.0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.text = text
	label.modulate = color
	add_child(label)

	var tween: Tween = create_tween()
	tween.set_parallel(true)
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "position", position + Vector2(0.0, -16.0), 0.55)
	tween.tween_property(label, "modulate:a", 0.0, 0.55)
	tween.set_parallel(false)
	tween.tween_callback(Callable(self, "queue_free"))

class_name MessageLogPanel
extends PanelContainer

const MAX_MESSAGES := 5
const UI_LABEL_SCENE := preload("res://scenes/ui/components/ui_label.tscn")

@onready var message_box: VBoxContainer = $MarginContainer/MessageBox

var messages: Array[String] = []


func _ready() -> void:
	_refresh()


func add_message(message: String) -> void:
	if message.is_empty():
		return

	messages.append(message)
	while messages.size() > MAX_MESSAGES:
		messages.pop_front()

	_refresh()


func add_result(result: ActionResult) -> void:
	if result == null:
		return

	if result.feedback.is_empty():
		if not result.success and not result.failure_reason.is_empty():
			add_message(result.failure_reason)
		return

	for feedback_value in result.feedback:
		add_message(str(feedback_value))


func clear_messages() -> void:
	messages.clear()
	_refresh()


func _refresh() -> void:
	if message_box == null:
		return

	for child in message_box.get_children():
		child.queue_free()

	if messages.is_empty():
		var empty_label: Label = _make_label("")
		message_box.add_child(empty_label)
		return

	for message_value in messages:
		message_box.add_child(_make_label(str(message_value)))


func _make_label(message: String) -> Label:
	var label: Label = UI_LABEL_SCENE.instantiate() as Label
	label.text = message
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label

class_name DialoguePanel
extends PanelContainer

signal option_selected(option_id: String)

const ACTION_BUTTON_SCENE := preload("res://scenes/ui/components/action_button.tscn")

@onready var speaker_label: Label = $MarginContainer/VBoxContainer/SpeakerLabel
@onready var text_label: Label = $MarginContainer/VBoxContainer/TextLabel
@onready var options_scroll: ScrollContainer = $MarginContainer/VBoxContainer/OptionsScroll
@onready var options_box: VBoxContainer = $MarginContainer/VBoxContainer/OptionsScroll/OptionsBox


func _ready() -> void:
	visible = false


func show_state(state: Dictionary) -> void:
	if state.is_empty():
		hide_panel()
		return

	speaker_label.text = str(state.get("speaker_name", ""))
	text_label.text = str(state.get("text", ""))
	_clear_options()
	options_scroll.scroll_vertical = 0

	var options: Array = state.get("options", []) as Array
	for index in range(options.size()):
		var option: Dictionary = options[index] as Dictionary
		var button: Button = ACTION_BUTTON_SCENE.instantiate() as Button
		button.text = "%d. %s" % [index + 1, str(option.get("text", ""))]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.pressed.connect(_on_option_pressed.bind(str(option.get("id", ""))))
		options_box.add_child(button)

	visible = true


func hide_panel() -> void:
	visible = false
	_clear_options()


func _clear_options() -> void:
	for child in options_box.get_children():
		child.queue_free()


func _on_option_pressed(option_id: String) -> void:
	option_selected.emit(option_id)

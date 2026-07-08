class_name RawDataPanel
extends PanelContainer

@onready var data_label: Label = $MarginContainer/ScrollContainer/DataLabel


func _ready() -> void:
	visible = false
	data_label.autowrap_mode = TextServer.AUTOWRAP_OFF


func set_data(data: Dictionary) -> void:
	data_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	data_label.text = JSON.stringify(data, "\t")
	visible = not data.is_empty()


func clear_data() -> void:
	data_label.text = ""
	visible = false

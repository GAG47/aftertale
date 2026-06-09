extends Control

@onready var _status_label: Label = $Root/LeftPanel/Status
@onready var _details: TextEdit = $Root/RightPanel/Details


func _ready() -> void:
	_set_status("Portrait Badge Fitter is kept only for old scenes. Use Portrait Avatar Fitter for square avatar cropping.")
	if _details != null:
		_details.text = "\n".join([
			"status: deprecated compatibility scene",
			"replacement: res://scenes/tools/portrait_avatar_fitter.tscn",
			"note: current UI uses square portrait avatars instead of circular badges.",
		])
	_disable_buttons()


func _disable_buttons() -> void:
	for path in [
		"Root/RightPanel/Actions/ReloadButton",
		"Root/RightPanel/Actions/SaveButton",
		"Root/RightPanel/Actions/GenerateButton",
		"Root/RightPanel/Navigation/PreviousButton",
		"Root/RightPanel/Navigation/NextButton",
	]:
		if not has_node(path):
			continue
		var button: Button = get_node(path) as Button
		button.disabled = true


func _set_status(text: String) -> void:
	if _status_label != null:
		_status_label.text = text
	print(text)

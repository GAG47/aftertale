class_name RegionGraphPanel
extends PanelContainer

signal travel_requested(edge_id: String)

@onready var title_label: Label = $MarginContainer/Content/TitleLabel
@onready var id_label: Label = $MarginContainer/Content/IdLabel
@onready var meta_label: Label = $MarginContainer/Content/MetaLabel
@onready var exits_box: VBoxContainer = $MarginContainer/Content/ExitScroll/ExitBox

var _runtime: Variant
var _current_edges: Array[Dictionary] = []


func bind_runtime(runtime: Variant) -> void:
	_runtime = runtime
	refresh()


func refresh() -> void:
	if _runtime == null or not _runtime.is_graph_active():
		visible = false
		return
	var location: Dictionary = _runtime.get_current_location()
	if location.is_empty():
		visible = false
		return
	visible = true
	var role_slug := str(location.get("role_slug", ""))
	var location_type := str(location.get("location_type", ""))
	title_label.text = _display_token(role_slug if not role_slug.is_empty() else location_type)
	id_label.text = str(location.get("location_id", ""))
	meta_label.text = "%s | %s | %s" % [
		_display_token(location_type),
		_display_token(str(location.get("role_type", ""))),
		_display_token(str(location.get("role_source", ""))),
	]
	_refresh_edges()


func travel_first_exit() -> bool:
	if not visible or _current_edges.is_empty():
		return false
	var edge: Dictionary = _current_edges[0]
	travel_requested.emit(str(edge.get("edge_id", "")))
	return true


func _refresh_edges() -> void:
	for child in exits_box.get_children():
		child.queue_free()
	_current_edges = _runtime.get_edges_from(str(_runtime.current_location_id))
	if _current_edges.is_empty():
		var empty_label := Label.new()
		empty_label.text = "No exits."
		empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		exits_box.add_child(empty_label)
		return
	for edge_value in _current_edges:
		var edge: Dictionary = edge_value as Dictionary
		exits_box.add_child(_edge_button(edge))


func _edge_button(edge: Dictionary) -> Button:
	var button := Button.new()
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	var target_location: Dictionary = _runtime.get_location(str(edge.get("traversal_to_location_id", "")))
	var target_name := _display_token(str(target_location.get("role_slug", edge.get("target_location_id", ""))))
	var detail := "%s / %s / %s" % [
		_display_token(str(edge.get("travel_type", ""))),
		_display_token(str(edge.get("direction_hint", ""))),
		_display_token(str(edge.get("exit_style", ""))),
	]
	button.text = "%s    %s" % [target_name, detail]
	button.pressed.connect(_on_edge_button_pressed.bind(str(edge.get("edge_id", ""))))
	return button


func _on_edge_button_pressed(edge_id: String) -> void:
	if edge_id.is_empty():
		return
	travel_requested.emit(edge_id)


static func _display_token(value: String) -> String:
	if value.is_empty():
		return "-"
	return value.replace("_", " ").capitalize()

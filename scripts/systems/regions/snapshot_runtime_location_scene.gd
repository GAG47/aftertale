class_name SnapshotRuntimeLocationScene
extends Control

@onready var graph_id_value: Label = $RuntimePanel/MarginContainer/Content/GraphInfo/GraphIdValue
@onready var snapshot_id_value: Label = $RuntimePanel/MarginContainer/Content/GraphInfo/SnapshotIdValue
@onready var current_name_label: Label = $RuntimePanel/MarginContainer/Content/CurrentName
@onready var current_id_label: Label = $RuntimePanel/MarginContainer/Content/CurrentId
@onready var current_type_label: Label = $RuntimePanel/MarginContainer/Content/CurrentType
@onready var current_tags_label: Label = $RuntimePanel/MarginContainer/Content/CurrentTags
@onready var neighbors_container: VBoxContainer = $RuntimePanel/MarginContainer/Content/NeighborsScroll/Neighbors
@onready var status_label: Label = $RuntimePanel/MarginContainer/Content/StatusLabel

var _adapter: RefCounted


func bind_adapter(adapter: RefCounted) -> Dictionary:
	if adapter == null:
		show_load_error("", "", "LocationGraphRuntimeAdapter is missing")
		return _failure(["LocationGraphRuntimeAdapter is missing"])
	if _adapter != null and _adapter.location_changed.is_connected(_on_location_changed):
		_adapter.location_changed.disconnect(_on_location_changed)
	_adapter = adapter
	if not _adapter.location_changed.is_connected(_on_location_changed):
		_adapter.location_changed.connect(_on_location_changed)
	return refresh_view()


func refresh_view() -> Dictionary:
	if _adapter == null:
		show_load_error("", "", "LocationGraphRuntimeAdapter is not bound")
		return _failure(["LocationGraphRuntimeAdapter is not bound"])
	var view_result: Dictionary = _adapter.get_current_location_view()
	if not bool(view_result.get("success", false)):
		var errors_text := "; ".join(view_result.get("errors", []) as Array[String])
		show_load_error("", "", errors_text)
		return view_result
	var view: Dictionary = view_result.get("view", {}) as Dictionary
	_apply_view(view)
	status_label.text = ""
	return {
		"success": true,
		"errors": [],
		"warnings": [],
		"current_location_id": str(view.get("current_location_id", "")),
	}


func show_load_error(graph_id: String, snapshot_id: String, error_text: String) -> void:
	graph_id_value.text = graph_id
	snapshot_id_value.text = snapshot_id
	current_name_label.text = "Runtime unavailable"
	current_id_label.text = ""
	current_type_label.text = ""
	current_tags_label.text = ""
	_clear_neighbors()
	status_label.text = error_text


func get_displayed_current_location_id() -> String:
	return current_id_label.text.trim_prefix("current_location_id: ")


func get_neighbor_button_count() -> int:
	var count := 0
	for child in neighbors_container.get_children():
		if child is Button:
			count += 1
	return count


func _apply_view(view: Dictionary) -> void:
	graph_id_value.text = str(view.get("graph_id", ""))
	snapshot_id_value.text = str(view.get("snapshot_id", ""))
	current_name_label.text = str(view.get("current_location_name", ""))
	current_id_label.text = "current_location_id: %s" % str(view.get("current_location_id", ""))
	current_type_label.text = "location_type: %s    archetype: %s    form: %s" % [
		str(view.get("current_location_type", "")),
		str(view.get("current_source_archetype_id", "")),
		str(view.get("current_source_form_id", "")),
	]
	var current_tags: Array = view.get("current_location_tags", []) as Array
	current_tags_label.text = "tags: %s" % _join_strings(current_tags)
	_clear_neighbors()
	var neighbors: Array = view.get("neighbors", []) as Array
	if neighbors.is_empty():
		var empty_label := Label.new()
		empty_label.text = "无相邻地点"
		neighbors_container.add_child(empty_label)
		return
	for neighbor_value in neighbors:
		var neighbor: Dictionary = neighbor_value as Dictionary
		var button := Button.new()
		var traversal_tags: Array = neighbor.get("traversal_tags", []) as Array
		button.custom_minimum_size = Vector2(0, 82)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.text = "%s\n%s\nedge: %s | %s | tags: %s" % [
			str(neighbor.get("target_location_name", "")),
			str(neighbor.get("target_location_id", "")),
			str(neighbor.get("edge_id", "")),
			str(neighbor.get("edge_type", "")),
			_join_strings(traversal_tags),
		]
		var access_rule := str(neighbor.get("access_rule", ""))
		button.disabled = access_rule != "always"
		button.tooltip_text = "access_rule: %s" % access_rule
		button.pressed.connect(_on_neighbor_pressed.bind(str(neighbor.get("target_location_id", ""))))
		neighbors_container.add_child(button)


func _on_neighbor_pressed(target_location_id: String) -> void:
	if _adapter == null:
		status_label.text = "LocationGraphRuntimeAdapter is not bound"
		return
	var travel_result: Dictionary = _adapter.travel_to_location(target_location_id)
	if not bool(travel_result.get("success", false)):
		status_label.text = "; ".join(travel_result.get("errors", []) as Array[String])
		return
	status_label.text = ""


func _on_location_changed(view: Dictionary) -> void:
	_apply_view(view)
	status_label.text = ""


func _clear_neighbors() -> void:
	for child in neighbors_container.get_children():
		neighbors_container.remove_child(child)
		child.queue_free()


static func _failure(errors: Array[String]) -> Dictionary:
	return {
		"success": false,
		"errors": errors.duplicate(),
		"warnings": [],
	}


static func _join_strings(values: Array) -> String:
	var parts: Array[String] = []
	for value in values:
		parts.append(str(value))
	return ", ".join(parts)

class_name QuestPanel
extends Control

signal close_requested()

const QUEST_LIST_ITEM_SCENE := preload("res://scenes/ui/components/quest_list_item.tscn")
const UI_LABEL_SCENE := preload("res://scenes/ui/components/ui_label.tscn")

var _quest_system: Node
var _quests: Array[Dictionary] = []
var _selected_quest_id: String = ""

@onready var _panel: PanelContainer = $QuestWindow
@onready var _list_box: VBoxContainer = $QuestWindow/Margin/Root/Body/ListPanel/Margin/Scroll/List
@onready var _detail_title: Label = $QuestWindow/Margin/Root/Body/DetailPanel/Margin/Scroll/Box/DetailTitle
@onready var _detail_body: Label = $QuestWindow/Margin/Root/Body/DetailPanel/Margin/Scroll/Box/DetailBody
var _empty_list_label: Label


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	$QuestWindow/Margin/Root/Header/CloseButton.pressed.connect(_request_close)


func bind_context(quest_system: Node) -> void:
	_quest_system = quest_system


func open_panel() -> void:
	visible = true
	refresh()


func close_panel() -> void:
	visible = false


func is_open() -> bool:
	return visible


func refresh() -> void:
	_quests = _get_quest_summaries()
	_select_default_quest()
	_refresh_list()
	_refresh_detail(_get_selected_quest())


func _refresh_list() -> void:
	_clear_children(_list_box)
	if _quests.is_empty():
		_empty_list_label = UI_LABEL_SCENE.instantiate() as Label
		_empty_list_label.text = "暂无任务。"
		_empty_list_label.modulate = Color(0.78, 0.8, 0.75)
		_empty_list_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_list_box.add_child(_empty_list_label)
		return

	for quest_value in _quests:
		var quest: Dictionary = quest_value as Dictionary
		_list_box.add_child(_make_quest_cell(quest))


func _make_quest_cell(quest: Dictionary) -> Control:
	var quest_id: String = str(quest.get("quest_id", ""))
	var selected: bool = quest_id == _selected_quest_id

	var cell: PanelContainer = QUEST_LIST_ITEM_SCENE.instantiate() as PanelContainer
	cell.add_theme_stylebox_override("panel", _make_panel_style(
		Color(0.105, 0.115, 0.105, 0.95) if selected else Color(0.08, 0.088, 0.082, 0.9),
		Color(0.42, 0.8, 1.0, 0.82) if selected else Color(0.78, 0.82, 0.72, 0.26),
		5,
		2 if selected else 1
	))
	cell.gui_input.connect(_on_quest_cell_gui_input.bind(quest_id))

	var title: Label = cell.get_node("Margin/Box/Title") as Label
	title.text = str(quest.get("display_name", quest_id))
	title.add_theme_color_override("font_color", Color(0.96, 0.97, 0.92, 1.0))

	var summary: Label = cell.get_node("Margin/Box/Summary") as Label
	summary.text = _get_quest_description(quest).strip_edges()
	if summary.text.is_empty():
		summary.text = "暂无简介。"
	summary.modulate = Color(0.76, 0.79, 0.74)
	return cell


func _refresh_detail(quest: Dictionary) -> void:
	if quest.is_empty():
		_detail_title.text = "选择一个任务"
		_detail_body.text = "左侧任务列表会显示任务名称和任务简介。"
		return

	var quest_id: String = str(quest.get("quest_id", ""))
	_detail_title.text = str(quest.get("display_name", quest_id))

	var lines: PackedStringArray = PackedStringArray()
	var description: String = _get_quest_description(quest).strip_edges()
	if description.is_empty():
		description = "暂无任务详情。"
	lines.append(description)

	var objective_lines: PackedStringArray = _build_objective_lines(quest)
	if not objective_lines.is_empty():
		lines.append("")
		lines.append("任务目标")
		for line in objective_lines:
			lines.append(line)

	var failed_reason: String = str(quest.get("failed_reason", "")).strip_edges()
	if not failed_reason.is_empty():
		lines.append("")
		lines.append("失败原因")
		lines.append(failed_reason)

	_detail_body.text = "\n".join(lines)


func _get_quest_summaries() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if _quest_system == null or not is_instance_valid(_quest_system):
		return result

	for quest_value in _quest_system.get_summary():
		var quest: Dictionary = (quest_value as Dictionary).duplicate(true)
		var definition: Dictionary = _get_quest_definition(str(quest.get("quest_id", "")))
		if not definition.is_empty():
			quest["description"] = str(definition.get("description", quest.get("description", "")))
		result.append(quest)
	return result


func _get_quest_definition(quest_id: String) -> Dictionary:
	if _quest_system == null or not is_instance_valid(_quest_system):
		return {}
	var definitions_value: Variant = _quest_system.get("quest_definitions")
	if typeof(definitions_value) != TYPE_DICTIONARY:
		return {}

	var definitions: Dictionary = definitions_value as Dictionary
	if not definitions.has(quest_id):
		return {}
	return definitions[quest_id] as Dictionary


func _select_default_quest() -> void:
	if _quests.is_empty():
		_selected_quest_id = ""
		return

	for quest_value in _quests:
		var quest: Dictionary = quest_value as Dictionary
		if str(quest.get("quest_id", "")) == _selected_quest_id:
			return

	_selected_quest_id = str((_quests[0] as Dictionary).get("quest_id", ""))


func _get_selected_quest() -> Dictionary:
	for quest_value in _quests:
		var quest: Dictionary = quest_value as Dictionary
		if str(quest.get("quest_id", "")) == _selected_quest_id:
			return quest
	return {}


func _get_quest_description(quest: Dictionary) -> String:
	return str(quest.get("description", ""))


func _build_objective_lines(quest: Dictionary) -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	var objectives: Dictionary = quest.get("objectives", {}) as Dictionary
	for objective_value in objectives.values():
		var objective: Dictionary = objective_value as Dictionary
		var marker: String = "已完成" if bool(objective.get("completed", false)) else "进行中"
		lines.append("%s - %s" % [
			marker,
			str(objective.get("description", objective.get("id", ""))),
		])
	return lines


func _on_quest_cell_gui_input(event: InputEvent, quest_id: String) -> void:
	if event is InputEventMouseButton:
		var mouse_event: InputEventMouseButton = event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
			_selected_quest_id = quest_id
			_refresh_list()
			_refresh_detail(_get_selected_quest())
			get_viewport().set_input_as_handled()


func _request_close() -> void:
	close_requested.emit()


func _make_panel_style(bg_color: Color, border_color: Color, radius: int, border_width: int = 1) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = bg_color
	style.border_color = border_color
	style.border_width_left = border_width
	style.border_width_top = border_width
	style.border_width_right = border_width
	style.border_width_bottom = border_width
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	return style


func _clear_children(parent: Node) -> void:
	for child in parent.get_children():
		child.queue_free()

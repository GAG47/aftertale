class_name GameMenuPanel
extends PanelContainer

signal close_requested()
signal return_title_requested()
signal quit_game_requested()
signal new_game_requested()

enum ViewMode {
	SYSTEM,
	SETTINGS,
	CONFIRM_RETURN_TITLE,
	CONFIRM_QUIT,
	TITLE,
}

var _content_box: VBoxContainer
var _title_label: Label
var _close_button: Button
var _volume_label: Label
var _view_mode: ViewMode = ViewMode.SYSTEM
var _confirm_return_view: ViewMode = ViewMode.SYSTEM


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_ui()


func bind_context(_scene_loader: Node, _quest_system: Node) -> void:
	pass


func open_menu() -> void:
	_view_mode = ViewMode.SYSTEM
	visible = true
	_apply_window_size(Vector2(420.0, 360.0))
	_refresh()


func open_title_menu() -> void:
	_view_mode = ViewMode.TITLE
	visible = true
	_apply_window_size(Vector2(460.0, 320.0))
	_refresh()


func close_menu() -> void:
	visible = false


func is_title_screen() -> bool:
	return visible and _view_mode == ViewMode.TITLE


func refresh() -> void:
	_refresh()


func _build_ui() -> void:
	_clear_children(self)
	_apply_window_size(Vector2(420.0, 360.0))
	add_theme_stylebox_override("panel", _make_panel_style(Color(0.055, 0.06, 0.055, 0.98), Color(0.78, 0.52, 0.24, 0.82), 6, 2))

	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 22)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_right", 22)
	margin.add_theme_constant_override("margin_bottom", 18)
	add_child(margin)

	var root: VBoxContainer = VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 14)
	margin.add_child(root)

	var header: HBoxContainer = HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	root.add_child(header)

	_title_label = Label.new()
	_title_label.text = "系统"
	_title_label.add_theme_font_size_override("font_size", 24)
	_title_label.add_theme_color_override("font_color", Color(0.94, 0.82, 0.62))
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title_label)

	_close_button = Button.new()
	_close_button.text = "关闭"
	_close_button.custom_minimum_size = Vector2(82.0, 32.0)
	_close_button.pressed.connect(_on_continue_pressed)
	header.add_child(_close_button)

	root.add_child(HSeparator.new())

	_content_box = VBoxContainer.new()
	_content_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content_box.add_theme_constant_override("separation", 10)
	root.add_child(_content_box)


func _refresh() -> void:
	if _content_box == null:
		return

	_clear_children(_content_box)
	match _view_mode:
		ViewMode.SYSTEM:
			_refresh_system_view()
		ViewMode.SETTINGS:
			_refresh_settings_view()
		ViewMode.CONFIRM_RETURN_TITLE:
			_refresh_confirm_view(
				"返回标题",
				"返回标题将丢失未保存的进度。",
				"确认返回",
				_on_confirm_return_title_pressed
			)
		ViewMode.CONFIRM_QUIT:
			_refresh_confirm_view(
				"退出游戏",
				"退出游戏将丢失未保存的进度。",
				"确认退出",
				_on_confirm_quit_pressed
			)
		ViewMode.TITLE:
			_refresh_title_view()


func _refresh_system_view() -> void:
	_title_label.text = "系统"
	_close_button.visible = true
	_content_box.add_child(_make_menu_button("继续游戏", _on_continue_pressed))
	_content_box.add_child(_make_menu_button("设置", _on_settings_pressed))
	_content_box.add_child(_make_menu_button("返回标题", _on_return_title_pressed))
	_content_box.add_child(_make_menu_button("退出游戏", _on_quit_pressed))


func _refresh_settings_view() -> void:
	_title_label.text = "设置"
	_close_button.visible = true

	var volume_row: HBoxContainer = HBoxContainer.new()
	volume_row.add_theme_constant_override("separation", 10)
	_content_box.add_child(volume_row)

	var label: Label = _make_label("主音量")
	label.custom_minimum_size = Vector2(80.0, 32.0)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	volume_row.add_child(label)

	var slider: HSlider = HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 100.0
	slider.step = 1.0
	slider.value = _get_master_volume_percent()
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.value_changed.connect(_on_master_volume_changed)
	volume_row.add_child(slider)

	_volume_label = _make_label("%d%%" % int(round(slider.value)))
	_volume_label.custom_minimum_size = Vector2(52.0, 32.0)
	_volume_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_volume_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	volume_row.add_child(_volume_label)

	var fullscreen_check: CheckBox = CheckBox.new()
	fullscreen_check.text = "全屏"
	fullscreen_check.button_pressed = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	fullscreen_check.toggled.connect(_on_fullscreen_toggled)
	_content_box.add_child(fullscreen_check)

	var spacer: Control = Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content_box.add_child(spacer)

	_content_box.add_child(_make_menu_button("返回", _on_settings_back_pressed))


func _refresh_confirm_view(title: String, message: String, confirm_text: String, callback: Callable) -> void:
	_title_label.text = title
	_close_button.visible = false

	var message_label: Label = _make_label(message)
	message_label.add_theme_font_size_override("font_size", 17)
	message_label.modulate = Color(0.88, 0.84, 0.76)
	_content_box.add_child(message_label)

	var spacer: Control = Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content_box.add_child(spacer)

	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_content_box.add_child(row)

	var cancel_button: Button = Button.new()
	cancel_button.text = "取消"
	cancel_button.custom_minimum_size = Vector2(150.0, 38.0)
	cancel_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel_button.pressed.connect(_on_confirm_cancel_pressed)
	row.add_child(cancel_button)

	var confirm_button: Button = Button.new()
	confirm_button.text = confirm_text
	confirm_button.custom_minimum_size = Vector2(150.0, 38.0)
	confirm_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	confirm_button.pressed.connect(callback)
	row.add_child(confirm_button)


func _refresh_title_view() -> void:
	_title_label.text = "Aftertale"
	_close_button.visible = false

	var subtitle: Label = _make_label("标题")
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.modulate = Color(0.74, 0.78, 0.70)
	_content_box.add_child(subtitle)

	var spacer_top: Control = Control.new()
	spacer_top.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content_box.add_child(spacer_top)

	_content_box.add_child(_make_menu_button("新游戏", _on_new_game_pressed))
	var load_button: Button = _make_menu_button("继续游戏", _on_load_game_pressed)
	load_button.disabled = not SaveManager.has_save()
	_content_box.add_child(load_button)
	_content_box.add_child(_make_menu_button("退出游戏", _on_quit_pressed))

	var spacer_bottom: Control = Control.new()
	spacer_bottom.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content_box.add_child(spacer_bottom)


func _make_menu_button(text: String, callback: Callable) -> Button:
	var button: Button = Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0.0, 42.0)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(callback)
	return button


func _make_label(text: String) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label


func _apply_window_size(size: Vector2) -> void:
	set_anchors_preset(Control.PRESET_CENTER)
	offset_left = -size.x * 0.5
	offset_top = -size.y * 0.5
	offset_right = size.x * 0.5
	offset_bottom = size.y * 0.5
	custom_minimum_size = size


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


func _get_master_volume_percent() -> float:
	var bus_index: int = AudioServer.get_bus_index("Master")
	if bus_index < 0:
		return 100.0

	var linear: float = db_to_linear(AudioServer.get_bus_volume_db(bus_index))
	return clampf(linear * 100.0, 0.0, 100.0)


func _set_master_volume_percent(value: float) -> void:
	var bus_index: int = AudioServer.get_bus_index("Master")
	if bus_index < 0:
		return

	var linear: float = clampf(value / 100.0, 0.0, 1.0)
	AudioServer.set_bus_mute(bus_index, linear <= 0.0)
	if linear > 0.0:
		AudioServer.set_bus_volume_db(bus_index, linear_to_db(linear))


func _on_continue_pressed() -> void:
	close_requested.emit()


func _on_settings_pressed() -> void:
	_view_mode = ViewMode.SETTINGS
	_refresh()


func _on_settings_back_pressed() -> void:
	_view_mode = ViewMode.SYSTEM
	_refresh()


func _on_return_title_pressed() -> void:
	_confirm_return_view = _view_mode
	_view_mode = ViewMode.CONFIRM_RETURN_TITLE
	_refresh()


func _on_quit_pressed() -> void:
	_confirm_return_view = _view_mode
	_view_mode = ViewMode.CONFIRM_QUIT
	_refresh()


func _on_confirm_cancel_pressed() -> void:
	_view_mode = _confirm_return_view
	_refresh()


func _on_confirm_return_title_pressed() -> void:
	return_title_requested.emit()


func _on_confirm_quit_pressed() -> void:
	quit_game_requested.emit()


func _on_new_game_pressed() -> void:
	new_game_requested.emit()


func _on_load_game_pressed() -> void:
	SaveManager.load_game()


func _on_master_volume_changed(value: float) -> void:
	_set_master_volume_percent(value)
	if _volume_label != null:
		_volume_label.text = "%d%%" % int(round(value))


func _on_fullscreen_toggled(enabled: bool) -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if enabled else DisplayServer.WINDOW_MODE_WINDOWED)


func _clear_children(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()

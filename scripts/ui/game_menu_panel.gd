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

@onready var _title_label: Label = $Margin/Root/Header/TitleLabel
@onready var _close_button: Button = $Margin/Root/Header/CloseButton
@onready var _system_view: VBoxContainer = $Margin/Root/Content/SystemView
@onready var _settings_view: VBoxContainer = $Margin/Root/Content/SettingsView
@onready var _confirm_view: VBoxContainer = $Margin/Root/Content/ConfirmView
@onready var _title_view: VBoxContainer = $Margin/Root/Content/TitleView
@onready var _confirm_message: Label = $Margin/Root/Content/ConfirmView/MessageLabel
@onready var _confirm_button: Button = $Margin/Root/Content/ConfirmView/Buttons/ConfirmButton
@onready var _volume_slider: HSlider = $Margin/Root/Content/SettingsView/VolumeRow/VolumeSlider
@onready var _volume_label: Label = $Margin/Root/Content/SettingsView/VolumeRow/VolumeLabel
@onready var _fullscreen_check: CheckBox = $Margin/Root/Content/SettingsView/FullscreenCheck
@onready var _load_game_button: Button = $Margin/Root/Content/TitleView/LoadGameButton
var _view_mode: ViewMode = ViewMode.SYSTEM
var _confirm_return_view: ViewMode = ViewMode.SYSTEM


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	_close_button.pressed.connect(_on_continue_pressed)
	$Margin/Root/Content/SystemView/ContinueButton.pressed.connect(_on_continue_pressed)
	$Margin/Root/Content/SystemView/SettingsButton.pressed.connect(_on_settings_pressed)
	$Margin/Root/Content/SystemView/ReturnTitleButton.pressed.connect(_on_return_title_pressed)
	$Margin/Root/Content/SystemView/QuitButton.pressed.connect(_on_quit_pressed)
	$Margin/Root/Content/SettingsView/BackButton.pressed.connect(_on_settings_back_pressed)
	_volume_slider.value_changed.connect(_on_master_volume_changed)
	_fullscreen_check.toggled.connect(_on_fullscreen_toggled)
	$Margin/Root/Content/ConfirmView/Buttons/CancelButton.pressed.connect(_on_confirm_cancel_pressed)
	$Margin/Root/Content/TitleView/NewGameButton.pressed.connect(_on_new_game_pressed)
	_load_game_button.pressed.connect(_on_load_game_pressed)
	$Margin/Root/Content/TitleView/TitleQuitButton.pressed.connect(_on_quit_pressed)


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


func _refresh() -> void:
	_system_view.visible = _view_mode == ViewMode.SYSTEM
	_settings_view.visible = _view_mode == ViewMode.SETTINGS
	_confirm_view.visible = _view_mode == ViewMode.CONFIRM_RETURN_TITLE or _view_mode == ViewMode.CONFIRM_QUIT
	_title_view.visible = _view_mode == ViewMode.TITLE
	_close_button.visible = _view_mode == ViewMode.SYSTEM or _view_mode == ViewMode.SETTINGS
	match _view_mode:
		ViewMode.SYSTEM:
			_title_label.text = "系统"
		ViewMode.SETTINGS:
			_title_label.text = "设置"
			_volume_slider.set_value_no_signal(_get_master_volume_percent())
			_volume_label.text = "%d%%" % int(round(_volume_slider.value))
			_fullscreen_check.set_pressed_no_signal(DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN)
		ViewMode.CONFIRM_RETURN_TITLE:
			_title_label.text = "返回标题"
			_confirm_message.text = "返回标题将丢失未保存的进度。"
			_confirm_button.text = "确认返回"
		ViewMode.CONFIRM_QUIT:
			_title_label.text = "退出游戏"
			_confirm_message.text = "退出游戏将丢失未保存的进度。"
			_confirm_button.text = "确认退出"
		ViewMode.TITLE:
			_title_label.text = "Aftertale"
			_load_game_button.disabled = not SaveManager.has_save()
	if _confirm_button.pressed.is_connected(_on_confirm_return_title_pressed):
		_confirm_button.pressed.disconnect(_on_confirm_return_title_pressed)
	if _confirm_button.pressed.is_connected(_on_confirm_quit_pressed):
		_confirm_button.pressed.disconnect(_on_confirm_quit_pressed)
	if _view_mode == ViewMode.CONFIRM_RETURN_TITLE:
		_confirm_button.pressed.connect(_on_confirm_return_title_pressed)
	elif _view_mode == ViewMode.CONFIRM_QUIT:
		_confirm_button.pressed.connect(_on_confirm_quit_pressed)


func _apply_window_size(size: Vector2) -> void:
	set_anchors_preset(Control.PRESET_CENTER)
	offset_left = -size.x * 0.5
	offset_top = -size.y * 0.5
	offset_right = size.x * 0.5
	offset_bottom = size.y * 0.5
	custom_minimum_size = size


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

extends Control

const CONFIG_PATH := "res://tools/art/catalogs/portrait_avatar_crops.json"
const SOURCE_VIEW_SIZE := 512
const PREVIEW_SIZE := 256

var _config: Dictionary = {}
var _entries: Array = []
var _selected_index := -1
var _source_image: Image
var _working_image: Image
var _source_display_rect := Rect2()
var _syncing_controls := false

@onready var _source_view: TextureRect = $Root/LeftPanel/PreviewRow/SourceColumn/SourceView
@onready var _avatar_view: TextureRect = $Root/LeftPanel/PreviewRow/AvatarColumn/AvatarView
@onready var _entry_list: ItemList = $Root/RightPanel/EntryList
@onready var _details: TextEdit = $Root/RightPanel/Details
@onready var _center_x: SpinBox = $Root/RightPanel/CenterXRow/Spin
@onready var _center_y: SpinBox = $Root/RightPanel/CenterYRow/Spin
@onready var _crop_size: SpinBox = $Root/RightPanel/CropSizeRow/Spin
@onready var _remove_background: CheckBox = $Root/RightPanel/BackgroundRow/RemoveBackground
@onready var _background_value: SpinBox = $Root/RightPanel/BackgroundValueRow/Spin
@onready var _background_saturation: SpinBox = $Root/RightPanel/BackgroundSaturationRow/Spin
@onready var _status_label: Label = $Root/LeftPanel/Status


func _ready() -> void:
	_load_config()
	_connect_ui()
	_refresh_entry_list()
	_select_first_entry()


func _connect_ui() -> void:
	_source_view.gui_input.connect(_on_source_view_gui_input)
	_entry_list.item_selected.connect(_select_entry)
	for control in [_center_x, _center_y, _crop_size]:
		control.value_changed.connect(func(_value: float) -> void:
			if not _syncing_controls:
				_update_previews()
		)
	_remove_background.toggled.connect(func(_enabled: bool) -> void:
		_refresh_working_image()
	)
	_background_value.value_changed.connect(func(_value: float) -> void:
		_refresh_working_image()
	)
	_background_saturation.value_changed.connect(func(_value: float) -> void:
		_refresh_working_image()
	)
	$Root/RightPanel/Actions/ReloadButton.pressed.connect(func() -> void:
		_load_config()
		_refresh_entry_list()
		_restore_selected_entry()
	)
	$Root/RightPanel/Actions/SaveButton.pressed.connect(_save_current_entry)
	$Root/RightPanel/Actions/GenerateButton.pressed.connect(func() -> void:
		_save_current_entry()
		_regenerate_avatar()
	)
	$Root/RightPanel/Actions/SaveTransparentButton.pressed.connect(_save_transparent_source)
	$Root/RightPanel/Navigation/PreviousButton.pressed.connect(func() -> void:
		_select_relative(-1)
	)
	$Root/RightPanel/Navigation/NextButton.pressed.connect(func() -> void:
		_select_relative(1)
	)


func _load_config() -> void:
	var file := FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if file == null:
		_config = {"version": 1, "output_size": 256, "entries": []}
	else:
		var parsed: Variant = JSON.parse_string(file.get_as_text())
		_config = parsed as Dictionary if parsed is Dictionary else {}
	_entries = _config.get("entries", []) as Array


func _refresh_entry_list() -> void:
	_entry_list.clear()
	for entry_value in _entries:
		var entry: Dictionary = entry_value as Dictionary
		_entry_list.add_item("%s  [%s]" % [str(entry.get("id", "portrait")), str(entry.get("role", ""))])


func _select_first_entry() -> void:
	if _entry_list.item_count > 0:
		_entry_list.select(0)
		_select_entry(0)


func _restore_selected_entry() -> void:
	if _entry_list.item_count <= 0:
		return
	_select_entry(clampi(_selected_index, 0, _entry_list.item_count - 1))


func _select_entry(index: int) -> void:
	_selected_index = clampi(index, 0, _entries.size() - 1)
	_load_selected_source()
	_load_entry_controls()
	_update_details()
	_refresh_working_image()


func _select_relative(delta: int) -> void:
	if _entry_list.item_count <= 0:
		return
	var index: int = clampi(_selected_index + delta, 0, _entry_list.item_count - 1)
	_entry_list.select(index)
	_entry_list.ensure_current_is_visible()
	_select_entry(index)


func _entry() -> Dictionary:
	if _selected_index < 0 or _selected_index >= _entries.size():
		return {}
	return _entries[_selected_index] as Dictionary


func _load_selected_source() -> void:
	_source_image = Image.new()
	var source_path: String = _resource_path(str(_entry().get("source", "")))
	if source_path.is_empty() or _source_image.load(source_path) != OK:
		_set_status("Missing portrait source: %s" % source_path)
		return
	if _source_image.get_format() != Image.FORMAT_RGBA8:
		_source_image.convert(Image.FORMAT_RGBA8)


func _load_entry_controls() -> void:
	var entry: Dictionary = _entry()
	var center: Dictionary = entry.get("center", {}) as Dictionary
	_syncing_controls = true
	_center_x.value = float(center.get("x", 0.5))
	_center_y.value = float(center.get("y", 0.2))
	_crop_size.value = float(entry.get("crop_size", 0.34))
	_remove_background.button_pressed = bool(entry.get("remove_background", true))
	_background_value.value = float(entry.get("background_value", 0.72))
	_background_saturation.value = float(entry.get("background_saturation", 0.16))
	_syncing_controls = false


func _refresh_working_image() -> void:
	if _source_image == null or _source_image.is_empty():
		_working_image = Image.new()
	elif _remove_background.button_pressed:
		_working_image = ImageBackgroundCleaner.remove_light_edge_background(
			_source_image,
			float(_background_value.value),
			float(_background_saturation.value)
		)
	else:
		_working_image = _source_image.duplicate()
	_update_previews()


func _update_details() -> void:
	var entry: Dictionary = _entry()
	_details.text = "\n".join([
		"id: %s" % str(entry.get("id", "")),
		"role: %s" % str(entry.get("role", "")),
		"source: %s" % str(entry.get("source", "")),
		"avatar: %s" % str(entry.get("output", "")),
		"output_size: %s" % str(_config.get("output_size", 256)),
	])


func _update_previews() -> void:
	_update_source_preview()
	_update_avatar_preview()


func _update_source_preview() -> void:
	var display := _checker_image(SOURCE_VIEW_SIZE)
	if _working_image != null and not _working_image.is_empty():
		var source_copy: Image = _working_image.duplicate()
		var scale: float = minf(
			float(SOURCE_VIEW_SIZE) / float(source_copy.get_width()),
			float(SOURCE_VIEW_SIZE) / float(source_copy.get_height())
		)
		var display_size := Vector2i(
			maxi(1, int(round(source_copy.get_width() * scale))),
			maxi(1, int(round(source_copy.get_height() * scale)))
		)
		source_copy.resize(display_size.x, display_size.y, Image.INTERPOLATE_LANCZOS)
		var destination := Vector2i(
			int(round(float(SOURCE_VIEW_SIZE - display_size.x) * 0.5)),
			int(round(float(SOURCE_VIEW_SIZE - display_size.y) * 0.5))
		)
		_source_display_rect = Rect2(Vector2(destination), Vector2(display_size))
		display.blend_rect(source_copy, Rect2i(Vector2i.ZERO, display_size), destination)
		_draw_crop_box(display)
	else:
		_source_display_rect = Rect2()
	_source_view.texture = ImageTexture.create_from_image(display)


func _update_avatar_preview() -> void:
	var display := _checker_image(PREVIEW_SIZE)
	var avatar: Image = _make_avatar_image()
	if not avatar.is_empty():
		var preview: Image = avatar.duplicate()
		preview.resize(PREVIEW_SIZE, PREVIEW_SIZE, Image.INTERPOLATE_LANCZOS)
		display.blend_rect(preview, Rect2i(0, 0, PREVIEW_SIZE, PREVIEW_SIZE), Vector2i.ZERO)
	_avatar_view.texture = ImageTexture.create_from_image(display)


func _make_avatar_image() -> Image:
	if _working_image == null or _working_image.is_empty():
		return Image.new()
	var avatar: Image = _working_image.get_region(_source_crop_rect())
	var output_size: int = int(_config.get("output_size", 256))
	avatar.resize(output_size, output_size, Image.INTERPOLATE_LANCZOS)
	return avatar


func _source_crop_rect() -> Rect2i:
	var source_size := Vector2i(_working_image.get_width(), _working_image.get_height())
	var crop_pixels: int = maxi(1, int(round(mini(source_size.x, source_size.y) * float(_crop_size.value))))
	crop_pixels = mini(crop_pixels, mini(source_size.x, source_size.y))
	var center := Vector2(source_size.x * float(_center_x.value), source_size.y * float(_center_y.value))
	return Rect2i(
		clampi(int(round(center.x - crop_pixels * 0.5)), 0, source_size.x - crop_pixels),
		clampi(int(round(center.y - crop_pixels * 0.5)), 0, source_size.y - crop_pixels),
		crop_pixels,
		crop_pixels
	)


func _on_source_view_gui_input(event: InputEvent) -> void:
	var local_position := Vector2.INF
	if event is InputEventMouseButton:
		var mouse_button := event as InputEventMouseButton
		if mouse_button.button_index == MOUSE_BUTTON_LEFT and mouse_button.pressed:
			local_position = mouse_button.position
	elif event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if (motion.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
			local_position = motion.position
	if local_position == Vector2.INF or _source_display_rect.size.x <= 0.0:
		return
	var texture_size := Vector2(SOURCE_VIEW_SIZE, SOURCE_VIEW_SIZE)
	var scale: float = minf(_source_view.size.x / texture_size.x, _source_view.size.y / texture_size.y)
	var display_position: Vector2 = (local_position - (_source_view.size - texture_size * scale) * 0.5) / maxf(scale, 0.001)
	if not _source_display_rect.has_point(display_position):
		return
	var normalized: Vector2 = (display_position - _source_display_rect.position) / _source_display_rect.size
	_syncing_controls = true
	_center_x.value = clampf(normalized.x, 0.0, 1.0)
	_center_y.value = clampf(normalized.y, 0.0, 1.0)
	_syncing_controls = false
	_update_previews()


func _save_current_entry() -> void:
	var entry: Dictionary = _entry()
	entry["center"] = {"x": snappedf(_center_x.value, 0.001), "y": snappedf(_center_y.value, 0.001)}
	entry["crop_size"] = snappedf(_crop_size.value, 0.001)
	entry["remove_background"] = _remove_background.button_pressed
	entry["background_value"] = snappedf(_background_value.value, 0.01)
	entry["background_saturation"] = snappedf(_background_saturation.value, 0.01)
	_entries[_selected_index] = entry
	_config["entries"] = _entries
	var file := FileAccess.open(CONFIG_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(_config, "\t"))
		_set_status("Saved avatar crop: %s" % str(entry.get("id", "")))


func _regenerate_avatar() -> void:
	var output_path: String = _resource_path(str(_entry().get("output", "")))
	var avatar: Image = _make_avatar_image()
	if output_path.is_empty() or avatar.is_empty():
		return
	var global_output: String = ProjectSettings.globalize_path(output_path)
	DirAccess.make_dir_recursive_absolute(global_output.get_base_dir())
	if avatar.save_png(global_output) == OK:
		_set_status("Generated square avatar: %s" % output_path)


func regenerate_all_avatars() -> void:
	for index in range(_entries.size()):
		_select_entry(index)
		_regenerate_avatar()


func _save_transparent_source() -> void:
	if _working_image == null or _working_image.is_empty():
		return
	var source_path: String = _resource_path(str(_entry().get("source", "")))
	if _working_image.save_png(ProjectSettings.globalize_path(source_path)) == OK:
		_source_image = _working_image.duplicate()
		_set_status("Saved transparent portrait source: %s" % source_path)


func _checker_image(size: int) -> Image:
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in range(size):
		for x in range(size):
			var light: bool = ((x / 24) + (y / 24)) % 2 == 0
			image.set_pixel(x, y, Color(0.84, 0.81, 0.73) if light else Color(0.95, 0.92, 0.84))
	return image


func _draw_crop_box(display: Image) -> void:
	var crop: Rect2i = _source_crop_rect()
	var scale: float = _source_display_rect.size.x / float(_working_image.get_width())
	var rect := Rect2(_source_display_rect.position + Vector2(crop.position) * scale, Vector2(crop.size) * scale)
	for x in range(int(rect.position.x), int(rect.end.x)):
		_set_preview_pixel(display, x, int(rect.position.y), Color.RED)
		_set_preview_pixel(display, x, int(rect.end.y), Color.RED)
	for y in range(int(rect.position.y), int(rect.end.y)):
		_set_preview_pixel(display, int(rect.position.x), y, Color.RED)
		_set_preview_pixel(display, int(rect.end.x), y, Color.RED)


func _set_preview_pixel(image: Image, x: int, y: int, color: Color) -> void:
	if x >= 0 and y >= 0 and x < image.get_width() and y < image.get_height():
		image.set_pixel(x, y, color)


func _resource_path(path: String) -> String:
	if path.is_empty() or path.begins_with("res://") or path.is_absolute_path():
		return path
	return "res://%s" % path


func _set_status(text: String) -> void:
	_status_label.text = text
	print(text)

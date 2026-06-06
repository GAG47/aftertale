extends Control

const CONFIG_PATH := "res://tools/art/catalogs/portrait_badge_crops.json"
const SOURCE_VIEW_SIZE := 512
const BADGE_INSET := 8

class PreviewTextureRect:
	extends TextureRect

	var owner_tool: Control

	func _gui_input(event: InputEvent) -> void:
		if owner_tool == null:
			return
		if event is InputEventMouseButton:
			var mouse_button := event as InputEventMouseButton
			if mouse_button.button_index == MOUSE_BUTTON_LEFT and mouse_button.pressed:
				owner_tool.call("_set_crop_center_from_source_view", mouse_button.position)
				accept_event()
		elif event is InputEventMouseMotion:
			var motion := event as InputEventMouseMotion
			if (motion.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
				owner_tool.call("_set_crop_center_from_source_view", motion.position)
				accept_event()

var _config: Dictionary = {}
var _entries: Array = []
var _selected_index := -1
var _source_image: Image
var _source_display_source_rect := Rect2()
var _syncing_controls := false

var _source_view: TextureRect
var _badge_view: TextureRect
var _entry_list: ItemList
var _details: TextEdit
var _center_x_slider: HSlider
var _center_x_spin: SpinBox
var _center_y_slider: HSlider
var _center_y_spin: SpinBox
var _crop_size_slider: HSlider
var _crop_size_spin: SpinBox
var _badge_zoom_slider: HSlider
var _badge_zoom_spin: SpinBox
var _ring_edit: LineEdit
var _highlight_edit: LineEdit
var _status_label: Label


func _ready() -> void:
	_load_config()
	_build_ui()
	_refresh_entry_list()
	_select_first_entry()
	_set_status("Ready. Drag the crop box or tune sliders, then Save + Regenerate.")


func _load_config() -> void:
	if not FileAccess.file_exists(CONFIG_PATH):
		_config = {
			"version": 1,
			"output_size": 128,
			"entries": [],
		}
		_entries = []
		return
	var file := FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if file == null:
		push_warning("Could not open portrait badge crop config.")
		_config = {}
		_entries = []
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		_config = parsed as Dictionary
	else:
		_config = {}
	_entries = _config.get("entries", [])
	if not (_entries is Array):
		_entries = []


func _build_ui() -> void:
	var root := HBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 12)
	root.offset_left = 12
	root.offset_top = 12
	root.offset_right = -12
	root.offset_bottom = -12
	add_child(root)

	var left_panel := VBoxContainer.new()
	left_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(left_panel)

	var title := Label.new()
	title.text = "Portrait Badge Fitter"
	title.add_theme_font_size_override("font_size", 22)
	left_panel.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Drag the crop square on the portrait. The circular badge preview updates immediately; save only when it looks right."
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left_panel.add_child(subtitle)

	var preview_row := HBoxContainer.new()
	preview_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview_row.add_theme_constant_override("separation", 12)
	left_panel.add_child(preview_row)

	var source_column := VBoxContainer.new()
	source_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	source_column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview_row.add_child(source_column)

	var source_label := Label.new()
	source_label.text = "Source Crop"
	source_column.add_child(source_label)

	_source_view = PreviewTextureRect.new()
	(_source_view as PreviewTextureRect).owner_tool = self
	_source_view.custom_minimum_size = Vector2(520, 520)
	_source_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_source_view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_source_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_source_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	source_column.add_child(_source_view)

	var badge_column := VBoxContainer.new()
	badge_column.custom_minimum_size = Vector2(260, 0)
	badge_column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview_row.add_child(badge_column)

	var badge_label := Label.new()
	badge_label.text = "Badge Preview"
	badge_column.add_child(badge_label)

	_badge_view = TextureRect.new()
	_badge_view.custom_minimum_size = Vector2(240, 240)
	_badge_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_badge_view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_badge_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_badge_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	badge_column.add_child(_badge_view)

	_status_label = Label.new()
	_status_label.text = ""
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left_panel.add_child(_status_label)

	var right_panel := VBoxContainer.new()
	right_panel.custom_minimum_size = Vector2(420, 0)
	right_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(right_panel)

	_entry_list = ItemList.new()
	_entry_list.custom_minimum_size = Vector2(0, 210)
	_entry_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_entry_list.item_selected.connect(func(index: int) -> void:
		_select_entry(index)
	)
	right_panel.add_child(_entry_list)

	_details = TextEdit.new()
	_details.custom_minimum_size = Vector2(0, 110)
	_details.editable = false
	_details.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	right_panel.add_child(_details)

	_center_x_slider = _make_slider(0.0, 1.0, 0.001)
	_center_x_spin = _make_spin(0.0, 1.0, 0.001, 3)
	right_panel.add_child(_make_control_row("Center X", _center_x_slider, _center_x_spin))

	_center_y_slider = _make_slider(0.0, 1.0, 0.001)
	_center_y_spin = _make_spin(0.0, 1.0, 0.001, 3)
	right_panel.add_child(_make_control_row("Center Y", _center_y_slider, _center_y_spin))

	_crop_size_slider = _make_slider(0.05, 1.0, 0.001)
	_crop_size_spin = _make_spin(0.05, 1.0, 0.001, 3)
	right_panel.add_child(_make_control_row("Crop Size", _crop_size_slider, _crop_size_spin))

	_badge_zoom_slider = _make_slider(1.0, 5.0, 0.1)
	_badge_zoom_spin = _make_spin(1.0, 5.0, 0.1, 1)
	right_panel.add_child(_make_control_row("Preview Zoom", _badge_zoom_slider, _badge_zoom_spin))

	_bind_pair(_center_x_slider, _center_x_spin)
	_bind_pair(_center_y_slider, _center_y_spin)
	_bind_pair(_crop_size_slider, _crop_size_spin)
	_bind_pair(_badge_zoom_slider, _badge_zoom_spin, false)

	right_panel.add_child(_make_color_row("Ring", true))
	right_panel.add_child(_make_color_row("Highlight", false))

	var action_row := HBoxContainer.new()
	right_panel.add_child(action_row)

	var reload_button := Button.new()
	reload_button.text = "Reload"
	reload_button.pressed.connect(func() -> void:
		_load_config()
		_refresh_entry_list()
		_restore_selected_entry()
	)
	action_row.add_child(reload_button)

	var save_button := Button.new()
	save_button.text = "Save"
	save_button.pressed.connect(_save_current_entry)
	action_row.add_child(save_button)

	var generate_button := Button.new()
	generate_button.text = "Save + Regenerate"
	generate_button.pressed.connect(func() -> void:
		_save_current_entry()
		_regenerate_selected_badge()
	)
	action_row.add_child(generate_button)

	var nav_row := HBoxContainer.new()
	right_panel.add_child(nav_row)

	var previous_button := Button.new()
	previous_button.text = "Previous"
	previous_button.pressed.connect(func() -> void:
		_select_relative(-1)
	)
	nav_row.add_child(previous_button)

	var next_button := Button.new()
	next_button.text = "Next"
	next_button.pressed.connect(func() -> void:
		_select_relative(1)
	)
	nav_row.add_child(next_button)


func _make_slider(minimum: float, maximum: float, step: float) -> HSlider:
	var slider := HSlider.new()
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = step
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return slider


func _make_spin(minimum: float, maximum: float, step: float, decimals: int) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = minimum
	spin.max_value = maximum
	spin.step = step
	spin.allow_greater = true
	spin.allow_lesser = true
	spin.custom_minimum_size = Vector2(96, 0)
	spin.get_line_edit().select_all_on_focus = true
	spin.rounded = decimals == 0
	return spin


func _make_control_row(label_text: String, slider: HSlider, spin: SpinBox) -> HBoxContainer:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(94, 0)
	row.add_child(label)
	row.add_child(slider)
	row.add_child(spin)
	return row


func _make_color_row(label_text: String, is_ring: bool) -> HBoxContainer:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(94, 0)
	row.add_child(label)
	var edit := LineEdit.new()
	edit.placeholder_text = "#ffffff"
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.text_changed.connect(func(_value: String) -> void:
		if not _syncing_controls:
			_update_previews()
	)
	row.add_child(edit)
	if is_ring:
		_ring_edit = edit
	else:
		_highlight_edit = edit
	return row


func _bind_pair(slider: HSlider, spin: SpinBox, update_badge_size: bool = true) -> void:
	slider.value_changed.connect(func(value: float) -> void:
		if _syncing_controls:
			return
		_syncing_controls = true
		spin.value = value
		_syncing_controls = false
		if update_badge_size:
			_update_previews()
		else:
			_update_badge_view_size()
	)
	spin.value_changed.connect(func(value: float) -> void:
		if _syncing_controls:
			return
		_syncing_controls = true
		slider.value = value
		_syncing_controls = false
		if update_badge_size:
			_update_previews()
		else:
			_update_badge_view_size()
	)


func _refresh_entry_list() -> void:
	if _entry_list == null:
		return
	_entry_list.clear()
	for i in _entries.size():
		var entry := _entry_at(i)
		var display := "%s  [%s]" % [
			str(entry.get("id", "portrait")),
			str(entry.get("role", "")),
		]
		_entry_list.add_item(display)


func _select_first_entry() -> void:
	if _entry_list == null or _entry_list.item_count <= 0:
		return
	_entry_list.select(0)
	_select_entry(0)


func _restore_selected_entry() -> void:
	if _entry_list == null or _entry_list.item_count <= 0:
		_selected_index = -1
		_update_previews()
		return
	var index := clampi(_selected_index, 0, _entry_list.item_count - 1)
	_entry_list.select(index)
	_select_entry(index)


func _select_entry(index: int) -> void:
	_selected_index = clampi(index, 0, _entries.size() - 1)
	_load_selected_source()
	_load_entry_controls()
	_update_details()
	_update_previews()


func _select_relative(delta: int) -> void:
	if _entry_list.item_count <= 0:
		return
	var index := _selected_index + delta
	index = clampi(index, 0, _entry_list.item_count - 1)
	_entry_list.select(index)
	_entry_list.ensure_current_is_visible()
	_select_entry(index)


func _entry_at(index: int) -> Dictionary:
	if index < 0 or index >= _entries.size():
		return {}
	var value: Variant = _entries[index]
	if value is Dictionary:
		return value as Dictionary
	return {}


func _load_selected_source() -> void:
	_source_image = Image.new()
	var entry := _entry_at(_selected_index)
	var source_path := _resource_path(str(entry.get("source", "")))
	if source_path.is_empty():
		_set_status("Selected entry has no source path.")
		return
	var error := _source_image.load(source_path)
	if error != OK:
		_source_image = Image.new()
		_set_status("Missing portrait source: %s" % str(entry.get("source", "")))
		return
	if _source_image.get_format() != Image.FORMAT_RGBA8:
		_source_image.convert(Image.FORMAT_RGBA8)
	_set_status("Loaded %s (%sx%s)." % [
		str(entry.get("source", "")),
		str(_source_image.get_width()),
		str(_source_image.get_height()),
	])


func _load_entry_controls() -> void:
	var entry := _entry_at(_selected_index)
	var center: Dictionary = entry.get("center", {})
	_syncing_controls = true
	_center_x_slider.value = _number(center, "x", 0.5)
	_center_x_spin.value = _center_x_slider.value
	_center_y_slider.value = _number(center, "y", 0.2)
	_center_y_spin.value = _center_y_slider.value
	_crop_size_slider.value = _number(entry, "crop_size", 0.34)
	_crop_size_spin.value = _crop_size_slider.value
	_badge_zoom_slider.value = 2.0
	_badge_zoom_spin.value = 2.0
	_ring_edit.text = str(entry.get("ring", "#d9b86f"))
	_highlight_edit.text = str(entry.get("highlight", "#fff1bd"))
	_syncing_controls = false
	_update_badge_view_size()


func _update_details() -> void:
	if _details == null:
		return
	var entry := _entry_at(_selected_index)
	_details.text = "\n".join([
		"id: %s" % str(entry.get("id", "")),
		"role: %s" % str(entry.get("role", "")),
		"source: %s" % str(entry.get("source", "")),
		"output: %s" % str(entry.get("output", "")),
		"output_size: %s" % str(_config.get("output_size", 128)),
	])


func _update_previews() -> void:
	_update_source_preview()
	_update_badge_preview()


func _update_source_preview() -> void:
	if _source_view == null:
		return
	var display := Image.create(SOURCE_VIEW_SIZE, SOURCE_VIEW_SIZE, false, Image.FORMAT_RGBA8)
	_fill_checker(display)
	if _source_image != null and not _source_image.is_empty():
		var source_copy := _source_image.duplicate()
		var scale := minf(
			float(SOURCE_VIEW_SIZE) / float(source_copy.get_width()),
			float(SOURCE_VIEW_SIZE) / float(source_copy.get_height())
		)
		var display_size := Vector2i(
			maxi(1, int(round(float(source_copy.get_width()) * scale))),
			maxi(1, int(round(float(source_copy.get_height()) * scale)))
		)
		source_copy.resize(display_size.x, display_size.y, Image.INTERPOLATE_LANCZOS)
		var dest := Vector2i(
			int(round(float(SOURCE_VIEW_SIZE - display_size.x) * 0.5)),
			int(round(float(SOURCE_VIEW_SIZE - display_size.y) * 0.5))
		)
		_source_display_source_rect = Rect2(Vector2(dest), Vector2(display_size))
		display.blend_rect(source_copy, Rect2i(Vector2i.ZERO, display_size), dest)
		_draw_crop_box(display)
	else:
		_source_display_source_rect = Rect2()
	_source_view.texture = ImageTexture.create_from_image(display)


func _update_badge_preview() -> void:
	if _badge_view == null:
		return
	var badge := _make_badge_image()
	var display := Image.create(256, 256, false, Image.FORMAT_RGBA8)
	_fill_checker(display)
	if not badge.is_empty():
		var copy := badge.duplicate()
		copy.resize(192, 192, Image.INTERPOLATE_NEAREST)
		display.blend_rect(copy, Rect2i(0, 0, 192, 192), Vector2i(32, 32))
	_badge_view.texture = ImageTexture.create_from_image(display)


func _update_badge_view_size() -> void:
	if _badge_view == null or _badge_zoom_spin == null:
		return
	var size := 128.0 * float(_badge_zoom_spin.value)
	_badge_view.custom_minimum_size = Vector2(size, size)


func _draw_crop_box(display: Image) -> void:
	if _source_image == null or _source_image.is_empty():
		return
	var crop := _source_crop_rect()
	var scale := _source_display_source_rect.size.x / float(_source_image.get_width())
	var rect := Rect2(
		_source_display_source_rect.position + Vector2(crop.position) * scale,
		Vector2(crop.size) * scale
	)
	_draw_rect_outline(display, rect, Color(1.0, 0.12, 0.08, 0.95), 3)
	var center := rect.get_center()
	_draw_line(display, Vector2(center.x, rect.position.y), Vector2(center.x, rect.position.y + rect.size.y), Color(1.0, 0.12, 0.08, 0.85), 1)
	_draw_line(display, Vector2(rect.position.x, center.y), Vector2(rect.position.x + rect.size.x, center.y), Color(1.0, 0.12, 0.08, 0.85), 1)


func _set_crop_center_from_source_view(local_position: Vector2) -> void:
	if _source_image == null or _source_image.is_empty() or _source_view == null:
		return
	var texture_size := Vector2(SOURCE_VIEW_SIZE, SOURCE_VIEW_SIZE)
	var scale := minf(_source_view.size.x / texture_size.x, _source_view.size.y / texture_size.y)
	var drawn_size := texture_size * scale
	var offset := (_source_view.size - drawn_size) * 0.5
	var display_position := (local_position - offset) / maxf(scale, 0.001)
	if not _source_display_source_rect.has_point(display_position):
		return
	var normalized := (display_position - _source_display_source_rect.position) / _source_display_source_rect.size
	_syncing_controls = true
	_center_x_slider.value = clampf(normalized.x, 0.0, 1.0)
	_center_x_spin.value = _center_x_slider.value
	_center_y_slider.value = clampf(normalized.y, 0.0, 1.0)
	_center_y_spin.value = _center_y_slider.value
	_syncing_controls = false
	_update_previews()


func _make_badge_image() -> Image:
	var output_size := int(_config.get("output_size", 128))
	var badge := Image.create(output_size, output_size, false, Image.FORMAT_RGBA8)
	badge.fill(Color.TRANSPARENT)
	if _source_image == null or _source_image.is_empty():
		return badge

	var crop := _source_image.get_region(_source_crop_rect())
	var target_size := maxi(1, output_size - BADGE_INSET * 2)
	crop.resize(target_size, target_size, Image.INTERPOLATE_LANCZOS)
	badge.blend_rect(crop, Rect2i(0, 0, target_size, target_size), Vector2i(BADGE_INSET, BADGE_INSET))
	_apply_circle_mask(badge, float(output_size) * 0.5 - float(BADGE_INSET))
	_draw_circle_stroke(badge, float(output_size) * 0.5 - 6.0, 8.0, _color_from_hex(_ring_edit.text, Color(0.22, 0.16, 0.12, 1.0)))
	_draw_arc_stroke(badge, float(output_size) * 0.5 - 15.0, 3.0, deg_to_rad(210.0), deg_to_rad(330.0), _color_from_hex(_highlight_edit.text, Color(0.95, 0.86, 0.62, 1.0)))
	return badge


func _source_crop_rect() -> Rect2i:
	if _source_image == null or _source_image.is_empty():
		return Rect2i()
	var source_size := Vector2i(_source_image.get_width(), _source_image.get_height())
	var min_dimension := mini(source_size.x, source_size.y)
	var crop_size := maxi(1, int(round(float(min_dimension) * float(_crop_size_spin.value))))
	crop_size = mini(crop_size, mini(source_size.x, source_size.y))
	var center := Vector2(
		float(source_size.x) * float(_center_x_spin.value),
		float(source_size.y) * float(_center_y_spin.value)
	)
	var x := clampi(int(round(center.x - float(crop_size) * 0.5)), 0, source_size.x - crop_size)
	var y := clampi(int(round(center.y - float(crop_size) * 0.5)), 0, source_size.y - crop_size)
	return Rect2i(x, y, crop_size, crop_size)


func _save_current_entry() -> void:
	if _selected_index < 0 or _selected_index >= _entries.size():
		return
	var entry := _entry_at(_selected_index)
	entry["center"] = {
		"x": snappedf(float(_center_x_spin.value), 0.001),
		"y": snappedf(float(_center_y_spin.value), 0.001),
	}
	entry["crop_size"] = snappedf(float(_crop_size_spin.value), 0.001)
	entry["ring"] = _normalized_hex(_ring_edit.text, str(entry.get("ring", "#d9b86f")))
	entry["highlight"] = _normalized_hex(_highlight_edit.text, str(entry.get("highlight", "#fff1bd")))
	_entries[_selected_index] = entry
	_config["entries"] = _entries
	if _write_config():
		_set_status("Saved crop settings for %s." % str(entry.get("id", "")))


func _write_config() -> bool:
	var global_path := ProjectSettings.globalize_path(CONFIG_PATH)
	DirAccess.make_dir_recursive_absolute(global_path.get_base_dir())
	var file := FileAccess.open(CONFIG_PATH, FileAccess.WRITE)
	if file == null:
		_set_status("Could not write crop config.")
		return false
	file.store_string(JSON.stringify(_config, "\t"))
	return true


func _regenerate_selected_badge() -> void:
	if _selected_index < 0 or _selected_index >= _entries.size():
		return
	if _source_image == null or _source_image.is_empty():
		_set_status("Cannot regenerate: portrait source is missing.")
		return
	var entry := _entry_at(_selected_index)
	var output_path := _resource_path(str(entry.get("output", "")))
	if output_path.is_empty():
		_set_status("Cannot regenerate: output path is missing.")
		return
	var global_output := ProjectSettings.globalize_path(output_path)
	DirAccess.make_dir_recursive_absolute(global_output.get_base_dir())
	var badge := _make_badge_image()
	var error := badge.save_png(global_output)
	if error != OK:
		_set_status("Could not save badge: %s" % str(entry.get("output", "")))
		return
	_set_status("Regenerated badge: %s." % str(entry.get("output", "")))


func _fill_checker(image: Image) -> void:
	for y in image.get_height():
		for x in image.get_width():
			var checker := ((x / 24) + (y / 24)) % 2 == 0
			image.set_pixel(x, y, Color(0.84, 0.81, 0.73, 1.0) if checker else Color(0.95, 0.92, 0.84, 1.0))


func _apply_circle_mask(image: Image, radius: float) -> void:
	var center := Vector2(float(image.get_width()) * 0.5, float(image.get_height()) * 0.5)
	for y in image.get_height():
		for x in image.get_width():
			var distance := (Vector2(float(x) + 0.5, float(y) + 0.5) - center).length()
			if distance <= radius:
				continue
			var pixel := image.get_pixel(x, y)
			if distance >= radius + 1.0:
				pixel.a = 0.0
			else:
				pixel.a *= clampf(radius + 1.0 - distance, 0.0, 1.0)
			image.set_pixel(x, y, pixel)


func _draw_circle_stroke(image: Image, radius: float, width: float, color: Color) -> void:
	var center := Vector2(float(image.get_width()) * 0.5, float(image.get_height()) * 0.5)
	for y in image.get_height():
		for x in image.get_width():
			var distance := (Vector2(float(x) + 0.5, float(y) + 0.5) - center).length()
			var coverage := _stroke_coverage(distance, radius, width)
			if coverage > 0.0:
				_blend_pixel(image, x, y, color, coverage)


func _draw_arc_stroke(image: Image, radius: float, width: float, start_angle: float, end_angle: float, color: Color) -> void:
	var center := Vector2(float(image.get_width()) * 0.5, float(image.get_height()) * 0.5)
	for y in image.get_height():
		for x in image.get_width():
			var delta := Vector2(float(x) + 0.5, float(y) + 0.5) - center
			var distance := delta.length()
			var coverage := _stroke_coverage(distance, radius, width)
			if coverage <= 0.0:
				continue
			var angle := atan2(delta.y, delta.x)
			if angle < 0.0:
				angle += TAU
			if _angle_between(angle, start_angle, end_angle):
				_blend_pixel(image, x, y, color, coverage)


func _stroke_coverage(distance: float, radius: float, width: float) -> float:
	var half_width := width * 0.5
	var delta := absf(distance - radius)
	if delta >= half_width + 1.0:
		return 0.0
	if delta <= half_width:
		return 1.0
	return clampf(half_width + 1.0 - delta, 0.0, 1.0)


func _angle_between(angle: float, start_angle: float, end_angle: float) -> bool:
	var start := fposmod(start_angle, TAU)
	var end := fposmod(end_angle, TAU)
	if start <= end:
		return angle >= start and angle <= end
	return angle >= start or angle <= end


func _draw_rect_outline(image: Image, rect: Rect2, color: Color, width: int) -> void:
	_draw_line(image, rect.position, rect.position + Vector2(rect.size.x, 0.0), color, width)
	_draw_line(image, rect.position + Vector2(0.0, rect.size.y), rect.position + rect.size, color, width)
	_draw_line(image, rect.position, rect.position + Vector2(0.0, rect.size.y), color, width)
	_draw_line(image, rect.position + Vector2(rect.size.x, 0.0), rect.position + rect.size, color, width)


func _draw_line(image: Image, from: Vector2, to: Vector2, color: Color, width: int) -> void:
	var distance := from.distance_to(to)
	var steps := maxi(1, int(ceil(distance)))
	for i in steps + 1:
		var point := from.lerp(to, float(i) / float(steps))
		for oy in range(-width, width + 1):
			for ox in range(-width, width + 1):
				var x := int(round(point.x)) + ox
				var y := int(round(point.y)) + oy
				if x >= 0 and y >= 0 and x < image.get_width() and y < image.get_height():
					_blend_pixel(image, x, y, color, 1.0)


func _blend_pixel(image: Image, x: int, y: int, color: Color, coverage: float) -> void:
	var source := color
	source.a *= coverage
	if source.a <= 0.0:
		return
	var destination := image.get_pixel(x, y)
	var out_alpha := source.a + destination.a * (1.0 - source.a)
	if out_alpha <= 0.0:
		image.set_pixel(x, y, Color.TRANSPARENT)
		return
	var out_color := Color(
		(source.r * source.a + destination.r * destination.a * (1.0 - source.a)) / out_alpha,
		(source.g * source.a + destination.g * destination.a * (1.0 - source.a)) / out_alpha,
		(source.b * source.a + destination.b * destination.a * (1.0 - source.a)) / out_alpha,
		out_alpha
	)
	image.set_pixel(x, y, out_color)


func _color_from_hex(text: String, fallback: Color) -> Color:
	var normalized := _normalized_hex(text, "")
	if normalized.is_empty():
		return fallback
	return Color.html(normalized)


func _normalized_hex(text: String, fallback: String) -> String:
	var value := text.strip_edges()
	if value.is_empty():
		return fallback
	if not value.begins_with("#"):
		value = "#%s" % value
	if value.length() != 7:
		return fallback
	for i in range(1, value.length()):
		var code := value.unicode_at(i)
		var valid := (code >= 48 and code <= 57) or (code >= 65 and code <= 70) or (code >= 97 and code <= 102)
		if not valid:
			return fallback
	return value.to_lower()


func _number(row: Dictionary, key: String, default_value: float) -> float:
	if row.is_empty() or not row.has(key):
		return default_value
	var value: Variant = row.get(key)
	if value == null:
		return default_value
	var text := str(value).strip_edges()
	if text.is_empty():
		return default_value
	return float(text)


func _resource_path(path: String) -> String:
	if path.is_empty():
		return ""
	if path.begins_with("res://") or path.is_absolute_path():
		return path
	return "res://%s" % path


func _set_status(text: String) -> void:
	if _status_label != null:
		_status_label.text = text
	print(text)

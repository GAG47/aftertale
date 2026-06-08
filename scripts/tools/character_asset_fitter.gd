extends Control

const CATALOG_PATH := "res://tools/art/catalogs/character_source_catalog.json"
const ADJUSTMENTS_PATH := "res://tools/art/catalogs/character_asset_adjustments.json"
const BATCH_ADJUSTMENTS_PATH := "res://tools/art/catalogs/character_batch_adjustments.json"
const COMMON_PARTS_PATH := "res://data/appearance/common_appearance_parts.json"
const CANVAS_SIZE := 256
const RUNTIME_SIZE := 64
const STANDARD_ANCHOR := Vector2i(128, 184)

var _catalog_rows: Array = []
var _adjustment_rows: Array = []
var _batch_adjustment_rows: Array = []
var _common_parts: Dictionary = {}
var _source_cache: Dictionary = {}
var _base_body: Image
var _base_head: Image
var _selected_row: Dictionary = {}
var _current_standardized: Image
var _syncing_controls := false

@onready var _preview_rect: TextureRect = $Root/LeftPanel/Preview
@onready var _part_filter: OptionButton = $Root/RightPanel/FilterRow/PartFilter
@onready var _search_box: LineEdit = $Root/RightPanel/FilterRow/SearchBox
@onready var _asset_list: ItemList = $Root/RightPanel/AssetList
@onready var _details: TextEdit = $Root/RightPanel/Details
@onready var _offset_x_slider: HSlider = $Root/RightPanel/OffsetXRow/Slider
@onready var _offset_x_spin: SpinBox = $Root/RightPanel/OffsetXRow/Spin
@onready var _offset_y_slider: HSlider = $Root/RightPanel/OffsetYRow/Slider
@onready var _offset_y_spin: SpinBox = $Root/RightPanel/OffsetYRow/Spin
@onready var _scale_slider: HSlider = $Root/RightPanel/ScaleRow/Slider
@onready var _scale_spin: SpinBox = $Root/RightPanel/ScaleRow/Spin
@onready var _status_label: Label = $Root/LeftPanel/Status


func _ready() -> void:
	_load_data()
	_connect_ui()
	_load_base_parts()
	_refresh_asset_list()
	_select_first_asset()
	_set_status("Ready. Select an asset, tune it on the standard body/head base, then Save + Regenerate.")


func _connect_ui() -> void:
	for part in ["all", "hair", "outfit", "accessory", "body", "head", "held_item"]:
		_part_filter.add_item(part)
	_part_filter.select(1)
	_part_filter.item_selected.connect(func(_index: int) -> void:
		_refresh_asset_list()
	)
	_search_box.text_changed.connect(func(_text: String) -> void:
		_refresh_asset_list()
	)
	_asset_list.item_selected.connect(_select_asset_from_list)
	_bind_pair(_offset_x_slider, _offset_x_spin)
	_bind_pair(_offset_y_slider, _offset_y_spin)
	_bind_pair(_scale_slider, _scale_spin)
	$Root/RightPanel/Actions/ReloadButton.pressed.connect(func() -> void:
		_load_selected_adjustment()
		_update_preview()
	)
	$Root/RightPanel/Actions/SaveButton.pressed.connect(_save_adjustment)
	$Root/RightPanel/Actions/GenerateButton.pressed.connect(func() -> void:
		_save_adjustment()
		_regenerate_runtime_texture()
	)
	$Root/RightPanel/Navigation/PreviousButton.pressed.connect(func() -> void:
		_select_relative(-1)
	)
	$Root/RightPanel/Navigation/NextButton.pressed.connect(func() -> void:
		_select_relative(1)
	)


func _load_data() -> void:
	_catalog_rows = _read_json_array(CATALOG_PATH)
	_adjustment_rows = _read_json_array(ADJUSTMENTS_PATH)
	_batch_adjustment_rows = _read_json_array(BATCH_ADJUSTMENTS_PATH)
	_common_parts = _read_json_dictionary(COMMON_PARTS_PATH)


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
	title.text = "Character Asset Fitter"
	title.add_theme_font_size_override("font_size", 22)
	left_panel.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Preview each source asset on the standard body + head base. Drag sliders for in-memory preview; save only when it looks right."
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left_panel.add_child(subtitle)

	_preview_rect = TextureRect.new()
	_preview_rect.custom_minimum_size = Vector2(560, 560)
	_preview_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_preview_rect.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_preview_rect.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_panel.add_child(_preview_rect)

	_status_label = Label.new()
	_status_label.text = ""
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left_panel.add_child(_status_label)

	var right_panel := VBoxContainer.new()
	right_panel.custom_minimum_size = Vector2(420, 0)
	right_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(right_panel)

	var filter_row := HBoxContainer.new()
	right_panel.add_child(filter_row)

	_part_filter = OptionButton.new()
	_part_filter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for part in ["all", "hair", "outfit", "accessory", "body", "head", "held_item"]:
		_part_filter.add_item(part)
	_part_filter.select(1)
	_part_filter.item_selected.connect(func(_index: int) -> void:
		_refresh_asset_list()
	)
	filter_row.add_child(_part_filter)

	_search_box = LineEdit.new()
	_search_box.placeholder_text = "asset/category/status"
	_search_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search_box.text_changed.connect(func(_text: String) -> void:
		_refresh_asset_list()
	)
	filter_row.add_child(_search_box)

	_asset_list = ItemList.new()
	_asset_list.custom_minimum_size = Vector2(0, 230)
	_asset_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_asset_list.item_selected.connect(func(index: int) -> void:
		_select_asset_from_list(index)
	)
	right_panel.add_child(_asset_list)

	_details = TextEdit.new()
	_details.custom_minimum_size = Vector2(0, 116)
	_details.editable = false
	_details.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	right_panel.add_child(_details)

	_offset_x_slider = _make_slider(-96.0, 96.0, 1.0)
	_offset_x_spin = _make_spin(-96.0, 96.0, 1.0, 0)
	right_panel.add_child(_make_control_row("Offset X", _offset_x_slider, _offset_x_spin))

	_offset_y_slider = _make_slider(-96.0, 96.0, 1.0)
	_offset_y_spin = _make_spin(-96.0, 96.0, 1.0, 0)
	right_panel.add_child(_make_control_row("Offset Y", _offset_y_slider, _offset_y_spin))

	_scale_slider = _make_slider(0.2, 2.0, 0.01)
	_scale_spin = _make_spin(0.2, 2.0, 0.01, 2)
	right_panel.add_child(_make_control_row("Scale", _scale_slider, _scale_spin))

	_bind_pair(_offset_x_slider, _offset_x_spin)
	_bind_pair(_offset_y_slider, _offset_y_spin)
	_bind_pair(_scale_slider, _scale_spin)

	var action_row := HBoxContainer.new()
	right_panel.add_child(action_row)

	var reload_button := Button.new()
	reload_button.text = "Reload Saved"
	reload_button.pressed.connect(func() -> void:
		_load_selected_adjustment()
		_update_preview()
	)
	action_row.add_child(reload_button)

	var save_button := Button.new()
	save_button.text = "Save Adjustment"
	save_button.pressed.connect(_save_adjustment)
	action_row.add_child(save_button)

	var generate_button := Button.new()
	generate_button.text = "Save + Regenerate"
	generate_button.pressed.connect(func() -> void:
		_save_adjustment()
		_regenerate_runtime_texture()
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
	spin.custom_minimum_size = Vector2(92, 0)
	spin.get_line_edit().select_all_on_focus = true
	spin.set("suffix", "")
	spin.rounded = decimals == 0
	return spin


func _make_control_row(label_text: String, slider: HSlider, spin: SpinBox) -> HBoxContainer:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(74, 0)
	row.add_child(label)
	row.add_child(slider)
	row.add_child(spin)
	return row


func _bind_pair(slider: HSlider, spin: SpinBox) -> void:
	slider.value_changed.connect(func(value: float) -> void:
		if _syncing_controls:
			return
		_syncing_controls = true
		spin.value = value
		_syncing_controls = false
		_update_preview()
	)
	spin.value_changed.connect(func(value: float) -> void:
		if _syncing_controls:
			return
		_syncing_controls = true
		slider.value = value
		_syncing_controls = false
		_update_preview()
	)


func _read_json_array(path: String) -> Array:
	var parsed: Variant = _read_json(path)
	if parsed is Array:
		return parsed as Array
	if parsed is Dictionary:
		if parsed.has("value") and parsed.has("Count"):
			var value: Variant = parsed.get("value")
			if value is Array:
				return value
		if parsed.has("SyncRoot") and parsed.has("Count"):
			var sync_root: Variant = parsed.get("SyncRoot")
			if sync_root is Array:
				return sync_root
	return []


func _read_json_dictionary(path: String) -> Dictionary:
	var parsed: Variant = _read_json(path)
	if parsed is Dictionary:
		return parsed as Dictionary
	return {}


func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		push_warning("Missing JSON: %s" % path)
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("Could not open JSON: %s" % path)
		return null
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed == null:
		push_warning("Could not parse JSON: %s" % path)
	return parsed


func _write_json_array(path: String, rows: Array) -> bool:
	var global_path := ProjectSettings.globalize_path(path)
	var directory := global_path.get_base_dir()
	DirAccess.make_dir_recursive_absolute(directory)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_set_status("Could not write JSON: %s" % path)
		return false
	file.store_string(JSON.stringify(rows, "\t"))
	return true


func _load_base_parts() -> void:
	_base_body = _load_runtime_layer("body")
	_base_head = _load_runtime_layer("head")


func _load_runtime_layer(layer_id: String) -> Image:
	var image := Image.create(CANVAS_SIZE, CANVAS_SIZE, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	var parts: Array = _common_parts.get("parts", [])
	for part_value in parts:
		if not (part_value is Dictionary):
			continue
		var part := part_value as Dictionary
		if str(part.get("layer", "")) != layer_id:
			continue
		var source := _resource_path(str(part.get("source", "")))
		var loaded := Image.new()
		if loaded.load(source) == OK:
			return loaded
	return image


func _refresh_asset_list() -> void:
	if _asset_list == null:
		return
	var selected_asset_id := str(_selected_row.get("asset_id", ""))
	_asset_list.clear()
	var filter := _part_filter.get_item_text(_part_filter.selected) if _part_filter != null else "all"
	var query := _search_box.text.to_lower() if _search_box != null else ""

	for row_value in _catalog_rows:
		if not (row_value is Dictionary):
			continue
		var row := row_value as Dictionary
		var part := str(row.get("standard_part", row.get("layer", "")))
		if filter != "all" and part != filter:
			continue
		var haystack := "%s %s %s %s %s %s" % [
			str(row.get("asset_id", "")),
			str(row.get("batch_id", "")),
			str(row.get("category", "")),
			str(row.get("layer", "")),
			str(row.get("review_status", row.get("status", ""))),
			str(row.get("source_path", "")),
		]
		if not query.is_empty() and not haystack.to_lower().contains(query):
			continue
		var display := "%s  [%s]  %s" % [
			str(row.get("asset_id", "")),
			part,
			str(row.get("batch_id", row.get("category", ""))),
		]
		_asset_list.add_item(display)
		var index := _asset_list.item_count - 1
		_asset_list.set_item_metadata(index, row)
		if str(row.get("asset_id", "")) == selected_asset_id:
			_asset_list.select(index)


func _select_first_asset() -> void:
	if _asset_list.item_count <= 0:
		return
	_asset_list.select(0)
	_select_asset_from_list(0)


func _select_asset_from_list(index: int) -> void:
	var metadata: Variant = _asset_list.get_item_metadata(index)
	if not (metadata is Dictionary):
		return
	_selected_row = (metadata as Dictionary).duplicate(true)
	_load_selected_adjustment()
	_update_details()
	_update_preview()


func _select_relative(delta: int) -> void:
	if _asset_list.item_count <= 0:
		return
	var current := _asset_list.get_selected_items()
	var index := 0
	if current.size() > 0:
		index = current[0]
	index = clampi(index + delta, 0, _asset_list.item_count - 1)
	_asset_list.select(index)
	_asset_list.ensure_current_is_visible()
	_select_asset_from_list(index)


func _load_selected_adjustment() -> void:
	var adjustment := _effective_adjustment_for_row(_selected_row)
	var offset_x := _adjustment_number(adjustment, "offset_x", 0.0)
	var offset_y := _adjustment_number(adjustment, "offset_y", 0.0)
	var scale := _adjustment_number(adjustment, "scale", 1.0)
	_syncing_controls = true
	_offset_x_slider.value = offset_x
	_offset_x_spin.value = offset_x
	_offset_y_slider.value = offset_y
	_offset_y_spin.value = offset_y
	_scale_slider.value = scale
	_scale_spin.value = scale
	_syncing_controls = false


func _update_details() -> void:
	var batch_adjustment := _get_batch_adjustment_row(_selected_row)
	var asset_adjustment := _get_adjustment_row(str(_selected_row.get("asset_id", "")))
	var adjustment := _effective_adjustment_for_row(_selected_row)
	_details.text = "\n".join([
		"asset_id: %s" % str(_selected_row.get("asset_id", "")),
		"batch_id: %s" % str(_selected_row.get("batch_id", "")),
		"part: %s" % _part_for_row(_selected_row),
		"layer: %s" % str(_selected_row.get("layer", "")),
		"category: %s" % str(_selected_row.get("category", "")),
		"status: %s" % str(_selected_row.get("review_status", _selected_row.get("status", ""))),
		"source: %s" % str(_selected_row.get("source_path", "")),
		"runtime: %s" % _runtime_output_path(_selected_row),
		"batch offset: %s, %s" % [
			str(batch_adjustment.get("offset_x", "")),
			str(batch_adjustment.get("offset_y", "")),
		],
		"batch scale: %s" % str(batch_adjustment.get("scale", "")),
		"asset offset: %s, %s" % [
			str(asset_adjustment.get("offset_x", "")),
			str(asset_adjustment.get("offset_y", "")),
		],
		"asset scale: %s" % str(asset_adjustment.get("scale", "")),
		"effective offset: %s, %s" % [
			str(adjustment.get("offset_x", "")),
			str(adjustment.get("offset_y", "")),
		],
		"effective scale: %s" % str(adjustment.get("scale", "")),
	])


func _update_preview() -> void:
	if _selected_row.is_empty() or _preview_rect == null:
		return
	var standardized := _standardize_selected_image(false)
	if standardized.is_empty():
		return
	_current_standardized = standardized
	var composite := _compose_preview(standardized, _part_for_row(_selected_row))
	var display := _make_display_image(composite)
	_preview_rect.texture = ImageTexture.create_from_image(display)


func _standardize_selected_image(use_saved_adjustment: bool) -> Image:
	var source_path := _resource_path(str(_selected_row.get("source_path", "")))
	if source_path.is_empty():
		_set_status("Selected asset has no source_path.")
		return Image.new()
	var cache := _get_source_cache(str(_selected_row.get("asset_id", "")), source_path)
	if cache.is_empty():
		return Image.new()
	var source: Image = cache.get("image")
	var bounds := Rect2i(0, 0, source.get_width(), source.get_height())
	var part := _part_for_row(_selected_row)
	var adjustment := _effective_adjustment_for_row(_selected_row)
	var region_info := _apply_target_override(_target_region(part), adjustment)
	var region: Rect2i = region_info.get("rect", Rect2i())
	var align := str(region_info.get("align", "center"))
	var offset_x := _adjustment_number(adjustment, "offset_x", 0.0)
	var offset_y := _adjustment_number(adjustment, "offset_y", 0.0)
	var scale_adjustment := _adjustment_number(adjustment, "scale", 1.0)
	if not use_saved_adjustment:
		offset_x = float(_offset_x_spin.value)
		offset_y = float(_offset_y_spin.value)
		scale_adjustment = float(_scale_spin.value)

	var source_region := source.get_region(bounds)
	var base_scale := minf(float(region.size.x) / float(bounds.size.x), float(region.size.y) / float(bounds.size.y))
	var final_scale := maxf(0.01, base_scale * scale_adjustment)
	var dest_size := Vector2i(
		maxi(1, int(round(float(bounds.size.x) * final_scale))),
		maxi(1, int(round(float(bounds.size.y) * final_scale)))
	)
	source_region.resize(dest_size.x, dest_size.y, Image.INTERPOLATE_LANCZOS)
	var dest_x := int(round(float(region.position.x) + (float(region.size.x - dest_size.x) * 0.5)))
	var dest_y := int(round(float(region.position.y) + (float(region.size.y - dest_size.y) * 0.5)))
	if align == "bottom":
		dest_y = int(round(float(region.position.y + region.size.y - dest_size.y)))
	dest_x += int(round(offset_x))
	dest_y += int(round(offset_y))

	var target := Image.create(CANVAS_SIZE, CANVAS_SIZE, false, Image.FORMAT_RGBA8)
	target.fill(Color.TRANSPARENT)
	_blit_clipped(target, source_region, Vector2i(dest_x, dest_y))
	return target


func _get_source_cache(asset_id: String, source_path: String) -> Dictionary:
	if _source_cache.has(asset_id):
		return _source_cache[asset_id]
	var image := Image.new()
	var error := image.load(source_path)
	if error != OK:
		_set_status("Could not load source image: %s" % source_path)
		return {}
	var cache := {
		"image": image,
	}
	_source_cache[asset_id] = cache
	return cache


func _compose_preview(selected: Image, part: String) -> Image:
	var composite := Image.create(CANVAS_SIZE, CANVAS_SIZE, false, Image.FORMAT_RGBA8)
	composite.fill(Color.TRANSPARENT)
	match part:
		"body":
			_blit_full(composite, selected)
			_blit_full(composite, _base_head)
		"head":
			_blit_full(composite, _base_body)
			_blit_full(composite, selected)
		"outfit":
			_blit_full(composite, _base_body)
			_blit_full(composite, selected)
			_blit_full(composite, _base_head)
		"hair":
			_blit_full(composite, _base_body)
			_blit_full(composite, _base_head)
			_blit_full(composite, selected)
		"accessory", "held_item":
			_blit_full(composite, _base_body)
			_blit_full(composite, _base_head)
			_blit_full(composite, selected)
		_:
			_blit_full(composite, _base_body)
			_blit_full(composite, _base_head)
			_blit_full(composite, selected)
	return composite


func _blit_full(target: Image, source: Image) -> void:
	if source == null or source.is_empty():
		return
	target.blend_rect(source, Rect2i(0, 0, CANVAS_SIZE, CANVAS_SIZE), Vector2i.ZERO)


func _blit_clipped(target: Image, source: Image, dest: Vector2i) -> void:
	if source == null or source.is_empty():
		return
	var source_rect := Rect2i(0, 0, source.get_width(), source.get_height())
	var dest_rect := Rect2i(dest, source_rect.size)
	var canvas_rect := Rect2i(0, 0, target.get_width(), target.get_height())
	var clipped_dest := dest_rect.intersection(canvas_rect)
	if clipped_dest.size.x <= 0 or clipped_dest.size.y <= 0:
		return
	var clipped_source := Rect2i(
		clipped_dest.position - dest_rect.position,
		clipped_dest.size
	)
	target.blend_rect(source, clipped_source, clipped_dest.position)


func _make_display_image(composite: Image) -> Image:
	var display := Image.create(CANVAS_SIZE, CANVAS_SIZE, false, Image.FORMAT_RGBA8)
	for y in CANVAS_SIZE:
		for x in CANVAS_SIZE:
			var checker := ((x / 16) + (y / 16)) % 2 == 0
			display.set_pixel(x, y, Color(0.88, 0.85, 0.78, 1.0) if checker else Color(0.96, 0.93, 0.86, 1.0))
	display.blend_rect(composite, Rect2i(0, 0, CANVAS_SIZE, CANVAS_SIZE), Vector2i.ZERO)
	for y in CANVAS_SIZE:
		display.set_pixel(STANDARD_ANCHOR.x, y, Color(0.9, 0.15, 0.12, 0.85))
	for x in CANVAS_SIZE:
		display.set_pixel(x, STANDARD_ANCHOR.y, Color(0.9, 0.15, 0.12, 0.85))
	return display


func _save_adjustment() -> void:
	if _selected_row.is_empty():
		return
	var asset_id := str(_selected_row.get("asset_id", ""))
	var found := false
	for row_value in _adjustment_rows:
		if not (row_value is Dictionary):
			continue
		var row := row_value as Dictionary
		if str(row.get("asset_id", "")) != asset_id:
			continue
		row["offset_x"] = float(_offset_x_spin.value)
		row["offset_y"] = float(_offset_y_spin.value)
		row["scale"] = float(_scale_spin.value)
		if str(row.get("review_status", "")).is_empty() or str(row.get("review_status", "")) == "pending":
			row["review_status"] = "adjusted"
		found = true
		break
	if not found:
		_adjustment_rows.append({
			"asset_id": asset_id,
			"source_path": str(_selected_row.get("source_path", "")),
			"standard_part": _part_for_row(_selected_row),
			"layer": str(_selected_row.get("layer", "")),
			"category": str(_selected_row.get("category", "")),
			"offset_x": float(_offset_x_spin.value),
			"offset_y": float(_offset_y_spin.value),
			"scale": float(_scale_spin.value),
			"target_x": "",
			"target_y": "",
			"target_width": "",
			"target_height": "",
			"align": "",
			"review_status": "adjusted",
			"notes": "",
		})
	if _write_json_array(ADJUSTMENTS_PATH, _adjustment_rows):
		_set_status("Saved adjustment for %s." % asset_id)
		_update_details()


func _regenerate_runtime_texture() -> void:
	if _selected_row.is_empty():
		return
	var standardized := _standardize_selected_image(true)
	if standardized.is_empty():
		return
	var output_path := _runtime_output_path(_selected_row)
	var global_output := ProjectSettings.globalize_path(output_path)
	DirAccess.make_dir_recursive_absolute(global_output.get_base_dir())
	var error := standardized.save_png(global_output)
	if error != OK:
		_set_status("Could not save runtime texture: %s" % output_path)
		return
	_current_standardized = standardized
	_update_preview()
	_set_status("Regenerated %s." % output_path)


func _target_region(part: String) -> Dictionary:
	var _part := part
	return {
		"rect": Rect2i(0, 0, CANVAS_SIZE, CANVAS_SIZE),
		"align": "center",
	}


func _apply_target_override(region_info: Dictionary, adjustment: Dictionary) -> Dictionary:
	var region: Rect2i = region_info.get("rect", Rect2i())
	var adjusted := region
	var x := _adjustment_number(adjustment, "target_x", float(region.position.x))
	var y := _adjustment_number(adjustment, "target_y", float(region.position.y))
	var width := _adjustment_number(adjustment, "target_width", float(region.size.x))
	var height := _adjustment_number(adjustment, "target_height", float(region.size.y))
	adjusted.position = Vector2i(int(round(x)), int(round(y)))
	adjusted.size = Vector2i(maxi(1, int(round(width))), maxi(1, int(round(height))))
	var align := str(region_info.get("align", "center"))
	if not str(adjustment.get("align", "")).is_empty():
		align = str(adjustment.get("align", align))
	return {
		"rect": adjusted,
		"align": align,
	}


func _get_adjustment_row(asset_id: String) -> Dictionary:
	for row_value in _adjustment_rows:
		if not (row_value is Dictionary):
			continue
		var row := row_value as Dictionary
		if str(row.get("asset_id", "")) == asset_id:
			return row
	return {}


func _get_batch_adjustment_row(row: Dictionary) -> Dictionary:
	var batch_id := str(row.get("batch_id", ""))
	var part := _part_for_row(row)
	if batch_id.is_empty():
		return {}
	for row_value in _batch_adjustment_rows:
		if not (row_value is Dictionary):
			continue
		var adjustment := row_value as Dictionary
		if str(adjustment.get("batch_id", "")) != batch_id:
			continue
		var adjustment_part := str(adjustment.get("standard_part", ""))
		if adjustment_part.is_empty() or adjustment_part == part:
			return adjustment
	return {}


func _effective_adjustment_for_row(row: Dictionary) -> Dictionary:
	var result := _target_region(_part_for_row(row))
	var base := {
		"target_x": result.get("rect", Rect2i()).position.x,
		"target_y": result.get("rect", Rect2i()).position.y,
		"target_width": result.get("rect", Rect2i()).size.x,
		"target_height": result.get("rect", Rect2i()).size.y,
		"align": result.get("align", "center"),
		"offset_x": 0.0,
		"offset_y": 0.0,
		"scale": 1.0,
	}
	_merge_adjustment(base, _get_batch_adjustment_row(row))
	_merge_adjustment(base, _get_adjustment_row(str(row.get("asset_id", ""))))
	return base


func _merge_adjustment(target: Dictionary, source: Dictionary) -> void:
	if source.is_empty():
		return
	for key in ["target_x", "target_y", "target_width", "target_height", "align", "offset_x", "offset_y", "scale"]:
		if not source.has(key):
			continue
		var value: Variant = source.get(key)
		if value == null or str(value).strip_edges().is_empty():
			continue
		target[key] = value


func _adjustment_number(row: Dictionary, key: String, default_value: float) -> float:
	if row.is_empty() or not row.has(key):
		return default_value
	var value: Variant = row.get(key)
	if value == null:
		return default_value
	var text := str(value)
	if text.strip_edges().is_empty():
		return default_value
	return float(text)


func _part_for_row(row: Dictionary) -> String:
	var part := str(row.get("standard_part", ""))
	if part.is_empty():
		part = str(row.get("layer", ""))
	return part


func _runtime_output_path(row: Dictionary) -> String:
	var catalog_runtime_path := str(row.get("runtime_path", ""))
	if not catalog_runtime_path.is_empty():
		if catalog_runtime_path.begins_with("res://"):
			return catalog_runtime_path
		return "res://%s" % catalog_runtime_path
	var asset_id := str(row.get("asset_id", "asset"))
	var part := _part_for_row(row)
	var directory := "assets/art/characters/accessories"
	match part:
		"body":
			directory = "assets/art/characters/body"
		"head":
			directory = "assets/art/characters/head"
		"hair":
			directory = "assets/art/characters/hair"
		"outfit":
			directory = "assets/art/characters/outfits"
		"held_item":
			directory = "assets/art/characters/held_items"
		"accessory":
			directory = "assets/art/characters/accessories"
	var filename := "%s_south_std256.png" % asset_id
	return "res://%s/%s" % [directory, filename]


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

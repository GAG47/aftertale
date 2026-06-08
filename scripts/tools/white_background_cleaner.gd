extends Control

var _source_path := ""
var _source_image: Image
var _clean_image: Image

@onready var _source_view: TextureRect = $Root/PreviewRow/SourcePanel/SourceView
@onready var _clean_view: TextureRect = $Root/PreviewRow/CleanPanel/CleanView
@onready var _source_label: Label = $Root/Controls/SourceLabel
@onready var _brightness: SpinBox = $Root/Controls/BrightnessRow/Spin
@onready var _saturation: SpinBox = $Root/Controls/SaturationRow/Spin
@onready var _open_dialog: FileDialog = $OpenDialog
@onready var _save_dialog: FileDialog = $SaveDialog
@onready var _status: Label = $Root/Status


func _ready() -> void:
	$Root/Controls/ButtonRow/OpenButton.pressed.connect(func() -> void:
		_open_dialog.popup_centered_ratio(0.75)
	)
	$Root/Controls/ButtonRow/SaveAsButton.pressed.connect(func() -> void:
		if not _source_path.is_empty():
			_save_dialog.current_path = _source_path
		_save_dialog.popup_centered_ratio(0.75)
	)
	_open_dialog.file_selected.connect(_load_source)
	_save_dialog.file_selected.connect(_save_clean_image)
	_brightness.value_changed.connect(func(_value: float) -> void:
		_update_clean_image()
	)
	_saturation.value_changed.connect(func(_value: float) -> void:
		_update_clean_image()
	)


func _load_source(path: String) -> void:
	_source_path = path
	_source_image = Image.new()
	if _source_image.load(path) != OK:
		_status.text = "Could not load: %s" % path
		return
	if _source_image.get_format() != Image.FORMAT_RGBA8:
		_source_image.convert(Image.FORMAT_RGBA8)
	_source_label.text = path
	_update_clean_image()


func _update_clean_image() -> void:
	if _source_image == null or _source_image.is_empty():
		return
	_clean_image = ImageBackgroundCleaner.remove_light_edge_background(
		_source_image,
		float(_brightness.value),
		float(_saturation.value)
	)
	_source_view.texture = ImageTexture.create_from_image(_preview_image(_source_image))
	_clean_view.texture = ImageTexture.create_from_image(_preview_image(_clean_image))
	_status.text = "Preview updated."


func _save_clean_image(path: String) -> void:
	if _clean_image == null or _clean_image.is_empty():
		return
	var save_path: String = path
	if not save_path.ends_with(".png"):
		save_path += ".png"
	if _clean_image.save_png(save_path) == OK:
		_status.text = "Saved: %s" % save_path
	else:
		_status.text = "Could not save: %s" % save_path


func _preview_image(source: Image) -> Image:
	const SIZE := 384
	var display := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	for y in range(SIZE):
		for x in range(SIZE):
			var light: bool = ((x / 24) + (y / 24)) % 2 == 0
			display.set_pixel(x, y, Color(0.84, 0.81, 0.73) if light else Color(0.95, 0.92, 0.84))
	var copy: Image = source.duplicate()
	var scale: float = minf(float(SIZE) / copy.get_width(), float(SIZE) / copy.get_height())
	var draw_size := Vector2i(maxi(1, int(copy.get_width() * scale)), maxi(1, int(copy.get_height() * scale)))
	copy.resize(draw_size.x, draw_size.y, Image.INTERPOLATE_LANCZOS)
	var destination := Vector2i((SIZE - draw_size.x) / 2, (SIZE - draw_size.y) / 2)
	display.blend_rect(copy, Rect2i(Vector2i.ZERO, draw_size), destination)
	return display

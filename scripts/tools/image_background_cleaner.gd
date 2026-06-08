class_name ImageBackgroundCleaner
extends RefCounted


static func remove_light_edge_background(
	source: Image,
	min_value: float = 0.72,
	max_saturation: float = 0.16
) -> Image:
	if source == null or source.is_empty():
		return Image.new()
	var result: Image = source.duplicate()
	if result.get_format() != Image.FORMAT_RGBA8:
		result.convert(Image.FORMAT_RGBA8)

	var width: int = result.get_width()
	var height: int = result.get_height()
	var visited := PackedByteArray()
	visited.resize(width * height)
	visited.fill(0)
	var queue := PackedInt32Array()

	for x in range(width):
		_enqueue_background_pixel(result, x, 0, width, visited, queue, min_value, max_saturation)
		_enqueue_background_pixel(result, x, height - 1, width, visited, queue, min_value, max_saturation)
	for y in range(1, height - 1):
		_enqueue_background_pixel(result, 0, y, width, visited, queue, min_value, max_saturation)
		_enqueue_background_pixel(result, width - 1, y, width, visited, queue, min_value, max_saturation)

	var cursor: int = 0
	while cursor < queue.size():
		var index: int = queue[cursor]
		cursor += 1
		var x: int = index % width
		var y: int = index / width
		var color: Color = result.get_pixel(x, y)
		color.a = 0.0
		result.set_pixel(x, y, color)
		if x > 0:
			_enqueue_background_pixel(result, x - 1, y, width, visited, queue, min_value, max_saturation)
		if x + 1 < width:
			_enqueue_background_pixel(result, x + 1, y, width, visited, queue, min_value, max_saturation)
		if y > 0:
			_enqueue_background_pixel(result, x, y - 1, width, visited, queue, min_value, max_saturation)
		if y + 1 < height:
			_enqueue_background_pixel(result, x, y + 1, width, visited, queue, min_value, max_saturation)
	return result


static func _enqueue_background_pixel(
	image: Image,
	x: int,
	y: int,
	width: int,
	visited: PackedByteArray,
	queue: PackedInt32Array,
	min_value: float,
	max_saturation: float
) -> void:
	var index: int = y * width + x
	if visited[index] != 0:
		return
	visited[index] = 1
	var color: Color = image.get_pixel(x, y)
	if color.a <= 0.01:
		queue.append(index)
		return
	if color.v >= min_value and color.s <= max_saturation:
		queue.append(index)

extends Node

signal scene_load_requested(scene_path: String)
signal scene_changed(scene_path: String, scene_root: Node)
signal scene_unloaded(scene_path: String)

const DEFAULT_CAMERA_ZOOM := 1.25

var scene_container: Node
var current_scene: Node
var current_scene_path: String = ""
var pending_entrance_id: String = ""
var save_runtime_on_next_unload: bool = true
var pending_location_context: Dictionary = {}
var pending_location_data: Dictionary = {}
var pending_return_location: Dictionary = {}
var camera_zoom: float = DEFAULT_CAMERA_ZOOM


func configure(container: Node) -> void:
	scene_container = container


func load_scene(scene_path: String) -> Error:
	scene_load_requested.emit(scene_path)

	if scene_container == null:
		push_error("SceneLoader has no scene container. Configure it from the boot scene first.")
		return ERR_UNAVAILABLE

	var packed_scene := load(scene_path) as PackedScene
	if packed_scene == null:
		push_error("SceneLoader could not load PackedScene: %s" % scene_path)
		return ERR_CANT_OPEN

	unload_current_scene()

	current_scene = packed_scene.instantiate()
	current_scene_path = scene_path

	if not pending_entrance_id.is_empty() and current_scene.has_method("set_entrance_id"):
		current_scene.set_entrance_id(pending_entrance_id)
	pending_entrance_id = ""

	scene_container.add_child(current_scene)
	scene_changed.emit(current_scene_path, current_scene)
	return OK


func load_location(scene_path: String, entrance_id: String) -> Error:
	if entrance_id.is_empty():
		push_error("SceneLoader.load_location requires an explicit entrance_id for location scenes: %s" % scene_path)
		return ERR_INVALID_PARAMETER
	pending_entrance_id = entrance_id
	return load_scene(scene_path)


func set_pending_location_context(context: Dictionary) -> void:
	pending_location_context = context.duplicate(true)


func set_pending_location_data(location_data: Dictionary) -> void:
	pending_location_data = location_data.duplicate(true)


func consume_pending_location_data() -> Dictionary:
	var location_data := pending_location_data.duplicate(true)
	pending_location_data.clear()
	return location_data


func consume_pending_location_context() -> Dictionary:
	var context := pending_location_context.duplicate(true)
	pending_location_context.clear()
	return context


func set_pending_return_location(scene_path: String, entrance_id: String) -> void:
	if entrance_id.is_empty():
		push_error("SceneLoader return location requires an explicit entrance_id: %s" % scene_path)
		return
	pending_return_location = {
		"scene_path": scene_path,
		"entrance_id": entrance_id,
	}


func load_pending_return_location() -> Error:
	var scene_path := str(pending_return_location.get("scene_path", ""))
	var entrance_id := str(pending_return_location.get("entrance_id", ""))
	pending_return_location.clear()
	if scene_path.is_empty():
		push_error("SceneLoader has no pending return location.")
		return ERR_UNAVAILABLE
	if entrance_id.is_empty():
		push_error("SceneLoader pending return location has no explicit entrance_id: %s" % scene_path)
		return ERR_INVALID_PARAMETER
	return load_location(scene_path, entrance_id)


func set_camera_zoom(value: float) -> void:
	camera_zoom = max(0.1, value)


func get_camera_zoom() -> float:
	return camera_zoom


func get_default_camera_zoom() -> float:
	return DEFAULT_CAMERA_ZOOM


func unload_current_scene() -> void:
	if current_scene == null:
		return

	var unloaded_path := current_scene_path
	if is_instance_valid(current_scene):
		if current_scene.has_method("set_save_runtime_on_exit"):
			current_scene.set_save_runtime_on_exit(save_runtime_on_next_unload)
		current_scene.queue_free()
	current_scene = null
	current_scene_path = ""
	save_runtime_on_next_unload = true
	scene_unloaded.emit(unloaded_path)


func has_active_scene() -> bool:
	return current_scene != null and is_instance_valid(current_scene)


func set_save_runtime_on_next_unload(value: bool) -> void:
	save_runtime_on_next_unload = value

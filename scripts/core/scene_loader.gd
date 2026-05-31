extends Node

signal scene_load_requested(scene_path: String)
signal scene_changed(scene_path: String, scene_root: Node)
signal scene_unloaded(scene_path: String)

var scene_container: Node
var current_scene: Node
var current_scene_path: String = ""
var pending_entrance_id: String = ""
var save_runtime_on_next_unload: bool = true


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


func load_location(scene_path: String, entrance_id: String = "") -> Error:
	pending_entrance_id = entrance_id
	return load_scene(scene_path)


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

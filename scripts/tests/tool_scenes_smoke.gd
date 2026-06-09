extends Node


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	for scene_path in [
		"res://scenes/tools/character_asset_fitter.tscn",
		"res://scenes/tools/portrait_avatar_fitter.tscn",
		"res://scenes/tools/portrait_badge_fitter.tscn",
		"res://scenes/tools/white_background_cleaner.tscn",
	]:
		var packed: PackedScene = load(scene_path)
		if packed == null:
			push_error("Could not load tool scene: %s" % scene_path)
			get_tree().quit(1)
			return
		var tool: Control = packed.instantiate() as Control
		add_child(tool)
		if not tool.has_node("Root"):
			push_error("Tool scene is missing its static UI root: %s" % scene_path)
			get_tree().quit(1)
			return
		remove_child(tool)
		tool.free()
	print("Tool scene smoke test passed")
	get_tree().quit(0)

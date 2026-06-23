class_name WorldLocationSpec
extends RefCounted


static func normalize_location(value: Dictionary) -> Dictionary:
	var spec := value.duplicate(true)
	var location_id := str(spec.get("location_id", spec.get("id", "")))
	spec["location_id"] = location_id
	if not spec.has("display_name"):
		spec["display_name"] = location_id
	if not spec.has("location_kind"):
		spec["location_kind"] = "static"
	if not spec.has("source_type"):
		spec["source_type"] = "static_scene" if str(spec.get("location_kind", "static")) == "static" else "generated"
	if spec.has("profile_id") and not spec.has("generator_profile_id"):
		spec["generator_profile_id"] = str(spec.get("profile_id", ""))
	if spec.has("width") or spec.has("height"):
		var size: Dictionary = spec.get("size", {}) as Dictionary
		if spec.has("width"):
			size["width"] = int(spec.get("width", 0))
		if spec.has("height"):
			size["height"] = int(spec.get("height", 0))
		spec["size"] = size
	if not spec.has("metadata"):
		spec["metadata"] = {}
	return spec


static func normalize_spawn(value: Dictionary) -> Dictionary:
	var spec := value.duplicate(true)
	spec["spawn_id"] = str(spec.get("spawn_id", spec.get("id", "")))
	spec["location_id"] = str(spec.get("location_id", ""))
	if spec.has("cell") and spec.get("cell") is Array:
		var cell_array: Array = spec.get("cell", []) as Array
		if cell_array.size() >= 2:
			spec["cell"] = { "x": int(cell_array[0]), "y": int(cell_array[1]) }
	if not spec.has("tags"):
		spec["tags"] = []
	return spec


static func normalize_exit(value: Dictionary) -> Dictionary:
	var spec := value.duplicate(true)
	spec["exit_id"] = str(spec.get("exit_id", spec.get("id", "")))
	spec["from_location_id"] = str(spec.get("from_location_id", ""))
	spec["target_location_id"] = str(spec.get("target_location_id", ""))
	spec["target_spawn_id"] = str(spec.get("target_spawn_id", spec.get("target_entrance_id", "")))
	if spec.has("from_cell") and spec.get("from_cell") is Array:
		var cell_array: Array = spec.get("from_cell", []) as Array
		if cell_array.size() >= 2:
			spec["from_cell"] = { "x": int(cell_array[0]), "y": int(cell_array[1]) }
	if not spec.has("transition_type"):
		spec["transition_type"] = "walk"
	if not spec.has("enabled"):
		spec["enabled"] = true
	if not spec.has("metadata"):
		spec["metadata"] = {}
	return spec

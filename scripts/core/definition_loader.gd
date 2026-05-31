extends Node

var _json_cache: Dictionary = {}


func load_json_resource(resource_path: String, expected_kind: String = "JSON resource") -> Dictionary:
	if resource_path.is_empty():
		return {}

	if _json_cache.has(resource_path):
		var cached: Dictionary = _json_cache[resource_path] as Dictionary
		return cached.duplicate(true)

	var file: FileAccess = FileAccess.open(resource_path, FileAccess.READ)
	if file == null:
		push_error("DefinitionLoader could not open %s: %s" % [expected_kind, resource_path])
		return {}

	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not (parsed is Dictionary):
		push_error("DefinitionLoader expected %s to be a JSON object: %s" % [expected_kind, resource_path])
		return {}

	var definition: Dictionary = parsed as Dictionary
	_json_cache[resource_path] = definition.duplicate(true)
	return definition.duplicate(true)


func load_location(resource_path: String) -> Dictionary:
	return load_json_resource(resource_path, "location definition")


func load_character(resource_path: String) -> Dictionary:
	return load_json_resource(resource_path, "character definition")


func load_item(resource_path: String) -> Dictionary:
	return load_json_resource(resource_path, "item definition")


func load_recipe(resource_path: String) -> Dictionary:
	return load_json_resource(resource_path, "recipe definition")


func load_shop(resource_path: String) -> Dictionary:
	return load_json_resource(resource_path, "shop definition")


func load_skill(resource_path: String) -> Dictionary:
	return load_json_resource(resource_path, "skill definition")


func load_crop(resource_path: String) -> Dictionary:
	return load_json_resource(resource_path, "crop definition")


func load_dialogue(resource_path: String) -> Dictionary:
	return load_json_resource(resource_path, "dialogue definition")


func load_quest(resource_path: String) -> Dictionary:
	return load_json_resource(resource_path, "quest definition")


func load_faction(resource_path: String) -> Dictionary:
	return load_json_resource(resource_path, "faction definition")


func load_relation_data(resource_path: String) -> Dictionary:
	return load_json_resource(resource_path, "relation data")


func clear_cache(resource_path: String = "") -> void:
	if resource_path.is_empty():
		_json_cache.clear()
		return

	_json_cache.erase(resource_path)

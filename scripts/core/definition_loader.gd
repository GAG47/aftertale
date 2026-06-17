extends Node

const VillageRoadGenerator := preload("res://scripts/systems/scenes/village_road_generator.gd")
const TileSceneCompiler := preload("res://scripts/systems/settlements/tile_scene_compiler.gd")

var _json_cache: Dictionary = {}
var _resolved_locations_by_id: Dictionary = {}
var _location_data_path_by_id: Dictionary = {}
var _location_scene_path_by_id: Dictionary = {}


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


func load_resolved_location(resource_path: String, context: Dictionary = {}) -> Dictionary:
	var location_data: Dictionary = load_location(resource_path)
	if location_data.is_empty():
		return {}

	return materialize_location(location_data, resource_path, context)


func materialize_location(location_data: Dictionary, resource_path: String = "", _context: Dictionary = {}) -> Dictionary:
	var generator_data: Dictionary = location_data.get("generator", {}) as Dictionary
	var generator_type := str(generator_data.get("type", ""))
	match generator_type:
		"village_road":
			var generator: RefCounted = VillageRoadGenerator.new()
			var generated: Dictionary = generator.generate_location(location_data)
			_register_resolved_location(generated, resource_path, "")
			return generated.duplicate(true)
		"settlement_blueprint":
			var compiler: RefCounted = TileSceneCompiler.new()
			var compiled: Dictionary = compiler.generate_location(location_data)
			_register_resolved_location(compiled, resource_path, "")
			return compiled.duplicate(true)
		"settlement":
			var compiler: RefCounted = TileSceneCompiler.new()
			var compiled: Dictionary = compiler.generate_location(location_data)
			_register_resolved_location(compiled, resource_path, "")
			return compiled.duplicate(true)
		_:
			_register_resolved_location(location_data, resource_path, "")
			return location_data.duplicate(true)


func resolve_location_by_id(location_id: String) -> Dictionary:
	if location_id.is_empty():
		return {}

	if _resolved_locations_by_id.has(location_id):
		return (_resolved_locations_by_id[location_id] as Dictionary).duplicate(true)

	var data_path := "res://data/locations/%s.json" % location_id
	return load_resolved_location(data_path)


func get_location_scene_path(location_id: String) -> String:
	return str(_location_scene_path_by_id.get(location_id, ""))


func get_location_data_path(location_id: String) -> String:
	return str(_location_data_path_by_id.get(location_id, ""))


func _register_resolved_location(location_data: Dictionary, resource_path: String, scene_path: String) -> void:
	var location_id := str(location_data.get("id", ""))
	if location_id.is_empty():
		return

	_resolved_locations_by_id[location_id] = location_data.duplicate(true)
	if not resource_path.is_empty():
		_location_data_path_by_id[location_id] = resource_path
	if not scene_path.is_empty():
		_location_scene_path_by_id[location_id] = scene_path


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
		_resolved_locations_by_id.clear()
		_location_data_path_by_id.clear()
		_location_scene_path_by_id.clear()
		return

	_json_cache.erase(resource_path)

extends Node

const VillageRoadGenerator := preload("res://scripts/systems/scenes/village_road_generator.gd")
const TileSceneCompiler := preload("res://scripts/systems/settlements/tile_scene_compiler.gd")
const GeneratedSettlementStoreScript := preload("res://scripts/systems/settlements/generated_settlement_store.gd")

var _json_cache: Dictionary = {}
var _resolved_locations_by_id: Dictionary = {}
var _location_data_path_by_id: Dictionary = {}
var _location_scene_path_by_id: Dictionary = {}
var _generated_interior_manifests_by_id: Dictionary = {}


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
	var context_location_id := _context_location_id(context)
	if not context_location_id.is_empty():
		if _resolved_locations_by_id.has(context_location_id):
			return (_resolved_locations_by_id[context_location_id] as Dictionary).duplicate(true)
		if context.has("interior_manifest"):
			var manifest: Dictionary = context.get("interior_manifest", {}) as Dictionary
			var materialized := _materialize_generated_interior(manifest)
			if not materialized.is_empty():
				_register_resolved_location(materialized, "manifest:%s" % context_location_id, str(manifest.get("scene_path", "")))
				return materialized.duplicate(true)

	var location_data: Dictionary = load_location(resource_path)
	if location_data.is_empty():
		return {}
	var location_id := str(location_data.get("id", ""))
	if context.is_empty() and not location_id.is_empty() and _resolved_locations_by_id.has(location_id):
		if str(_location_data_path_by_id.get(location_id, "")) == resource_path:
			return (_resolved_locations_by_id[location_id] as Dictionary).duplicate(true)

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
			if _uses_persistent_generated_settlement(location_data):
				var snapshot_location := _load_or_create_persistent_generated_settlement(location_data, resource_path)
				if not snapshot_location.is_empty():
					return snapshot_location.duplicate(true)
			var compiler: RefCounted = TileSceneCompiler.new()
			var compiled: Dictionary = compiler.generate_location(location_data)
			_register_resolved_location(compiled, resource_path, "")
			return compiled.duplicate(true)
		"settlement":
			if _uses_persistent_generated_settlement(location_data):
				var snapshot_location := _load_or_create_persistent_generated_settlement(location_data, resource_path)
				if not snapshot_location.is_empty():
					return snapshot_location.duplicate(true)
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
	var snapshot_location := _load_persistent_generated_location_by_id(location_id)
	if not snapshot_location.is_empty():
		return snapshot_location.duplicate(true)
	if _generated_interior_manifests_by_id.has(location_id):
		var manifest: Dictionary = _generated_interior_manifests_by_id[location_id] as Dictionary
		var materialized := _materialize_generated_interior(manifest)
		if not materialized.is_empty():
			_register_resolved_location(materialized, "manifest:%s" % location_id, str(manifest.get("scene_path", "")))
			return materialized.duplicate(true)

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
	_register_generated_interiors(location_data, resource_path)


func _uses_persistent_generated_settlement(location_data: Dictionary) -> bool:
	if bool(location_data.get("persistent_generated_settlement", false)):
		return true
	var generator_data: Dictionary = location_data.get("generator", {}) as Dictionary
	return bool(generator_data.get("persistent_generated_settlement", generator_data.get("persistent_snapshot", false)))


func _load_or_create_persistent_generated_settlement(location_data: Dictionary, resource_path: String) -> Dictionary:
	var store: RefCounted = GeneratedSettlementStoreScript.new()
	var snapshot: Dictionary = store.ensure_snapshot(location_data, resource_path)
	if snapshot.is_empty():
		return {}
	_register_persistent_generated_snapshot(snapshot, resource_path)
	return _snapshot_exterior_location(snapshot)


func _load_persistent_generated_location_by_id(location_id: String) -> Dictionary:
	var store: RefCounted = GeneratedSettlementStoreScript.new()
	var snapshot: Dictionary = store.load_snapshot_for_location_id(location_id)
	if snapshot.is_empty():
		return {}
	_register_persistent_generated_snapshot(snapshot, "snapshot:%s" % str(snapshot.get("settlement_id", "")))
	if _resolved_locations_by_id.has(location_id):
		return (_resolved_locations_by_id[location_id] as Dictionary).duplicate(true)
	return {}


func _register_persistent_generated_snapshot(snapshot: Dictionary, resource_path: String) -> void:
	for location_value in (snapshot.get("locations", []) as Array):
		var location: Dictionary = location_value as Dictionary
		_register_resolved_location(location, resource_path, str(location.get("scene_path", "")))
	for manifest_value in (snapshot.get("generated_interiors", []) as Array):
		var manifest: Dictionary = manifest_value as Dictionary
		var interior_id := str(manifest.get("interior_location_id", ""))
		if interior_id.is_empty():
			continue
		_generated_interior_manifests_by_id[interior_id] = manifest.duplicate(true)
		var materialized := _materialize_generated_interior(manifest)
		if materialized.is_empty():
			continue
		_resolved_locations_by_id[interior_id] = materialized.duplicate(true)
		_location_data_path_by_id[interior_id] = "snapshot:%s#%s" % [str(snapshot.get("settlement_id", "")), interior_id]
		var scene_path := str(manifest.get("scene_path", ""))
		if not scene_path.is_empty():
			_location_scene_path_by_id[interior_id] = scene_path


func _snapshot_exterior_location(snapshot: Dictionary) -> Dictionary:
	var exterior_id := str(snapshot.get("exterior_location_id", ""))
	for location_value in (snapshot.get("locations", []) as Array):
		var location: Dictionary = location_value as Dictionary
		if exterior_id.is_empty() or str(location.get("id", "")) == exterior_id:
			return location.duplicate(true)
	return {}


func _register_generated_interiors(location_data: Dictionary, resource_path: String) -> void:
	for manifest_value in (location_data.get("generated_interiors", []) as Array):
		var manifest: Dictionary = manifest_value as Dictionary
		var interior_id := str(manifest.get("interior_location_id", ""))
		if interior_id.is_empty():
			continue
		_generated_interior_manifests_by_id[interior_id] = manifest.duplicate(true)
		var materialized := _materialize_generated_interior(manifest)
		if materialized.is_empty():
			continue
		_resolved_locations_by_id[interior_id] = materialized.duplicate(true)
		_location_data_path_by_id[interior_id] = "manifest:%s#%s" % [str(location_data.get("id", resource_path)), interior_id]
		var scene_path := str(manifest.get("scene_path", ""))
		if not scene_path.is_empty():
			_location_scene_path_by_id[interior_id] = scene_path


func _materialize_generated_interior(manifest: Dictionary) -> Dictionary:
	var interior_id := str(manifest.get("interior_location_id", ""))
	if interior_id.is_empty():
		return {}
	var location: Dictionary = {
		"id": interior_id,
		"display_name": str(manifest.get("display_name", "Generated Interior")),
		"size": (manifest.get("size", { "width": 8, "height": 6 }) as Dictionary).duplicate(true),
		"tile_size": int(manifest.get("tile_size", 32)),
		"default_entrance": str(manifest.get("interior_entry_entrance_id", "entry")),
		"tiles": (manifest.get("tiles", []) as Array).duplicate(true),
		"terrain": (manifest.get("terrain", {}) as Dictionary).duplicate(true),
		"zones": (manifest.get("zones", []) as Array).duplicate(true),
		"floor_overlays": (manifest.get("floor_overlays", []) as Array).duplicate(true),
		"floor_decorations": (manifest.get("floor_decorations", []) as Array).duplicate(true),
		"structures": (manifest.get("structures", []) as Array).duplicate(true),
		"roofs": (manifest.get("roofs", []) as Array).duplicate(true),
		"entrances": (manifest.get("entrances", []) as Array).duplicate(true),
		"anchors": (manifest.get("anchors", []) as Array).duplicate(true),
		"exits": (manifest.get("exits", []) as Array).duplicate(true),
		"shops": (manifest.get("shops", []) as Array).duplicate(true),
		"objects": (manifest.get("objects", []) as Array).duplicate(true),
		"characters": (manifest.get("characters", []) as Array).duplicate(true),
		"state": (manifest.get("state", {}) as Dictionary).duplicate(true),
		"generated_interior_manifest": manifest.duplicate(true),
	}
	if (location.get("tiles", []) as Array).is_empty():
		location["tiles"] = [
			"wwwwwwww",
			"wffffffw",
			"wffffffw",
			"wffffffw",
			"wffffffw",
			"wwwewwww",
		]
	if (location.get("terrain", {}) as Dictionary).is_empty():
		location["terrain"] = _default_interior_terrain()
	return location


func _default_interior_terrain() -> Dictionary:
	return {
		"w": { "id": "interior_wall", "label": "Interior Wall", "walkable": false, "color": "#443a32" },
		"f": { "id": "interior_floor", "label": "Interior Floor", "walkable": true, "color": "#7b6a55" },
		"e": { "id": "interior_entry", "label": "Interior Entry", "walkable": true, "color": "#b5975d" },
	}


func _context_location_id(context: Dictionary) -> String:
	for key in ["target_location_id", "interior_location_id", "location_id"]:
		var value := str(context.get(key, ""))
		if not value.is_empty():
			return value
	return ""


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
		_generated_interior_manifests_by_id.clear()
		return

	_json_cache.erase(resource_path)

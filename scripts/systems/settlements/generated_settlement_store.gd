class_name GeneratedSettlementStore
extends RefCounted

const SCHEMA_VERSION := 1
const GENERATOR_VERSION := "v67"
const MAX_REFERENCE_REWRITE_DEPTH := 16
const TileSceneCompilerScript := preload("res://scripts/systems/settlements/tile_scene_compiler.gd")
const PopulationPlannerScript := preload("res://scripts/systems/settlements/population_planner.gd")


static func clear_runtime_cache() -> void:
	pass


func has_snapshot(settlement_id: String) -> bool:
	return FileAccess.file_exists(get_snapshot_path(settlement_id))


func load_snapshot(settlement_id: String) -> Dictionary:
	var path := get_snapshot_path(settlement_id)
	if not FileAccess.file_exists(path):
		return {}
	return _read_json(path)


func load_snapshot_for_location_id(location_id: String) -> Dictionary:
	var settlement_id := settlement_id_from_location_id(location_id)
	if settlement_id.is_empty():
		return {}
	var snapshot := load_snapshot(settlement_id)
	if snapshot.is_empty():
		return {}
	if _snapshot_has_location(snapshot, location_id):
		return snapshot
	return {}


func save_snapshot(settlement_id: String, snapshot: Dictionary) -> bool:
	var snapshot_path := get_expected_snapshot_path(settlement_id)
	if not _ensure_parent_dir(snapshot_path):
		return false
	_write_generated_characters(snapshot)
	var file := FileAccess.open(snapshot_path, FileAccess.WRITE)
	if file == null:
		push_error("GeneratedSettlementStore could not write snapshot: %s" % snapshot_path)
		return false
	file.store_string(JSON.stringify(snapshot, "\t"))
	_register_with_save_manager(settlement_id, snapshot_path, snapshot)
	return true


func ensure_snapshot(source_data: Dictionary, resource_path: String = "", context: Dictionary = {}) -> Dictionary:
	var settlement_id := settlement_id_from_source(source_data, context)
	if has_snapshot(settlement_id):
		var existing := load_snapshot(settlement_id)
		if not existing.is_empty():
			_register_with_save_manager(settlement_id, get_snapshot_path(settlement_id), existing)
			return existing

	var snapshot := _build_snapshot(source_data, resource_path, context)
	if snapshot.is_empty():
		return {}
	save_snapshot(settlement_id, snapshot)
	return snapshot


func delete_snapshot(settlement_id: String) -> void:
	var snapshot := load_snapshot(settlement_id)
	for definition_value in (snapshot.get("npc_definitions", []) as Array):
		var definition: Dictionary = definition_value as Dictionary
		var npc_id := str(definition.get("id", ""))
		if npc_id.is_empty():
			continue
		_remove_file_if_exists(get_generated_character_path(npc_id))
	var indexed_path := get_snapshot_path(settlement_id)
	var expected_path := get_expected_snapshot_path(settlement_id)
	_remove_file_if_exists(indexed_path)
	if indexed_path != expected_path:
		_remove_file_if_exists(expected_path)


func get_snapshot_path(settlement_id: String) -> String:
	if SaveManager != null and SaveManager.has_method("get_generated_settlement_record"):
		var record: Dictionary = SaveManager.get_generated_settlement_record(settlement_id)
		var indexed_path := str(record.get("snapshot_path", ""))
		if not indexed_path.is_empty():
			return indexed_path
	return get_expected_snapshot_path(settlement_id)


func get_expected_snapshot_path(settlement_id: String) -> String:
	return "%s/settlements/%s.json" % [_generated_root_path(), settlement_id]


func get_generated_character_path(npc_id: String) -> String:
	return "%s/characters/%s.json" % [_generated_root_path(), npc_id]


func get_generated_location_path(location_id: String) -> String:
	return "%s/locations/%s.json" % [_generated_root_path(), location_id]


func settlement_id_from_source(source_data: Dictionary, context: Dictionary = {}) -> String:
	var generator_data: Dictionary = source_data.get("generator", {}) as Dictionary
	var settlement_id := str(context.get("settlement_instance_id", context.get("settlement_id", "")))
	if settlement_id.is_empty():
		settlement_id = str(generator_data.get("settlement_instance_id", generator_data.get("settlement_id", "")))
	if settlement_id.is_empty():
		settlement_id = str(source_data.get("settlement_instance_id", source_data.get("settlement_id", "")))
	if settlement_id.is_empty():
		settlement_id = str(source_data.get("id", "generated_settlement"))
	return _safe_id(settlement_id)


func settlement_id_from_location_id(location_id: String) -> String:
	var exterior_marker := "__exterior"
	var marker_index := location_id.find(exterior_marker)
	if marker_index > 0:
		return location_id.substr(0, marker_index)
	var parts := location_id.split("__")
	if parts.size() >= 2:
		return str(parts[0])
	return ""


func _build_snapshot(source_data: Dictionary, resource_path: String, context: Dictionary = {}) -> Dictionary:
	var settlement_id := settlement_id_from_source(source_data, context)
	var generator_data: Dictionary = source_data.get("generator", {}) as Dictionary
	var template_id := _template_id_from_source(source_data)
	var policy_id := str(generator_data.get("settlement_policy_id", generator_data.get("policy_id", "")))
	var seed := int(generator_data.get("seed", generator_data.get("random_seed", 0)))
	var exterior_location_id := "%s__exterior" % settlement_id
	var snapshot_id := "%s__snapshot" % settlement_id
	var compiler_source := source_data.duplicate(true)
	compiler_source["id"] = exterior_location_id
	if not resource_path.is_empty():
		compiler_source["source_resource_path"] = resource_path

	var compiler: RefCounted = TileSceneCompilerScript.new()
	var compiled: Dictionary = compiler.generate_location(compiler_source)
	if compiled.is_empty():
		return {}

	compiled = _namespace_compiled(settlement_id, compiled)
	var planner: RefCounted = PopulationPlannerScript.new()
	var population: Dictionary = planner.plan_population(settlement_id, policy_id, seed, compiled)

	var exterior_location: Dictionary = compiled.duplicate(true)
	var generated_interiors: Array = (exterior_location.get("generated_interiors", []) as Array).duplicate(true)
	var npc_definitions: Array = population.get("npc_definitions", []) as Array
	var spawn_rows_by_location: Dictionary = (population.get("npc_spawn_rows_by_location", {}) as Dictionary).duplicate(true)
	_apply_character_sources(npc_definitions, spawn_rows_by_location)
	_inject_spawn_rows(exterior_location, generated_interiors, spawn_rows_by_location)
	exterior_location["generated_interiors"] = generated_interiors
	exterior_location["generation_summary"] = _with_population_summary(exterior_location.get("generation_summary", {}) as Dictionary, population.get("population_summary", {}) as Dictionary)

	var snapshot := {
		"schema_version": SCHEMA_VERSION,
		"generator_version": GENERATOR_VERSION,
		"settlement_id": settlement_id,
		"settlement_instance_id": settlement_id,
		"settlement_template_id": template_id,
		"snapshot_id": snapshot_id,
		"policy_id": policy_id,
		"seed": seed,
		"exterior_location_id": exterior_location_id,
		"locations": [exterior_location],
		"generated_interiors": generated_interiors,
		"building_contracts": (exterior_location.get("building_contracts", []) as Array).duplicate(true),
		"schedule_targets": (exterior_location.get("schedule_targets", []) as Array).duplicate(true),
		"npc_definitions": npc_definitions,
		"npc_spawn_rows_by_location": spawn_rows_by_location,
		"npc_role_assignments": population.get("npc_role_assignments", []),
		"population_summary": population.get("population_summary", {}),
		"created_at_game_time": _created_at_game_time(),
		"history": [
			{
				"type": "generated_settlement_snapshot_created",
				"generator_version": GENERATOR_VERSION,
				"settlement_id": settlement_id,
				"settlement_instance_id": settlement_id,
				"settlement_template_id": template_id,
				"snapshot_id": snapshot_id,
				"policy_id": policy_id,
				"seed": seed,
			},
		],
	}
	return snapshot


func _namespace_compiled(settlement_id: String, compiled: Dictionary) -> Dictionary:
	var result := compiled.duplicate(true)
	var building_map := _building_namespace_map(settlement_id, result)
	var interior_map := _interior_namespace_map(settlement_id, result)
	return _rename_generated_references(result, settlement_id, building_map, interior_map)


func _building_namespace_map(settlement_id: String, compiled: Dictionary) -> Dictionary:
	var building_map: Dictionary = {}
	for contract_value in (compiled.get("building_contracts", []) as Array):
		var contract: Dictionary = contract_value as Dictionary
		var local_id := str(contract.get("building_id", contract.get("source_building_id", "")))
		if local_id.is_empty() or local_id.begins_with("%s__" % settlement_id):
			continue
		building_map[local_id] = "%s__%s" % [settlement_id, local_id]
	return building_map


func _interior_namespace_map(settlement_id: String, compiled: Dictionary) -> Dictionary:
	var interior_map: Dictionary = {}
	for manifest_value in (compiled.get("generated_interiors", []) as Array):
		var manifest: Dictionary = manifest_value as Dictionary
		var old_id := str(manifest.get("interior_location_id", ""))
		var local_building_id := str(manifest.get("source_building_id", ""))
		if local_building_id.is_empty():
			local_building_id = _local_building_id_from_interior_id(old_id)
		if old_id.is_empty() or local_building_id.is_empty():
			continue
		var new_id := "%s__interior_%s" % [settlement_id, _local_building_id_from_scoped_id(settlement_id, local_building_id)]
		if old_id != new_id:
			interior_map[old_id] = new_id
	return interior_map


func _rename_generated_references(value: Variant, settlement_id: String, building_map: Dictionary, interior_map: Dictionary, depth: int = 0) -> Variant:
	if depth > MAX_REFERENCE_REWRITE_DEPTH:
		return value
	match typeof(value):
		TYPE_DICTIONARY:
			var result: Dictionary = {}
			for key in (value as Dictionary).keys():
				var key_text := str(key)
				var child: Variant = (value as Dictionary).get(key)
				if _skip_generated_reference_rewrite_key(key_text):
					result[key] = child
				elif typeof(child) == TYPE_STRING:
					result[key] = _rename_generated_string(str(child), key_text, settlement_id, building_map, interior_map)
				else:
					result[key] = _rename_generated_references(child, settlement_id, building_map, interior_map, depth + 1)
			return result
		TYPE_ARRAY:
			var rows: Array = []
			for child in (value as Array):
				rows.append(_rename_generated_references(child, settlement_id, building_map, interior_map, depth + 1))
			return rows
		_:
			return value


func _skip_generated_reference_rewrite_key(key_text: String) -> bool:
	return key_text in [
		"tiles",
		"terrain",
		"floor_overlays",
		"floor_decorations",
		"structures",
		"roofs",
		"zones",
		"generation_summary",
		"evaluation",
		"debug",
	]


func _rename_generated_string(value: String, key_text: String, settlement_id: String, building_map: Dictionary, interior_map: Dictionary) -> String:
	if interior_map.has(value):
		return str(interior_map.get(value, value))
	for old_interior_id in interior_map.keys():
		var old_text := str(old_interior_id)
		if value.begins_with("%s." % old_text):
			return "%s%s" % [str(interior_map.get(old_interior_id, old_text)), value.substr(old_text.length())]
	if key_text in ["shop_id"] or (key_text == "id" and value.begins_with("generated_shop_")):
		return _namespace_shop_id(value, settlement_id, building_map)
	if key_text in ["id", "object_id"] and value.begins_with("wall_door_"):
		return _namespace_wall_door_object_id(value, settlement_id, building_map)
	return _rename_building_scoped_id(value, building_map)


func _rename_building_scoped_id(value: String, building_map: Dictionary) -> String:
	for local_id in building_map.keys():
		var local_text := str(local_id)
		if value == local_text:
			return str(building_map.get(local_id, value))
		if value.begins_with("%s." % local_text):
			return "%s%s" % [str(building_map.get(local_id, local_text)), value.substr(local_text.length())]
		if value.begins_with("%s__" % local_text):
			return "%s%s" % [str(building_map.get(local_id, local_text)), value.substr(local_text.length())]
	return value


func _namespace_shop_id(value: String, settlement_id: String, building_map: Dictionary) -> String:
	if value.begins_with("%s__shop_" % settlement_id):
		return value
	var local_building_id := value.trim_prefix("generated_shop_")
	local_building_id = _local_building_id_from_scoped_id(settlement_id, local_building_id)
	if building_map.has(local_building_id):
		return "%s__shop_%s" % [settlement_id, local_building_id]
	return "%s__shop_%s" % [settlement_id, _safe_id(local_building_id)]


func _namespace_wall_door_object_id(value: String, settlement_id: String, building_map: Dictionary) -> String:
	if value.begins_with("%s__object_" % settlement_id):
		return value
	var local_building_id := value.trim_prefix("wall_door_")
	local_building_id = _local_building_id_from_scoped_id(settlement_id, local_building_id)
	if building_map.has(local_building_id):
		return "%s__object_wall_door_%s" % [settlement_id, local_building_id]
	return "%s__object_%s" % [settlement_id, _safe_id(value)]


func _apply_character_sources(npc_definitions: Array, spawn_rows_by_location: Dictionary) -> void:
	for definition_value in npc_definitions:
		var definition: Dictionary = definition_value as Dictionary
		var npc_id := str(definition.get("id", ""))
		if npc_id.is_empty():
			continue
		definition["source"] = get_generated_character_path(npc_id)
	for location_id in spawn_rows_by_location.keys():
		var rows: Array = spawn_rows_by_location.get(location_id, []) as Array
		for row_value in rows:
			var row: Dictionary = row_value as Dictionary
			var npc_id := str(row.get("id", ""))
			if npc_id.is_empty():
				continue
			row["source"] = get_generated_character_path(npc_id)
			var tags: Array = row.get("spawn_tags", []) as Array
			if not tags.has(settlement_id_from_location_id(str(location_id))):
				tags.append(settlement_id_from_location_id(str(location_id)))
			row["spawn_tags"] = tags


func _inject_spawn_rows(exterior_location: Dictionary, generated_interiors: Array, spawn_rows_by_location: Dictionary) -> void:
	var exterior_id := str(exterior_location.get("id", ""))
	if spawn_rows_by_location.has(exterior_id):
		var rows: Array = exterior_location.get("characters", []) as Array
		rows.append_array((spawn_rows_by_location.get(exterior_id, []) as Array).duplicate(true))
		exterior_location["characters"] = rows
	for index in range(generated_interiors.size()):
		var manifest: Dictionary = generated_interiors[index] as Dictionary
		var location_id := str(manifest.get("interior_location_id", ""))
		if not spawn_rows_by_location.has(location_id):
			continue
		var rows: Array = manifest.get("characters", []) as Array
		rows.append_array((spawn_rows_by_location.get(location_id, []) as Array).duplicate(true))
		manifest["characters"] = rows
		generated_interiors[index] = manifest


func _with_population_summary(generation_summary: Dictionary, population_summary: Dictionary) -> Dictionary:
	var result := generation_summary.duplicate(true)
	var gameplay_hooks: Dictionary = result.get("gameplay_hooks", {}) as Dictionary
	gameplay_hooks["generated_npc_count"] = int(population_summary.get("npc_count", 0))
	gameplay_hooks["character_records"] = int(population_summary.get("npc_count", 0))
	result["gameplay_hooks"] = gameplay_hooks
	result["population"] = population_summary.duplicate(true)
	return result


func _write_generated_characters(snapshot: Dictionary) -> void:
	for definition_value in (snapshot.get("npc_definitions", []) as Array):
		var definition: Dictionary = definition_value as Dictionary
		var npc_id := str(definition.get("id", ""))
		if npc_id.is_empty():
			continue
		var path := get_generated_character_path(npc_id)
		if not _ensure_parent_dir(path):
			continue
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file == null:
			push_error("GeneratedSettlementStore could not write generated character: %s" % path)
			continue
		file.store_string(JSON.stringify(definition, "\t"))


func _snapshot_has_location(snapshot: Dictionary, location_id: String) -> bool:
	for location_value in (snapshot.get("locations", []) as Array):
		var location: Dictionary = location_value as Dictionary
		if str(location.get("id", "")) == location_id:
			return true
	for manifest_value in (snapshot.get("generated_interiors", []) as Array):
		var manifest: Dictionary = manifest_value as Dictionary
		if str(manifest.get("interior_location_id", "")) == location_id:
			return true
	return false


func _generated_root_path() -> String:
	if SaveManager != null and SaveManager.has_method("get_generated_root_path"):
		var root_path := str(SaveManager.get_generated_root_path())
		if not root_path.is_empty():
			return root_path
	return "user://saves/slot_1/worlds/default_world/generated"


func _register_with_save_manager(settlement_id: String, snapshot_path: String, snapshot: Dictionary) -> void:
	if SaveManager == null or not SaveManager.has_method("register_generated_settlement"):
		return
	SaveManager.register_generated_settlement(settlement_id, snapshot_path, {
		"schema_version": int(snapshot.get("schema_version", SCHEMA_VERSION)),
		"generator_version": str(snapshot.get("generator_version", GENERATOR_VERSION)),
		"policy_id": str(snapshot.get("policy_id", "")),
		"seed": int(snapshot.get("seed", 0)),
		"exterior_location_id": str(snapshot.get("exterior_location_id", "")),
		"snapshot_id": str(snapshot.get("snapshot_id", "")),
	})


func _template_id_from_source(source_data: Dictionary) -> String:
	var generator_data: Dictionary = source_data.get("generator", {}) as Dictionary
	var template_id := str(generator_data.get("settlement_template_id", generator_data.get("template_id", "")))
	if template_id.is_empty():
		template_id = str(source_data.get("settlement_template_id", source_data.get("template_id", "")))
	if template_id.is_empty():
		template_id = str(source_data.get("id", "generated_settlement_template"))
	return _safe_id(template_id)


func _local_building_id_from_interior_id(interior_id: String) -> String:
	var marker := "__interior_"
	var marker_index := interior_id.rfind(marker)
	if marker_index < 0:
		return ""
	return interior_id.substr(marker_index + marker.length())


func _local_building_id_from_scoped_id(settlement_id: String, value: String) -> String:
	var prefix := "%s__" % settlement_id
	if value.begins_with(prefix):
		return value.substr(prefix.length())
	return value


func _created_at_game_time() -> Dictionary:
	if TimeManager == null:
		return {}
	return {
		"day": int(TimeManager.get("day")),
		"hour": int(TimeManager.get("hour")),
		"minute": int(TimeManager.get("minute")),
		"absolute_minutes": TimeManager.get_absolute_minutes() if TimeManager.has_method("get_absolute_minutes") else 0,
	}


func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed as Dictionary


func _ensure_parent_dir(path: String) -> bool:
	var global_path := ProjectSettings.globalize_path(path)
	var directory := global_path.get_base_dir()
	var error := DirAccess.make_dir_recursive_absolute(directory)
	return error == OK


func _remove_file_if_exists(path: String) -> void:
	if not FileAccess.file_exists(path):
		return
	var global_path := ProjectSettings.globalize_path(path)
	DirAccess.remove_absolute(global_path)


func _safe_id(value: String) -> String:
	var result := value.strip_edges().to_lower()
	for character in [" ", "/", "\\", ":", ".", "-", "\t", "\n"]:
		result = result.replace(character, "_")
	while result.find("__") >= 0:
		result = result.replace("__", "_")
	if result.is_empty():
		return "generated_settlement"
	return result

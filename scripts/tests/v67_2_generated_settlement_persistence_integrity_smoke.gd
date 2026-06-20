extends RefCounted

const StoreScript := preload("res://scripts/systems/settlements/generated_settlement_store.gd")

const SETTLEMENT_ID := "v67_integrity_settlement"
const TEMPLATE_ID := "v67_integrity_template"
const WORLD_ID := "v67_2_integrity_world"
const SLOT_A_SAVE := "user://saves/v67_2_slot_a.json"
const SLOT_B_SAVE := "user://saves/v67_2_slot_b.json"
const SOURCE_PATH := "res://data/locations/v67_2_integrity_template.json"
const GENERATED_SETTLEMENT_SCENE := "res://scenes/locations/generated_settlement.tscn"


func run(root: Node) -> bool:
	if root != null and root.has_node("WorldRoot"):
		SceneLoader.configure(root.get_node("WorldRoot"))

	GameState.start_new_session("v67_2_integrity_session")
	TimeManager.reset()
	NpcScheduleSystem.reset_schedule_state()
	DefinitionLoader.clear_cache()

	var slot_a := _generate_slot(SLOT_A_SAVE)
	if slot_a.is_empty():
		return false
	var slot_b := _generate_slot(SLOT_B_SAVE)
	if slot_b.is_empty():
		return false

	if not _slot_result_uses_fragment(slot_a, "v67_2_slot_a/worlds/%s" % WORLD_ID):
		return false
	if not _slot_result_uses_fragment(slot_b, "v67_2_slot_b/worlds/%s" % WORLD_ID):
		return false
	if str(slot_a.get("snapshot_path", "")) == str(slot_b.get("snapshot_path", "")):
		return _fail("v67.2 snapshot paths must differ across save slots")
	if str(slot_a.get("character_source", "")) == str(slot_b.get("character_source", "")):
		return _fail("v67.2 generated character source paths must differ across save slots")

	if not _snapshot_identity_is_valid(slot_a.get("snapshot", {}) as Dictionary):
		return false
	if not _formal_generated_ids_are_namespaced(slot_a.get("snapshot", {}) as Dictionary):
		return false
	if not _generated_user_definitions_are_readable(slot_a.get("snapshot", {}) as Dictionary):
		return false
	if not _cache_switch_uses_active_index(slot_a, slot_b):
		return false
	if not _load_game_restores_generated_context(slot_a, slot_b):
		return false

	print("v67.2 generated settlement persistence integrity smoke test passed")
	return true


func _generate_slot(save_path: String) -> Dictionary:
	SaveManager.configure_active_save_context(save_path, WORLD_ID)
	SaveManager.clear_generated_settlement_index()
	DefinitionLoader.clear_generated_runtime_cache()

	var store: RefCounted = StoreScript.new()
	store.delete_snapshot(SETTLEMENT_ID)
	DefinitionLoader.clear_generated_runtime_cache()

	var exterior := DefinitionLoader.materialize_location(_source(), SOURCE_PATH, {
		"settlement_instance_id": SETTLEMENT_ID,
	})
	if exterior.is_empty():
		_fail("v67.2 could not materialize generated settlement for %s" % save_path)
		return {}

	var snapshot: Dictionary = store.load_snapshot(SETTLEMENT_ID)
	if snapshot.is_empty():
		_fail("v67.2 snapshot was not written for %s" % save_path)
		return {}

	var record: Dictionary = SaveManager.get_generated_settlement_record(SETTLEMENT_ID)
	var snapshot_path := str(record.get("snapshot_path", ""))
	var character_source := _first_generated_character_source(snapshot)
	if snapshot_path.is_empty() or character_source.is_empty():
		_fail("v67.2 slot result is missing snapshot_path or generated character source")
		return {}

	return {
		"save_path": save_path,
		"snapshot": snapshot.duplicate(true),
		"index": SaveManager.get_generated_settlement_index(),
		"snapshot_path": snapshot_path,
		"character_source": character_source,
	}


func _source() -> Dictionary:
	return {
		"id": SETTLEMENT_ID,
		"settlement_template_id": TEMPLATE_ID,
		"display_name": "V67.2 Integrity Template",
		"tile_size": 32,
		"generator": {
			"type": "settlement",
			"persistent_generated_settlement": true,
			"settlement_id": SETTLEMENT_ID,
			"settlement_template_id": TEMPLATE_ID,
			"settlement_policy_id": "roadside_trade_village",
			"seed": 6701,
			"size": { "width": 48, "height": 32 },
			"context": {
				"map_size": { "width": 48, "height": 32 },
				"entrances": [{ "x": 0, "y": 16 }],
				"existing_obstacles": [{ "x": 11, "y": 5 }, { "x": 12, "y": 5 }],
				"existing_water": [{ "x": 42, "y": 7 }, { "x": 43, "y": 7 }],
				"important_world_points": [{ "x": 36, "y": 20 }],
				"world_seed": 6701,
			},
		},
	}


func _slot_result_uses_fragment(slot_result: Dictionary, fragment: String) -> bool:
	var snapshot_path := str(slot_result.get("snapshot_path", ""))
	var character_source := str(slot_result.get("character_source", ""))
	if snapshot_path.find(fragment) < 0:
		return _fail("v67.2 snapshot path does not include expected slot/world fragment: %s" % snapshot_path)
	if character_source.find(fragment) < 0:
		return _fail("v67.2 generated character source does not include expected slot/world fragment: %s" % character_source)
	return true


func _snapshot_identity_is_valid(snapshot: Dictionary) -> bool:
	if str(snapshot.get("settlement_id", "")) != SETTLEMENT_ID:
		return _fail("v67.2 snapshot settlement_id must be the instance id")
	if str(snapshot.get("settlement_instance_id", "")) != SETTLEMENT_ID:
		return _fail("v67.2 snapshot settlement_instance_id mismatch")
	if str(snapshot.get("settlement_template_id", "")) != TEMPLATE_ID:
		return _fail("v67.2 snapshot settlement_template_id mismatch")
	if str(snapshot.get("snapshot_id", "")) != "%s__snapshot" % SETTLEMENT_ID:
		return _fail("v67.2 snapshot_id mismatch")
	if str(snapshot.get("exterior_location_id", "")) != "%s__exterior" % SETTLEMENT_ID:
		return _fail("v67.2 exterior_location_id mismatch")
	return true


func _formal_generated_ids_are_namespaced(snapshot: Dictionary) -> bool:
	var prefix := "%s__" % SETTLEMENT_ID
	for contract_value in (snapshot.get("building_contracts", []) as Array):
		var contract: Dictionary = contract_value as Dictionary
		if not _string_begins(str(contract.get("building_id", "")), prefix, "building contract building_id"):
			return false
		if not _string_begins(str(contract.get("source_building_id", "")), prefix, "building contract source_building_id"):
			return false
		if not _string_begins(str(contract.get("interior_location_id", "")), "%s__interior_" % SETTLEMENT_ID, "building contract interior_location_id"):
			return false
		if str(contract.get("interior_location_id", "")).find("__exterior__interior_") >= 0:
			return _fail("v67.2 interior location id must not retain the exterior-derived compiler id")

	for target_value in (snapshot.get("schedule_targets", []) as Array):
		var target: Dictionary = target_value as Dictionary
		if not _string_begins(str(target.get("id", "")), prefix, "schedule target id"):
			return false
		if not _string_begins(str(target.get("source_building_id", "")), prefix, "schedule target source_building_id"):
			return false
		if not _string_begins(str(target.get("location_id", "")), prefix, "schedule target location_id"):
			return false

	for manifest_value in (snapshot.get("generated_interiors", []) as Array):
		var manifest: Dictionary = manifest_value as Dictionary
		if not _string_begins(str(manifest.get("interior_location_id", "")), "%s__interior_" % SETTLEMENT_ID, "manifest interior_location_id"):
			return false
		if not _string_begins(str(manifest.get("source_building_id", "")), prefix, "manifest source_building_id"):
			return false
		if not _manifest_ids_are_namespaced(manifest):
			return false

	for location_value in (snapshot.get("locations", []) as Array):
		var location: Dictionary = location_value as Dictionary
		if not _string_begins(str(location.get("id", "")), prefix, "location id"):
			return false
		for object_value in (location.get("objects", []) as Array):
			var object_row: Dictionary = object_value as Dictionary
			if str(object_row.get("kind", "")) == "wall_door":
				if not _string_begins(str(object_row.get("id", "")), "%s__object_wall_door_" % SETTLEMENT_ID, "exterior wall door object id"):
					return false
			if not _optional_generated_ref_is_namespaced(object_row, "source_building_id"):
				return false
			if not _optional_location_ref_is_namespaced(object_row, "target_location_id"):
				return false
			if not _optional_location_ref_is_namespaced(object_row, "interior_location_id"):
				return false

	for definition_value in (snapshot.get("npc_definitions", []) as Array):
		var definition: Dictionary = definition_value as Dictionary
		var npc_id := str(definition.get("id", ""))
		if not _string_begins(npc_id, "%s__npc_" % SETTLEMENT_ID, "generated npc id"):
			return false
		for entry_value in (definition.get("schedule", []) as Array):
			var entry: Dictionary = entry_value as Dictionary
			if not _string_begins(str(entry.get("id", "")), "%s__" % npc_id, "npc schedule entry id"):
				return false
			if not _string_begins(str(entry.get("location_id", "")), prefix, "npc schedule location_id"):
				return false

	for assignment_value in (snapshot.get("npc_role_assignments", []) as Array):
		var assignment: Dictionary = assignment_value as Dictionary
		if not _string_begins(str(assignment.get("id", "")), prefix, "role assignment id"):
			return false
		if not _optional_generated_ref_is_namespaced(assignment, "source_building_id"):
			return false
	return true


func _manifest_ids_are_namespaced(manifest: Dictionary) -> bool:
	for object_value in (manifest.get("objects", []) as Array):
		var object_row: Dictionary = object_value as Dictionary
		if not _string_begins(str(object_row.get("id", "")), "%s__" % SETTLEMENT_ID, "interior object id"):
			return false
		if object_row.has("object_id") and not _string_begins(str(object_row.get("object_id", "")), "%s__" % SETTLEMENT_ID, "interior object_id"):
			return false
		if not _optional_generated_ref_is_namespaced(object_row, "source_building_id"):
			return false
		if not _optional_generated_ref_is_namespaced(object_row, "shop_id", "%s__shop_" % SETTLEMENT_ID):
			return false
		if not _optional_location_ref_is_namespaced(object_row, "target_location_id"):
			return false
		if not _optional_location_ref_is_namespaced(object_row, "interior_location_id"):
			return false
		if not _optional_location_ref_is_namespaced(object_row, "exterior_location_id"):
			return false

	for shop_value in (manifest.get("shops", []) as Array):
		var shop: Dictionary = shop_value as Dictionary
		if not _string_begins(str(shop.get("id", "")), "%s__shop_" % SETTLEMENT_ID, "generated shop id"):
			return false
		if not _optional_generated_ref_is_namespaced(shop, "source_building_id"):
			return false

	for facility_value in (manifest.get("facilities", []) as Array):
		var facility: Dictionary = facility_value as Dictionary
		if not _string_begins(str(facility.get("object_id", "")), "%s__" % SETTLEMENT_ID, "facility object_id"):
			return false
		if not _optional_generated_ref_is_namespaced(facility, "source_building_id"):
			return false
		if not _optional_location_ref_is_namespaced(facility, "location_id"):
			return false

	for target_value in (manifest.get("schedule_targets", []) as Array):
		var target: Dictionary = target_value as Dictionary
		if not _string_begins(str(target.get("id", "")), "%s__" % SETTLEMENT_ID, "manifest schedule target id"):
			return false
		if not _optional_generated_ref_is_namespaced(target, "source_building_id"):
			return false
		if not _optional_location_ref_is_namespaced(target, "location_id"):
			return false
	return true


func _cache_switch_uses_active_index(slot_a: Dictionary, slot_b: Dictionary) -> bool:
	var location_id := _first_spawned_location_id(slot_a.get("snapshot", {}) as Dictionary)
	if location_id.is_empty():
		return _fail("v67.2 could not find a spawned location to test cache switching")

	SaveManager.configure_active_save_context(SLOT_A_SAVE, WORLD_ID)
	SaveManager.apply_generated_settlement_index(slot_a.get("index", {}) as Dictionary)
	var source_a := _materialize_and_first_spawn_source(location_id)
	if source_a.find("v67_2_slot_a/worlds/%s" % WORLD_ID) < 0:
		return _fail("v67.2 active slot A did not resolve generated source from slot A: %s" % source_a)

	SaveManager.configure_active_save_context(SLOT_B_SAVE, WORLD_ID)
	SaveManager.apply_generated_settlement_index(slot_b.get("index", {}) as Dictionary)
	var source_b := _materialize_and_first_spawn_source(location_id)
	if source_b.find("v67_2_slot_b/worlds/%s" % WORLD_ID) < 0:
		return _fail("v67.2 active slot B did not resolve generated source from slot B: %s" % source_b)
	if source_a == source_b:
		return _fail("v67.2 cache switch reused the same generated source path across slots")
	return true


func _load_game_restores_generated_context(slot_a: Dictionary, slot_b: Dictionary) -> bool:
	if not _write_save_file(SLOT_A_SAVE, slot_a.get("index", {}) as Dictionary):
		return false

	SaveManager.configure_active_save_context(SLOT_B_SAVE, WORLD_ID)
	SaveManager.apply_generated_settlement_index(slot_b.get("index", {}) as Dictionary)
	DefinitionLoader.materialize_location(_source(), SOURCE_PATH, {
		"settlement_instance_id": SETTLEMENT_ID,
	})

	var result: ActionResult = SaveManager.load_game(SLOT_A_SAVE)
	if not result.success:
		return _fail("v67.2 load_game failed: %s" % result.failure_reason)
	if SaveManager.get_active_save_slot_id() != "v67_2_slot_a":
		return _fail("v67.2 load_game did not restore active slot before scene load")
	if SaveManager.get_active_world_id() != WORLD_ID:
		return _fail("v67.2 load_game did not restore active world before scene load")
	var record: Dictionary = SaveManager.get_generated_settlement_record(SETTLEMENT_ID)
	if str(record.get("snapshot_path", "")) != str(slot_a.get("snapshot_path", "")):
		return _fail("v67.2 load_game did not restore the generated settlement index")

	var location_id := _first_spawned_location_id(slot_a.get("snapshot", {}) as Dictionary)
	var source_after_load := _materialize_and_first_spawn_source(location_id)
	if source_after_load.find("v67_2_slot_a/worlds/%s" % WORLD_ID) < 0:
		return _fail("v67.2 load_game kept stale generated cache after switching slots: %s" % source_after_load)
	return true


func _materialize_and_first_spawn_source(location_id: String) -> String:
	DefinitionLoader.materialize_location(_source(), SOURCE_PATH, {
		"settlement_instance_id": SETTLEMENT_ID,
	})
	var resolved := DefinitionLoader.resolve_location_by_id(location_id)
	for row_value in (resolved.get("characters", []) as Array):
		var row: Dictionary = row_value as Dictionary
		var source := str(row.get("source", ""))
		if not source.is_empty():
			return source
	return ""


func _generated_user_definitions_are_readable(snapshot: Dictionary) -> bool:
	for definition_value in (snapshot.get("npc_definitions", []) as Array):
		var definition: Dictionary = definition_value as Dictionary
		var source := str(definition.get("source", ""))
		if source.is_empty() or not source.begins_with("user://") or not FileAccess.file_exists(source):
			return _fail("v67.2 generated character user:// source is missing: %s" % source)
		var loaded := DefinitionLoader.load_json_resource(source, "generated character definition")
		if str(loaded.get("id", "")) != str(definition.get("id", "")):
			return _fail("v67.2 generated user:// character definition loaded the wrong id")
	return true


func _write_save_file(save_path: String, generated_index: Dictionary) -> bool:
	var dir_error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(save_path).get_base_dir())
	if dir_error != OK:
		return _fail("v67.2 could not create save directory for %s" % save_path)
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	if file == null:
		return _fail("v67.2 could not write save file: %s" % save_path)
	file.store_string(JSON.stringify({
		"version": 1,
		"saved_at": Time.get_datetime_string_from_system(false, true),
		"active_save_path": save_path,
		"active_save_slot_id": "v67_2_slot_a",
		"active_world_id": WORLD_ID,
		"scene": {
			"scene_path": GENERATED_SETTLEMENT_SCENE,
			"scene_id": "v67_2_integrity_scene",
			"location_id": "generated_settlement__exterior",
			"entrance_id": "main_entrance",
			"controlled_character": {},
		},
		"game_state": GameState.get_save_state(),
		"time": TimeManager.get_save_state(),
		"quests": QuestSystem.get_save_state(),
		"party": PartySystem.get_save_state(),
		"relations": RelationSystem.get_save_state(),
		"crops": CropSystem.get_save_state(),
		"business": BusinessSystem.get_save_state(),
		"npc_schedules": NpcScheduleSystem.get_save_state(),
		"generated_settlements": generated_index.duplicate(true),
	}, "\t"))
	return true


func _first_generated_character_source(snapshot: Dictionary) -> String:
	for definition_value in (snapshot.get("npc_definitions", []) as Array):
		var definition: Dictionary = definition_value as Dictionary
		var source := str(definition.get("source", ""))
		if not source.is_empty():
			return source
	return ""


func _first_spawned_location_id(snapshot: Dictionary) -> String:
	for location_id in (snapshot.get("npc_spawn_rows_by_location", {}) as Dictionary).keys():
		var rows: Array = (snapshot.get("npc_spawn_rows_by_location", {}) as Dictionary).get(location_id, []) as Array
		if not rows.is_empty():
			return str(location_id)
	return ""


func _optional_generated_ref_is_namespaced(row: Dictionary, key: String, prefix: String = "") -> bool:
	var value := str(row.get(key, ""))
	if value.is_empty():
		return true
	if prefix.is_empty():
		prefix = "%s__" % SETTLEMENT_ID
	return _string_begins(value, prefix, key)


func _optional_location_ref_is_namespaced(row: Dictionary, key: String) -> bool:
	var value := str(row.get(key, ""))
	if value.is_empty() or value == "__return__":
		return true
	return _string_begins(value, "%s__" % SETTLEMENT_ID, key)


func _string_begins(value: String, prefix: String, label: String) -> bool:
	if value.begins_with(prefix):
		return true
	return _fail("v67.2 %s must begin with %s, got %s" % [label, prefix, value])


func _fail(message: String) -> bool:
	push_error(message)
	return false
